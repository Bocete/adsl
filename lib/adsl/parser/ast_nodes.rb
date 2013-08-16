require 'rubygems'
require 'active_support'
require 'pp'
require 'set'
require 'adsl/ds/data_store_spec'
require 'adsl/util/general'

module ADSL
  module Parser
   
    class ASTNode
      def self.is_statement?
        @is_statement
      end

      def self.is_objset?
        @is_objset
      end

      def self.is_formula?
        @is_formula
      end

      def objset_has_side_effects?
        false
      end

      def self.node_type(*fields)
        options = {}
        if fields.last.is_a? Hash
          options.merge! fields.pop
        end

        if options.include?(:type) and !options.include?(:types)
          options[:types] = [options[:type]]
        end
        if options.include?(:types)
          @is_statement = options[:types].include? :statement
          @is_objset = options[:types].include? :objset
          @is_formula = options[:types].include? :formula
        end

        container_for *fields
        container_for :lineno
      end

      def adsl_ast
        self
      end

      def optimize
        copy = self.dup
        children = self.class.container_for_fields.map{ |field_name| [field_name, copy.send(field_name)] }
        until children.empty?
          child_name, child = children.pop
          new_value = if child.is_a? Array
            child.map{ |c| c.optimize }
          elsif child.respond_to?(:optimize)
            child.optimize
          else
            child.respond_to?(:dup) ? child.dup : child
          end
          copy.send "#{child_name}=", new_value unless new_value.equal? child
        end
        copy
      end

      def dup
        new_values = {}
        self.class.container_for_fields.each do |field_name|
          value = send field_name
          new_values[field_name] = if value.is_a?(Symbol) || value.nil?
            value
          else
            value.dup
          end
        end
        self.class.new new_values
      end

      def block_replace(&block)
        children = self.class.container_for_fields.map{ |field_name| [field_name, send(field_name)] }
        children.each do |name, value|
          new_value = if value.is_a? Array
            value.map do |e|
              new_e = e.block_replace(&block)
              new_e.nil? ? e.dup : new_e
            end
          elsif value.is_a? ASTNode
            new_value = value.block_replace(&block)
            new_value.nil? ? value.dup : new_value
          elsif value.is_a?(Symbol) || value.nil?
            value
          else
            value.dup
          end
          send("#{name}=", new_value) if new_value != value
        end
        new_value = block[self]
        new_value.nil? ? self.dup : new_value
      end

      def ==(other)
        return false unless self.class == other.class
        self.class.container_for_fields.each do |field_name|
          child1 = self.send field_name
          child2 = other.send field_name
          return false unless child1 == child2
        end
        true
      end
      alias_method :eql?, :==

      def hash
        [self.class, *self.class.container_for_fields.map{ |field_name| send field_name }].hash
      end

      def preorder_traverse(&block)
        self.class.container_for_fields.each do |field_name|
          field = send field_name
          if field.is_a? Array
            field.flatten.each do |subfield|
              subfield.preorder_traverse &block if subfield.respond_to? :preorder_traverse
            end
          else
            field.preorder_traverse &block if field.respond_to? :preorder_traverse
          end
        end
        block[self]
      end
    end

    class ADSLError < StandardError; end

    class ASTDummyObjset < ASTNode
      node_type :type, :type => :objset

      def typecheck_and_resolve(context)
        self
      end

      def to_adsl
        "DummyObjset(#{ @type })"
      end
    end

    class ASTDummyStmt < ASTNode
      node_type :type, :type => :statement

      def typecheck_and_resolve(context)
        self
      end

      def to_adsl
        "DummyStmt(#{ @type })\n"
      end
    end

    class ASTSpec < ASTNode
      node_type :classes, :actions, :invariants

      def typecheck_and_resolve
        context = ASTTypecheckResolveContext.new

        # make sure class names are unique
        @classes.each do |class_node|
          if context.classes.include? class_node.name.text
            raise ADSLError, "Duplicate class name '#{class_node.name.text}' on line #{class_node.name.lineno} (first definition on line #{context.classes[class_node.name.text][0].name.lineno}"
          end
          klass = ADSL::DS::DSClass.new :name => class_node.name.text
          context.classes[klass.name] = [class_node, klass]
        end

        # make sure the parent classes are declared properly and that the inheritance graph is non-cyclic
        parents = Hash.new{}
        context.classes.values.select{ |v| v[0].parent_name }.each do |class_node, klass|
          parent_node, parent = context.classes[class_node.parent_name.text]
          raise ADSLError, "Unknown parent class name #{class_node.parent_name.text} for class #{class_node.name.text} on line #{class_node.parent_name}" if parent.nil?
          klass.parent = parent

          parents[klass] = parent
          parent_chain = [klass]
          while parent != nil do
            if parent_chain.include? parent
              cyclic_chain = parent_chain.slice(parent_chain.index(parent), parent_chain.length) + [parent]
              raise ADSLError, "Cyclic inheritance detected: #{cyclic_chain.map{ |c| c.name }.join ' -> '}"
            end
            parent_chain << parent
            parent = parents[parent]
          end
        end

        # make sure relations are valid and refer to existing classes
        context.classes.values.each do |class_node, klass|
          class_node.relations.each do |rel_node|
            iter = klass
            while iter != nil
              if context.relations[iter.name].include? rel_node.name.text
                raise ADSLError, "Duplicate relation name '#{class_node.name.text}' under class '#{klass.name}' on line #{rel_node.lineno} (first definition on line #{context.relations[iter.name][rel_node.name.text][0].lineno}"
              end
              iter = iter.parent
            end
            rel = ADSL::DS::DSRelation.new :name => rel_node.name.text, :from_class => klass
            context.relations[klass.name][rel.name] = [rel_node, rel]
          end
        end

        # now that classes and rels are initialized, check them
        @classes.each do |class_node|
          class_node.typecheck_and_resolve context
        end

        @actions.each do |action_node|
          action_node.typecheck_and_resolve context
        end

        # make sure invariants have unique names; add names to unnamed invariants
        names = Set.new
        @invariants.each do |invariant_node|
          invariant = invariant_node.typecheck_and_resolve context
          if invariant.name && names.include?(invariant.name)
            raise ADSLError, "Duplicate invariant name #{invariant.name} on line #{invariant_node.lineno}"
          end
          name = invariant.name || "unnamed_line_#{invariant_node.lineno}"
          while names.include? name
            name = name.increment_suffix
          end
          invariant.name = name
          context.invariants << invariant
          names << name
        end

        @invariants.each do |invariant_node|
          invariant = invariant_node.typecheck_and_resolve context
        end

        ADSL::DS::DSSpec.new(
          :classes => context.classes.map{ |a, b| b[1] }, 
          :actions => context.actions.map{ |a, b| b[1] },
          :invariants => context.invariants.dup
        )
      end

      def to_adsl
        "#{ @classes.map(&:to_adsl).join }\n#{ @actions.map(&:to_adsl).join }\n#{ @invariants.map(&:to_adsl).join }"
      end
    end
    
    class ASTClass < ASTNode
      node_type :name, :parent_name, :relations

      def typecheck_and_resolve(context)
        klass = context.classes[@name.text][1]
        @relations.each do |rel_node|
          rel = context.relations[@name.text][rel_node.name.text][1]
          klass.relations << rel
          
          if rel_node.cardinality[0] > rel_node.cardinality[1]
            raise ADSLError, "Invalid cardinality of relation #{klass.name}.#{rel_node.name.text} on line #{rel_node.cardinality[2]}: minimum cardinality #{rel_node.cardinality[0]} must not be greater than the maximum cardinality #{rel_node.cardinality[1]}"
          end
          if rel_node.cardinality[1] == 0
            raise ADSLError, "Invalid cardinality of relation #{klass.name}.#{rel_node.name.text} on line #{rel_node.cardinality[2]}: maximum cardinality #{rel_node.cardinality[1]} must be positive"
          end
          unless context.classes.include? rel_node.to_class_name.text
            raise ADSLError, "Unknown class name #{rel_node.to_class_name.text} in relation #{klass.name}.#{rel_node.name.text} on line #{rel_node.to_class_name.lineno}"
          end

          rel.to_class = context.classes[rel_node.to_class_name.text][1]
          rel.cardinality = rel_node.cardinality
          if rel_node.inverse_of_name
            target_class = context.classes[rel.to_class.name][1]
            inverse_of_node, inverse_of = context.relations[target_class.name][rel_node.inverse_of_name.text]

            while inverse_of_node.nil?
              inverse_of_node, inverse_of = context.relations[target_class.name][rel_node.inverse_of_name.text]
              target_class = target_class.parent
              raise ADSLError, "Unknown relation to which #{rel.from_class.name}.#{rel.name} relation is inverse to: #{rel.to_class.name}.#{rel_node.inverse_of_name.text} on line #{rel_node.inverse_of_name.lineno}" if target_class.nil?
            end

            if inverse_of_node.inverse_of_name
              raise ADSLError, "Relation #{rel.from_class.name}.#{rel.name} cannot be inverse to an inverse relation #{rel.to_class.name}.#{rel_node.inverse_of_name.text} on line #{rel_node.inverse_of_name.lineno}"
            end
            rel.inverse_of = inverse_of
          end
        end
      end

      def to_adsl
        par_name = @parent_name.nil? ? "" : "extends #{@parent_name.text} "
        "class #{ @name.text } #{ par_name }{\n#{ @relations.map(&:to_adsl).adsl_indent }}\n"
      end
    end
    
    class ASTRelation < ASTNode
      node_type :cardinality, :to_class_name, :name, :inverse_of_name

      def to_adsl
        card_str = cardinality[1] == Float::INFINITY ? "#{cardinality[0]}+" : "#{cardinality[0]}..#{cardinality[1]}"
        inv_str = inverse_of_name.nil? ? "" : " inverseof #{inverse_of_name.text}"
        "#{ card_str } #{ @to_class_name.text } #{ @name.text }#{ inv_str }\n"
      end
    end

    class ASTIdent < ASTNode
      node_type :text
    end

    class ASTTypecheckResolveContext
      attr_accessor :classes, :relations, :actions, :invariants, :var_stack, :pre_stmts 

      class ASTStackFrame < ActiveSupport::OrderedHash
        attr_accessor :var_write_listeners
        attr_accessor :var_read_listeners
        
        def initialize
          super
          @var_write_listeners = []
          @var_read_listeners = []
        end
      
        def on_var_read(&block)
          listeners = @var_read_listeners
          listeners.push block
        end
        
        def on_var_write(&block)
          listeners = @var_write_listeners
          listeners.push block
        end

        def fire_write_event(name)
          listeners = @var_write_listeners
          listeners.each do |listener|
            listener.call name
          end
        end
        
        def fire_read_event(name)
          listeners = @var_read_listeners
          listeners.each do |listener|
            listener.call name
          end
        end
        
        def dup
          other = ASTStackFrame.new
          self.each do |key, val|
            other[key] = val.dup
          end
          other.var_write_listeners = @var_write_listeners.dup
          other.var_read_listeners = @var_read_listeners.dup
          other
        end

        def clone
          dup
        end
      end

      def initialize
        # name => [astnode, dsobj]
        @classes = ActiveSupport::OrderedHash.new

        # classname => name => [astnode, dsobj]
        @relations = ActiveSupport::OrderedHash.new{ |hash, key| hash[key] = ActiveSupport::OrderedHash.new }

        # stack of name => [astnode, dsobj]
        @actions = ActiveSupport::OrderedHash.new

        @invariants = []
        @var_stack = []
        @pre_stmts = []
      end

      def initialize_copy(source)
        super
        source.classes.each do |name, value|
          @classes[name] = value.dup
        end
        source.relations.each do |class_name, class_entry|
          entries = @relations[class_name]
          class_entry.each do |name, value|
            entries[name] = value.dup
          end
        end
        @actions = source.actions.dup
        @invariants = source.invariants.dup
        @var_stack = source.var_stack.map{ |frame| frame.dup }
        @pre_stmts = source.pre_stmts.map{ |stmt| stmt.dup }
      end
      
      def on_var_write(&block)
        @var_stack.last.on_var_write(&block)
      end
      
      def on_var_read(&block)
        @var_stack.last.on_var_read(&block)
      end

      def in_stack_frame
        push_frame
        yield
      ensure
        pop_frame
      end

      def push_frame
        @var_stack.push ASTStackFrame.new
      end

      def pop_frame
        @var_stack.pop
      end

      def define_var(var, node)
        raise ADSLError, "Defining variables on a stack with no stack frames" if @var_stack.empty?
        prev_var_node, prev_var = lookup_var var.name
        raise ADSLError, "Duplicate identifier '#{var.name}' on line #{node.lineno}; previous definition on line #{prev_var_node.lineno}" unless prev_var.nil?
        @var_stack.last[var.name] = [node, var]
        @var_stack.last.fire_write_event var.name
        return var
      end

      def redefine_var(var, node)
        @var_stack.length.times do |frame_index|
          frame = @var_stack[frame_index]
          next unless frame.include? var.name
          old_var = frame[var.name][1]
        
          if old_var.type.nil?
            # nothing?
          elsif var.type.nil?
            var.type = old_var.type
          elsif var.type != old_var.type
            raise ADSLError, "Unmatched type '#{var.type.name}' for variable '#{var.name}' on line #{node.lineno}"
          end

          frame[var.name][1] = var

          @var_stack[frame_index..-1].reverse.each do |subframe|
            subframe.fire_write_event var.name
          end
          
          return var
        end
        return define_var var, node
      end

      def lookup_var(name, fire_read_event=true)
        @var_stack.length.times do |index|
          frame = @var_stack[index]
          next if frame[name].nil?
          var = frame[name]

          if fire_read_event
            @var_stack[index..-1].reverse.each do |subframe|
              subframe.fire_read_event name
            end
          end

          # handle events here, none defined atm
          return var
        end
        nil
      end
    
      def find_relation(from_type, rel_name, lineno, to_type=nil)
        iter = from_type
        relation_node, relation = @relations[iter.name][rel_name]
        while relation.nil?
          iter = iter.parent
          raise ADSLError, "Unknown relation #{from_type.name}.#{rel_name} on line #{lineno}" if iter.nil?
          relation_node, relation = @relations[iter.name][rel_name]
        end
        
        unless to_type.nil?
          raise ADSLError, "Mismatched right-hand-side type for relation #{from_type.name}.#{rel_name} on line #{lineno}. Expected #{relation.to_class.name} but was #{to_type.name}" unless relation.to_class.superclass_of? to_type
        end

        relation
      end

      def self.context_vars_that_differ(*contexts)
        vars_per_context = []
        contexts.each do |context|
          vars_per_context << context.var_stack.inject(ActiveSupport::OrderedHash.new) { |so_far, frame| so_far.merge! frame }
        end
        all_vars = vars_per_context.map{ |c| c.keys }.flatten.uniq
        packed = ActiveSupport::OrderedHash.new
        all_vars.each do |v|
          packed[v] = vars_per_context.map{ |vpc| vpc[v][1] }
        end
        packed.delete_if { |v, vars| vars.uniq.length == 1 }
        packed
      end
    end

    class ASTAction < ASTNode
      node_type :name, :arg_cardinalities, :arg_names, :arg_types, :block

      def typecheck_and_resolve(context)
        old_action_node, old_action = context.actions[@name.text]
        raise ADSLError, "Duplicate action name #{@name.text} on line #{@name.lineno}; first definition on line #{old_action_node.name.lineno}" unless old_action.nil?
        arguments = []
        cardinalities = []
        block = nil
        context.in_stack_frame do
          @arg_names.length.times do |i|
            cardinality = @arg_cardinalities[i]
            if cardinality[0] > cardinality[1]
              raise ADSLError, "Invalid cardinality of argument #{@arg_names[i].text} of action #{@name.text} on line #{cardinality[2]}: minimum cardinality #{cardinality[0]} must not be greater than the maximum cardinality #{cardinality[1]}"
            end
            if cardinality[1] == 0
              raise ADSLError, "Invalid cardinality of relation #{@arg_names[i].text} of action #{@name.text} on line #{cardinality[2]}: maximum cardinality #{cardinality[1]} must be positive"
            end
            cardinality = cardinality.first 2

            klass_node, klass = context.classes[@arg_types[i].text]
            raise ADSLError, "Unknown class #{@arg_types[i].text} on line #{@arg_types[i].lineno}" if klass.nil?
            var = ADSL::DS::DSVariable.new :name => @arg_names[i].text, :type => klass
            context.define_var var, @arg_types[i]
            arguments << var
            cardinalities << cardinality
          end
          block = @block.typecheck_and_resolve context, false
        end
        action = ADSL::DS::DSAction.new :name => @name.text, :args => arguments, :cardinalities => cardinalities, :block => block
        context.actions[action.name] = [self, action]
        return action
      rescue Exception => e
        #pp @block
        new_ex = e.exception("#{e.message} in action #{@name.text}")
        new_ex.set_backtrace e.backtrace
        raise new_ex
      end

      def optimize
        copy = super

        copy.block = until_no_change(copy.block) do |block|
          block = block.optimize

          variables_read = []
          block.preorder_traverse do |node|
            next unless node.is_a? ASTVariable
            variables_read << node.var_name.text
          end
          block.block_replace do |node|
            next unless node.is_a? ASTAssignment
            next if node.var_name.nil? || variables_read.include?(node.var_name.text)
            ASTObjsetStmt.new :objset => node.objset
          end

          next block if block.statements.length != 1
          if block.statements.first.is_a? ASTEither
            either = block.statements.first
            either = ASTEither.new(:blocks => either.blocks.reject{ |subblock| subblock.statements.empty? })
            if either.blocks.length == 0
              ASTBlock.new(:statements => [])
            elsif either.blocks.length == 1
              either.blocks.first
            else
              ASTBlock.new(:statements => [either])
            end
          else
            block
          end
        end

        copy
      end

      def prepend_global_variables_by_signatures(*regexes)
        variable_names = []
        preorder_traverse do |node|
          next unless node.is_a? ASTVariable
          name = node.var_name.text
          variable_names << name if regexes.map{ |r| r =~ name ? true : false }.include? true
        end
        variable_names.each do |name|
          @block.statements.unshift ASTAssignment.new(
            :var_name => ASTIdent.new(:text => name),
            :objset => ASTEmptyObjset.new
          )
        end
      end

      def to_adsl
        args = []
        @arg_cardinalities.length.times do |index|
          card = @arg_cardinalities[index]
          type = @arg_types[index].text
          name = @arg_names[index].text

          card_str = card[1] == Float::INFINITY ? "#{card[0]}+" : "#{card[0]}..#{card[1]}"
          args << "#{card_str} #{type} #{name}"
        end
        "action #{@name.text}(#{ args.join ', ' }) {\n#{ @block.to_adsl.adsl_indent }}\n"
      end
    end

    class ASTBlock < ASTNode
      node_type :statements, :type => :statement

      def typecheck_and_resolve(context, open_subcontext=true)
        context.push_frame if open_subcontext
        stmts = []
        @statements.each do |node|
          main_stmt = node.typecheck_and_resolve context
          stmts += context.pre_stmts
          stmts << main_stmt unless main_stmt.nil?
          context.pre_stmts = []
        end
        return ADSL::DS::DSBlock.new :statements => stmts.flatten
      ensure
        context.pop_frame if open_subcontext
      end

      def optimize
        until_no_change super do |block|
          ASTBlock.new(:statements => block.statements.map{ |stmt|
            if stmt.is_a?(ASTBlock)
              stmt.statements
            elsif stmt.is_a?(ASTDummyStmt)
              []
            else
              [stmt]
            end
          }.flatten(1).reject{ |stmt|
            stmt.is_a?(ASTObjsetStmt) and !stmt.objset.objset_has_side_effects?
          }.map{ |stmt|
            stmt.optimize
          })
        end
      end

      def to_adsl
        @statements.map(&:to_adsl).join
      end
    end

    class ASTAssignment < ASTNode
      node_type :var_name, :objset, :type => :statement

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        @var = ADSL::DS::DSVariable.new :name => @var_name.text, :type => objset.type
        context.redefine_var @var, @var_name
        return ADSL::DS::DSAssignment.new :var => @var, :objset => objset
      end

      def to_adsl
        "#{ @var_name.text } = #{ @objset.to_adsl }\n"
      end
    end

    class ASTObjsetStmt < ASTNode
      node_type :objset, :type => :statement

      def typecheck_and_resolve(context)
        @objset.typecheck_and_resolve(context)
        return nil
      end

      def to_adsl
        "#{ @objset.to_adsl }\n"
      end
    end

    class ASTCreateObjset < ASTNode
      node_type :class_name, :type => :objset
      
      def objset_has_side_effects?
        true
      end

      def typecheck_and_resolve(context)
        klass_node, klass = context.classes[@class_name.text]
        raise ADSLError, "Undefined class #{@class_name.text} referred to at line #{@class_name.lineno}" if klass.nil?
        create_obj = ADSL::DS::DSCreateObj.new :klass => klass
        context.pre_stmts << create_obj
        ADSL::DS::DSCreateObjset.new :createobj => create_obj
      end

      def to_adsl
        "create(#{ @class_name.text })"
      end
    end

    class ASTForEach < ASTNode
      node_type :var_name, :objset, :block, :type => :statement

      def typecheck_and_resolve(context)
        before_context = context.dup
        objset = @objset.typecheck_and_resolve context
        
        temp_iterator_objset = ASTDummyObjset.new :type => objset.type
        assignment = ASTAssignment.new :lineno => @lineno, :var_name => @var_name, :objset => temp_iterator_objset
        @block.statements = [assignment, @block.statements].flatten
        
        vars_written_to = Set[]
        vars_read = Set[]
        vars_read_before_being_written_to = Set[]
        context.on_var_write do |name|
          vars_written_to << name
        end
        context.on_var_read do |name|
          var_node, var = context.lookup_var name, false
          vars_read_before_being_written_to << name unless
              vars_written_to.include?(name) or vars_read_before_being_written_to.include? name
          vars_read << name unless vars_read.include? name
        end

        context.push_frame
        block = @block.typecheck_and_resolve context
        context.pop_frame

        vars_read_before_being_written_to.each do |var_name|
          vars_read_before_being_written_to.delete var_name unless vars_written_to.include? var_name
        end

        flat = true
        # flat = false unless vars_read_before_being_written_to.empty?

        if flat
          for_each = ADSL::DS::DSFlatForEach.new :objset => objset, :block => block
        else
          for_each = ADSL::DS::DSForEach.new :objset => objset, :block => block
        end

        vars_read_before_being_written_to.each do |var_name|
          before_var_node, before_var = before_context.lookup_var var_name, false
          inside_var_node, inside_var = context.lookup_var var_name, false
          lambda_objset = ADSL::DS::DSForEachPreLambdaObjset.new :for_each => for_each, :before_var => before_var, :inside_var => inside_var
          var = ADSL::DS::DSVariable.new :name => var_name, :type => before_var.type
          assignment = ADSL::DS::DSAssignment.new :var => var, :objset => lambda_objset
          block.replace before_var, var
          block.statements.unshift assignment
        end
        
        iterator_objset = ADSL::DS::DSForEachIteratorObjset.new :for_each => for_each
        block.replace temp_iterator_objset, iterator_objset
        return for_each
      end

      def list_creations
        @block.list_creations
      end

      def to_adsl
        "foreach #{ @var_name.text } : #{ @objset.to_adsl } {\n#{ @block.to_adsl.adsl_indent }}\n"
      end
    end

    class ASTEither < ASTNode
      node_type :blocks, :type => :statement

      def typecheck_and_resolve(context)
        context.push_frame

        contexts = [context]
        (@blocks.length-1).times do
          contexts << context.dup
        end

        blocks = []
        @blocks.length.times do |i|
          blocks << @blocks[i].typecheck_and_resolve(contexts[i])
        end

        contexts.each do |c|
          c.pop_frame
        end

        either = ADSL::DS::DSEither.new :blocks => blocks

        lambdas = []

        ASTTypecheckResolveContext::context_vars_that_differ(*contexts).each do |var_name, vars|
          var = ADSL::DS::DSVariable.new :name => var_name, :type => vars.first.type
          objset = ADSL::DS::DSEitherLambdaObjset.new :either => either, :vars => vars
          assignment = ADSL::DS::DSAssignment.new :var => var, :objset => objset
          context.redefine_var var, nil
          lambdas << assignment
        end

        return [ either, lambdas ]
      end

      def list_entity_classes_written_to
        @blocks.map{ block.list_entity_classes_written_to }.flatten
      end

      def optimize
        until_no_change super do |either|
          next either.optimize unless either.is_a?(ASTEither)
          next ASTDummyStmt.new if either.blocks.empty?
          next either.blocks.first if either.blocks.length == 1
          ASTEither.new(:blocks => either.blocks.map{ |block|
            if block.statements.length == 1 && block.statements.first.is_a?(ASTEither)
              block.statements.first.blocks
            else
              [block]
            end
          }.flatten(1).uniq)
        end
      end

      def to_adsl
        "either #{ @blocks.map{ |b| "{\n#{ b.to_adsl.adsl_indent }}" }.join " or " }\n"
      end
    end

    class ASTDeleteObj < ASTNode
      node_type :objset, :type => :statement

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        return [] if objset.type.nil?
        return ADSL::DS::DSDeleteObj.new :objset => objset
      end


      def to_adsl
        "delete #{ @objset.to_adsl }\n"
      end
    end

    class ASTCreateTup < ASTNode
      node_type :objset1, :rel_name, :objset2, :type => :statement

      def typecheck_and_resolve(context)
        objset1 = @objset1.typecheck_and_resolve context
        objset2 = @objset2.typecheck_and_resolve context
        raise ADSLError, "Ambiguous type on the left hand side on line #{@objset1.lineno}" if objset1.type.nil?
        return [] if objset2.type.nil?
        relation = context.find_relation objset1.type, @rel_name.text, @rel_name.lineno, objset2.type
        return ADSL::DS::DSCreateTup.new :objset1 => objset1, :relation => relation, :objset2 => objset2
      end

      def to_adsl
        "#{ @objset1.to_adsl }.#{ @rel_name.text } += #{ @objset2.to_adsl }"
      end
    end

    class ASTDeleteTup < ASTNode
      node_type :objset1, :rel_name, :objset2, :type => :statement
      
      def typecheck_and_resolve(context)
        objset1 = @objset1.typecheck_and_resolve context
        objset2 = @objset2.typecheck_and_resolve context
        raise ADSLError, "Ambiguous type on the left hand side on line #{@objset1.lineno}" if objset1.type.nil?
        return [] if objset2.type.nil?
        relation = context.find_relation objset1.type, @rel_name.text, @rel_name.lineno, objset2.type 
        return ADSL::DS::DSDeleteTup.new :objset1 => objset1, :relation => relation, :objset2 => objset2
      end

      def to_adsl
        "#{ @objset1.to_adsl }.#{ @rel_name.text } -= #{ @objset2.to_adsl }"
      end
    end

    class ASTSetTup < ASTNode
      node_type :objset1, :rel_name, :objset2, :type => :statement

      def typecheck_and_resolve(context)
        objset1 = @objset1.typecheck_and_resolve context
        objset2 = @objset2.typecheck_and_resolve context
        raise ADSLError, "Ambiguous type on the left hand side on line #{@objset1.lineno}" if objset1.type.nil?
        return [] if objset2.type.nil?
        relation = context.find_relation objset1.type, @rel_name.text, @rel_name.lineno, objset2.type
        return [
          ADSL::DS::DSDeleteTup.new(:objset1 => objset1, :relation => relation, :objset2 => ADSL::DS::DSAllOf.new(:klass => relation.to_class)),
          ADSL::DS::DSCreateTup.new(:objset1 => objset1, :relation => relation, :objset2 => objset2)
        ]
      end

      def to_adsl
        "#{ @objset1.to_adsl }.#{ @rel_name.text } = #{ @objset2.to_adsl }"
      end
    end

    class ASTAllOf < ASTNode
      node_type :class_name, :type => :objset

      def typecheck_and_resolve(context)
        klass_node, klass = context.classes[@class_name.text]
        raise ADSLError, "Unknown class name #{@class_name.text} on line #{@class_name.lineno}" if klass.nil?
        return ADSL::DS::DSAllOf.new :klass => klass
      end

      def list_entity_classes_read
        Set[context.classes[@class_name.text]]
      end

      def to_adsl
        "allof(#{@class_name.text})"
      end
    end

    class ASTSubset < ASTNode
      node_type :objset, :type => :objset

      def objset_has_side_effects?
        @objset.nil? ? false : @objset.objset_has_side_effects?
      end

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        return ADSL::DS::DSEmptyObjset.new if objset.type.nil?
        return ADSL::DS::DSSubset.new :objset => objset
      end

      def optimize
        until_no_change super do |subset|
          subset.objset.is_a?(ASTSubset) ? subset.objset : subset
        end
      end

      def to_adsl
        "subset(#{ @objset.to_adsl })"
      end
    end
    
    class ASTOneOf < ASTNode
      node_type :objset, :type => :objset
      
      def objset_has_side_effects?
        @objset.nil? ? false : @objset.objset_has_side_effects?
      end

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        return ADSL::DS::DSEmptyObjset.new if objset.type.nil?
        return ADSL::DS::DSOneOf.new :objset => objset
      end

      def optimize
        until_no_change super do |oneof|
          oneof.objset.is_a?(ASTOneOf) ? oneof.objset : oneof
        end
      end

      def to_adsl
        "oneof(#{ @objset.to_adsl })"
      end
    end

    class ASTUnion < ASTNode
      node_type :objsets, :type => :objset
      
      def objset_has_side_effects?
        @objsets.nil? ? false : @objsets.map{ |o| o.objset_has_side_effects? }.include?(true)
      end

      def typecheck_and_resolve(context)
        objsets = @objsets.map{ |o| o.typecheck_and_resolve context }
        @objsets.reject!{ |o| o.type.nil? }

        return ADSL::DS::DSEmptyObjset.new if objsets.length == 0
        return objsets.first if objsets.length == 1

        types = objsets.map{ |o| o.type }
        # will raise an error if no single common supertype exists
        ADSL::DS::DSClass.common_supertype(types)

        return ADSL::DS::DSUnion.new :objsets => objsets
      end

      def optimize
        until_no_change super do |union|
          next ASTEmptyObjset.new if union.objsets.empty?
          next union.objsets.first if union.objsets.length == 1
          ASTUnion.new(:objsets => union.objsets.map{ |objset|
            objset.is_a?(ASTUnion) ? objset.objsets : [objset]
          }.flatten(1).reject{ |o| o.is_a? ASTEmptyObjset })
        end
      end

      def to_adsl
        "union(#{ @objsets.map(&:to_adsl).join(', ') })"
      end
    end

    class ASTOneOfObjset < ASTNode
      node_type :objsets, :type => :objset
      
      def objset_has_side_effects?
        @objsets.nil? ? false : @objsets.map{ |o| o.objset_has_side_effects? }.include?(true)
      end

      def typecheck_and_resolve(context)
        objsets = @objsets.map{ |o| o.typecheck_and_resolve context }
        common_type = ADSL::DS::DSClass.common_supertype objsets.reject{ |o| o.type.nil? }
        if objsets.length == 0
          ADSL::DS::DSEmptyObjset.new
        elsif objsets.length == 1
          objsets.first
        else
          ADSL::DS::DSOneOfObjset.new :objsets => objsets
        end
      end

      def optimize
        until_no_change super do |o|
          ASTEmpty.new if o.empty?
          o.objsets.first if o.objects.length == 1
          ASTOneOfObjset.new(:objsets => o.objsets.uniq)
        end
      end

      def to_adsl
        "any_of(#{ @objsets.map(&:to_adsl).join ', ' })"
      end
    end
    
    class ASTVariable < ASTNode
      node_type :var_name, :type => :objset

      def typecheck_and_resolve(context)
        var_node, var = context.lookup_var @var_name.text
        raise ADSLError, "Undefined variable #{@var_name.text} on line #{@var_name.lineno}" if var.nil?
        return ADSL::DS::DSEmptyObjset.new if var.type.nil?
        return var
      end

      def to_adsl
        @var_name.text
      end
    end

    class ASTDereference < ASTNode
      node_type :objset, :rel_name, :type => :objset
      
      def objset_has_side_effects?
        @objset.nil? ? false : @objset.objset_has_side_effects?
      end

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        klass = objset.type
        raise ADSLError, 'Empty objset dereference' if klass.nil?
        relation = context.find_relation objset.type, @rel_name.text, @rel_name.lineno
        return ADSL::DS::DSDereference.new :objset => objset, :relation => relation
      end

      def to_adsl
        "#{ @objset.to_adsl }.#{ rel_name.text }"
      end
    end

    class ASTEmptyObjset < ASTNode
      node_type

      def typecheck_and_resolve(context)
        return ADSL::DS::DSEmptyObjset.new
      end

      def to_adsl
        "empty"
      end
    end

    class ASTInvariant < ASTNode
      node_type :name, :formula, :type => :formula

      def typecheck_and_resolve(context)
        formula = @formula.typecheck_and_resolve context
        name = @name.nil? ? nil : @name.text
        return ADSL::DS::DSInvariant.new :name => name, :formula => formula
      end

      def to_adsl
        n = @name.nil? ? "" : "#{ @name.gsub(/\s/, '_').text }: "
        "invariant #{n}#{ @formula.to_adsl }\n"
      end
    end

    class ASTBoolean < ASTNode
      node_type :bool_value, :type => :formula

      def typecheck_and_resolve(context)
        return ADSL::DS::DSBoolean::TRUE if @bool_value
        return ADSL::DS::DSBoolean::FALSE
      end

      def to_adsl
        "#{ @bool_value }"
      end
    end

    class ASTForAll < ASTNode
      node_type :vars, :subformula, :type => :formula

      def typecheck_and_resolve(context)
        context.in_stack_frame do
          vars = []
          objsets = []
          @vars.each do |var_node, objset_node|
            objset = objset_node.typecheck_and_resolve context
            
            var = ADSL::DS::DSVariable.new :name => var_node.text, :type => objset.type
            context.define_var var, var_node

            vars << var
            objsets << objset
          end
          subformula = @subformula.typecheck_and_resolve context
          return ADSL::DS::DSForAll.new :vars => vars, :objsets => objsets, :subformula => subformula
        end
      end

      def to_adsl
        v = @vars.map{ |var, objset| "#{ var.text } in #{ objset.to_adsl }" }.join ", " 
        "forall(#{v}: #{ @subformula.to_adsl })"
      end
    end

    class ASTExists < ASTNode
      node_type :vars, :subformula, :type => :formula

      def typecheck_and_resolve(context)
        context.in_stack_frame do
          vars = []
          objsets = []
          @vars.each do |var_node, objset_node|
            objset = objset_node.typecheck_and_resolve context
            
            var = ADSL::DS::DSVariable.new :name => var_node.text, :type => objset.type
            context.define_var var, var_node

            vars << var
            objsets << objset
          end
          subformula = @subformula.nil? ? nil : @subformula.typecheck_and_resolve(context)
          return ADSL::DS::DSExists.new :vars => vars, :objsets => objsets, :subformula => subformula
        end
      end
      
      def to_adsl
        v = @vars.map{ |var, objset| "#{ var.text } in #{ objset.to_adsl }" }.join ", " 
        "exists(#{v}: #{ @subformula.to_adsl })"
      end
    end

    class ASTNot < ASTNode
      node_type :subformula, :type => :formula

      def typecheck_and_resolve(context)
        subformula = @subformula.typecheck_and_resolve context
        raise "Substatement not a formula on line #{@subformula.lineno}" unless subformula.type == :formula
        return subformula.subformula if subformula.is_a? ADSL::DS::DSNot
        return ADSL::DS::DSNot.new :subformula => subformula
      end

      def to_adsl
        "not(#{ @subformula.to_adsl })"
      end
    end

    class ASTAnd < ASTNode
      node_type :subformulae, :type => :formula

      def typecheck_and_resolve(context)
        subformulae = @subformulae.map{ |o| o.typecheck_and_resolve context }
        subformulae.each do |subformula|
          raise "Substatement not a formula on line #{subformula.lineno}" unless subformula.type == :formula  
        end
        flattened_subformulae = []
        subformulae.each do |subformula|
          if subformula.is_a? ADSL::DS::DSAnd
            flattened_subformulae += subformula.subformulae
          else
            flattened_subformulae << subformula
          end
        end
        return ADSL::DS::DSAnd.new :subformulae => flattened_subformulae
      end

      def to_adsl
        "and(#{ @subformulae.map(&:to_adsl).join ", " })"
      end
    end
    
    class ASTOr < ASTNode
      node_type :subformulae, :type => :formula

      def typecheck_and_resolve(context)
        subformulae = @subformulae.map{ |o| o.typecheck_and_resolve context }
        subformulae.each do |subformula|
          raise "Substatement not a formula on line #{subformula.lineno}" unless subformula.type == :formula  
        end
        flattened_subformulae = []
        subformulae.each do |subformula|
          if subformula.is_a? ADSL::DS::DSOr
            flattened_subformulae += subformula.subformulae
          else
            flattened_subformulae << subformula
          end
        end
        return ADSL::DS::DSOr.new :subformulae => flattened_subformulae
      end

      def to_adsl
        "or(#{ @subformulae.map(&:to_adsl).join ", " })"
      end
    end

    class ASTEquiv < ASTNode
      node_type :subformulae, :type => :formula

      def typecheck_and_resolve(context)
        subformulae = @subformulae.map{ |o| o.typecheck_and_resolve context }
        subformulae.each do |subformula|
          raise "Substatement not a formula on line #{subformula.lineno}" unless subformula.type == :formula  
        end
        return ADSL::DS::DSEquiv.new :subformulae => subformulae
      end

      def to_adsl
        "equiv(#{ @subformulae.map(&:to_adsl).join ", " })"
      end
    end

    class ASTImplies < ASTNode
      node_type :subformula1, :subformula2, :type => :formula

      def typecheck_and_resolve(context)
        subformula1 = @subformula1.typecheck_and_resolve context
        subformula2 = @subformula2.typecheck_and_resolve context
        
        [subformula1, subformula2].each do |subformula|
          raise "Substatement not a formula on line #{subformula.lineno}" unless subformula.type == :formula  
        end
        return ADSL::DS::DSImplies.new :subformula1 => subformula1, :subformula2 => subformula2
      end

      def to_adsl
        "implies(#{ @subformula1.to_adsl }, #{ @subformula2.to_adsl })"
      end
    end

    class ASTEqual < ASTNode
      node_type :objsets, :type => :formula
      
      def typecheck_and_resolve(context)
        objsets = @objsets.map{ |o| o.typecheck_and_resolve context }

        types = objsets.map{ |o| o.type }.select{ |o| not o.nil? }
        # will raise an error if no single common supertype exists
        ADSL::DS::DSClass.common_supertype(types)
          
        return ADSL::DS::DSEqual.new :objsets => objsets
      end
      
      def to_adsl
        "equal(#{ @objsets.map(&:to_adsl).join ", " })"
      end
    end

    class ASTIn < ASTNode
      node_type :objset1, :objset2, :type => :formula

      def typecheck_and_resolve(context)
        objset1 = @objset1.typecheck_and_resolve context
        objset2 = @objset2.typecheck_and_resolve context
        
        return ADSL::DS::Boolean::TRUE if objset1.type.nil?
        return ADSL::DS::DSEmpty.new :objset => objset1 if objset2.type.nil?
        
        raise ADSLError, "Object sets are not of compatible types: #{objset1.type.name}, #{objset2.type.name}" unless objset2.type.superclass_of? objset1.type
        return ADSL::DS::DSIn.new :objset1 => objset1, :objset2 => objset2
      end
      
      def to_adsl
        "#{ @objset1.to_adsl } in #{ @objset2.to_adsl }"
      end
    end
    
    class ASTEmpty < ASTNode
      node_type :objset, :type => :formula

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        return ADSL::DS::Boolean::TRUE if objset.type.nil?
        return ADSL::DS::DSEmpty.new :objset => objset
      end

      def to_adsl
        "empty(#{ @objset.to_adsl })"
      end
    end
  end
end
