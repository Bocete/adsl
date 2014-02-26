require 'rubygems'
require 'active_support'
require 'pp'
require 'set'
require 'adsl/ds/data_store_spec'
require 'adsl/util/general'

class Array
  def optimize
    map do |e|
      e.respond_to?(:optimize) ? e.optimize : e
    end
  end
end

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

        if options.include?(:node_type) and !options.include?(:node_types)
          options[:node_types] = [options[:node_type]]
        end
        if options.include?(:node_types)
          @is_statement = options[:node_types].include? :statement
          @is_objset    = options[:node_types].include? :objset
          @is_formula   = options[:node_types].include? :formula
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
          new_value = child.respond_to?(:optimize) ? child.optimize : child.dup
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

      # used for statistics
      def adsl_ast_size
        sum = 1
        self.class.container_for_fields.each do |field_name|
          field = send field_name
          if field.is_a? Array
            field.flatten.each do |subfield|
              sum += subfield.adsl_ast_size if subfield.respond_to? :adsl_ast_size
            end
          else
            sum += field.adsl_ast_size if field.respond_to? :adsl_ast_size
          end
        end
        sum
      end
    end

    class ADSLError < StandardError; end

    class ASTDummyObjset < ASTNode
      node_type :type_sig, :node_type => :objset

      def typecheck_and_resolve(context)
        self
      end

      def to_adsl
        "DummyObjset(#{ @type_sig })"
      end
    end

    class ASTDummyStmt < ASTNode
      node_type :label, :node_type => :statement

      def typecheck_and_resolve(context)
      end

      def to_adsl
        "DummyStmt(#{ @label })\n"
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
        context.classes.values.each do |class_node, klass|
          class_node.parent_names.map(&:text).each do |parent_name|
            parent_node, parent = context.classes[parent_name]
            raise ADSLError, "Unknown parent class name #{parent_name} for class #{class_node.name.text}" if parent.nil?
            klass.parents << parent
          end
        end

        context.classes.values.each do |class_node, klass|
          raise ADSLError, "Cyclic inheritance detected with class #{klass.name}" if klass.all_parents.include? klass
        end

        # make sure relations are valid and refer to existing classes
        context.classes.values.each do |class_node, klass|
          class_node.relations.each do |rel_node|
            klass.all_parents(true).each do |superclass|
              if context.relations[superclass.name].include? rel_node.name.text
                raise ADSLError, "Duplicate relation name '#{class_node.name.text}' under class '#{klass.name}' on line #{rel_node.lineno} (first definition on line #{context.relations[superclass.name][rel_node.name.text][0].lineno}"
              end
            end
            
            rel = ADSL::DS::DSRelation.new :name => rel_node.name.text, :from_class => klass
            context.relations[klass.name][rel.name] = [rel_node, rel]
            klass.relations << rel
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

      def adsl_ast_size(options = {})
        sum = 1
        @classes.each do |c|
          sum += c.adsl_ast_size
        end
        actions = options[:action_name].nil? ? @actions : @actions.select{ |a| a.name.text == options[:action_name] }
        actions.each do |a|
          sum += options[:pre_optimize] ? a.pre_optimize_adsl_ast_size : a.adsl_ast_size
        end
        invs = options[:invariant_name].nil? ? @invariants : @invariants.select{ |a| a.name.text == options[:invariant_name] }
        invs.each do |i|
          sum += i.adsl_ast_size
        end
        sum
      end
    end
    
    class ASTClass < ASTNode
      node_type :name, :parent_names, :relations

      def typecheck_and_resolve(context)
        klass = context.classes[@name.text][1]
        @relations.each do |rel_node|
          rel = context.relations[@name.text][rel_node.name.text][1]
          
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
            target_rel = (Set[target_class] + target_class.all_parents).map{ |klass| klass.relations }.flatten.select{ |rel| rel.name == rel_node.inverse_of_name.text}.first
           
            if target_rel.nil?
              raise ADSLError, "Unknown relation to which #{rel.from_class.name}.#{rel.name} relation is inverse to: #{rel.to_class.name}.#{rel_node.inverse_of_name.text} on line #{rel_node.inverse_of_name.lineno}"
            end

            rel.inverse_of = target_rel

            if target_rel.inverse_of
              raise ADSLError, "Relation #{rel.from_class.name}.#{rel.name} cannot be inverse to an inverse relation #{rel.to_class.name}.#{rel_node.inverse_of_name.text} on line #{rel_node.inverse_of_name.lineno}"
            end
          end
        end
      end

      def to_adsl
        par_names = @parent_names.empty? ? "" : "extends #{@parent_names.map(&:text).join(', ')} "
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
        
          if old_var.type_sig.nil_sig?
            # nothing
          elsif var.type_sig.nil_sig?
            var.type_sig = old_var.type_sig
          elsif var.type_sig != old_var.type_sig
            raise ADSLError, "Unmatched type signatures '#{ old_var.type_sig }' and  '#{ var.type_sig }' for variable '#{var.name}' on line #{node.lineno}"
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
    
      def find_relation(from_type_sig, rel_name, lineno, to_type_sig=nil)
        origin_classes = from_type_sig.all_parents(true).map(&:name)
        relation_map = @relations.select{ |klass_name, rel_map| origin_classes.include? klass_name }.values.inject(&:merge) || {}
        
        unless relation_map.include? rel_name
          raise ADSLError, "Unknown relation #{rel_name} from type signature #{from_type_sig} on line #{lineno}"
        end

        relation = relation_map[rel_name][1]
        
        if to_type_sig && !(relation.to_class.to_sig >= to_type_sig)
          raise ADSLError, "Mismatched right-hand-side type for relation #{from_type_sig}.#{rel_name} on line #{lineno}. Expected #{to_type_sig} but was #{relation.to_class.to_sig}"
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
            var = ADSL::DS::DSVariable.new :name => @arg_names[i].text, :type_sig => klass.to_sig
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
        copy = dup
        copy.instance_variable_set :@pre_optimize_adsl_ast_size, copy.adsl_ast_size

        copy.block = until_no_change(copy.block) do |block|
          block = block.optimize(true)

          variables_read = []
          block.preorder_traverse do |node|
            next unless node.is_a? ASTVariable
            variables_read << node.var_name.text
          end
          block.block_replace do |node|
            next unless node.is_a? ASTAssignment
            next if node.var_name.nil? || variables_read.include?(node.var_name.text)
            node.objset
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

      def pre_optimize_adsl_ast_size
        @pre_optimize_adsl_ast_size || adsl_ast_size
      end

      def prepend_global_variables_by_signatures(*regexes)
        variable_names = []
        preorder_traverse do |node|
          next unless node.is_a? ASTVariable
          name = node.var_name.text
          variable_names << name if regexes.map{ |r| r =~ name ? true : false }.include? true
        end
        variable_names.each do |name|
          @block.statements.unshift ASTObjsetStmt.new(:objset => ASTAssignment.new(
            :var_name => ASTIdent.new(:text => name),
            :objset => ASTEmptyObjset.new
          ))
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
      node_type :statements, :node_type => :statement

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

      def optimize(last_stmt = false)
        until_no_change super() do |block|
          next block if block.statements.empty?

          statements = block.statements.map(&:optimize).map{ |stmt|
            stmt.is_a?(ASTBlock) ? stmt.statements : [stmt]
          }.flatten(1).reject{ |stmt|
            stmt.is_a?(ASTDummyStmt)
          }

          if last_stmt
            if statements.last.is_a?(ASTEither)
              statements.last.blocks.map!{ |b| b.optimize true }
              statements[-1] = statements.last.optimize
            elsif statements.last.is_a?(ASTBlock)
              last = statements.pop.optimize true
              statements += last.statements
            end
          end

          ASTBlock.new(:statements => statements)
        end
      end

      def to_adsl
        @statements.map(&:to_adsl).join
      end
    end

    class ASTAssignment < ASTNode
      node_type :var_name, :objset, :node_type => :objset
      
      def objset_has_side_effects?; true; end

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        @var = ADSL::DS::DSVariable.new :name => @var_name.text, :type_sig => objset.type_sig
        context.redefine_var @var, @var_name
        create_prestmt = ADSL::DS::DSAssignment.new :var => @var, :objset => objset
        context.pre_stmts << create_prestmt
        @var
      end

      def to_adsl
        "#{ @var_name.text } = #{ @objset.to_adsl }"
      end
    end

    class ASTDeclareVar < ASTNode
      node_type :var_name, :node_type => :statement

      def typecheck_and_resolve(context)
        var = context.lookup_var @var_name.text, false
        if var.nil?
          ASTObjsetStmt.new(
            :objset => ASTAssignment.new(:var_name => @var_name.dup, :objset => ASTEmptyObjset.new).typecheck_and_resolve(context)
          )
        else
          []
        end
      end

      def to_adsl
        "declare #{ @var_name.text }\n"
      end
    end

    class ASTObjsetStmt < ASTNode
      node_type :objset, :node_type => :statement

      def typecheck_and_resolve(context)
        @objset.typecheck_and_resolve(context)
        return nil
      end

      def optimize(last_stmt = false)
        @objset.objset_has_side_effects? ? self : ASTDummyStmt.new
      end

      def to_adsl
        "#{ @objset.to_adsl }\n"
      end
    end

    class ASTCreateObjset < ASTNode
      node_type :class_name, :node_type => :objset
      
      def objset_has_side_effects?; true; end

      def typecheck_and_resolve(context)
        klass_node, klass = context.classes[@class_name.text]
        raise ADSLError, "Undefined class #{@class_name.text} referred to at line #{@class_name.lineno}" if klass.nil?
        if @create_obj.nil?
          @create_obj = ADSL::DS::DSCreateObj.new :klass => klass
          context.pre_stmts << @create_obj
        end
        ADSL::DS::DSCreateObjset.new :createobj => @create_obj
      end

      def to_adsl
        "create(#{ @class_name.text })"
      end
    end

    class ASTForEach < ASTNode
      node_type :var_name, :objset, :block, :node_type => :statement

      def typecheck_and_resolve(context)
        before_context = context.dup
        objset = @objset.typecheck_and_resolve context

        temp_iterator_objset = ASTDummyObjset.new :type_sig => objset.type_sig
        assignment = ASTObjsetStmt.new(
          :objset => ASTAssignment.new(:lineno => @lineno, :var_name => @var_name, :objset => temp_iterator_objset)
        )
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

        # this should be a runtime check of dependencies etc
        flat = true

        if flat
          for_each = ADSL::DS::DSFlatForEach.new :objset => objset, :block => block
        else
          for_each = ADSL::DS::DSForEach.new :objset => objset, :block => block
        end

        vars_read_before_being_written_to.each do |var_name|
          before_var_node, before_var = before_context.lookup_var var_name, false
          inside_var_node, inside_var = context.lookup_var var_name, false
          lambda_objset = ADSL::DS::DSForEachPreLambdaObjset.new :for_each => for_each, :before_var => before_var, :inside_var => inside_var
          var = ADSL::DS::DSVariable.new :name => var_name, :type_sig => before_var.type_sig
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

      def optimize
        optimized = super
        if optimized.block.statements.empty?
          return ASTObjsetStmt.new(:objset => optimized.objset).optimize
        end
        optimized
      end

      def to_adsl
        "foreach #{ @var_name.text } : #{ @objset.to_adsl } {\n#{ @block.to_adsl.adsl_indent }}\n"
      end
    end

    class ASTEither < ASTNode
      node_type :blocks, :node_type => :statement

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

        ASTTypecheckResolveContext::context_vars_that_differ(*contexts).each do |var_name, objsets|
          type_sig = ADSL::DS::DSTypeSig.join objsets.map(&:type_sig)
          var = ADSL::DS::DSVariable.new :name => var_name, :type_sig => type_sig
          objset = ADSL::DS::DSEitherLambdaObjset.new :either => either, :objsets => objsets
          assignment = ADSL::DS::DSAssignment.new :var => var, :objset => objset
          context.redefine_var var, nil
          lambdas << assignment
        end

        return [ either, lambdas ]
      end

      def list_entity_classes_written_to
        @blocks.map(&:list_entity_classes_written_to).flatten
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

    class ASTIf < ASTNode
      node_type :condition, :then_block, :else_block, :node_type => :statement

      def blocks
        [@then_block, @else_block]
      end

      def typecheck_and_resolve(context)
        context.push_frame
        
        condition = @condition.typecheck_and_resolve(context)
        
        pre_stmts = context.pre_stmts
        context.pre_stmts = []

        context.push_frame
        
        contexts = [context, context.dup]
        blocks = [@then_block.typecheck_and_resolve(contexts[0]), @else_block.typecheck_and_resolve(contexts[1])]
        contexts.each{ |c| c.pop_frame; c.pop_frame }

        ds_if = ADSL::DS::DSIf.new :condition => condition, :then_block => blocks[0], :else_block => blocks[1]

        lambdas = []
        ASTTypecheckResolveContext::context_vars_that_differ(*contexts).each do |var_name, objsets|
          type_sig = ADSL::DS::DSTypeSig.join objsets.map(&:type_sig)
          var = ADSL::DS::DSVariable.new :name => var_name, :type_sig => type_sig
          objset = ADSL::DS::DSIfLambdaObjset.new :if => ds_if, :then_objset => objsets[0], :else_objset => objsets[1]
          assignment = ADSL::DS::DSAssignment.new :var => var, :objset => objset
          context.redefine_var var, nil
          lambdas << assignment
        end

        return [*pre_stmts, ds_if, lambdas]
      end

      def optimize
        until_no_change super do |if_node|
          next if_node.optimize unless if_node.is_a?(ASTIf)
          next ASTDummyStmt.new if blocks.map(&:statements).flatten.empty?
          if if_node.condition.is_a?(ASTBoolean)
            case if_node.condition.bool_value
            when true;  next if_node.then_block.optimize
            when false; next if_node.else_block.optimize
            when nil;   next ASTEither.new(:blocks => if_node.blocks).optimize
            end
          end
          ASTIf.new(
            :condition  => if_node.condition.optimize,
            :then_block => if_node.then_block.optimize,
            :else_block => if_node.else_block.optimize
          )
        end
      end

      def list_entity_classes_written_to
        [@then_block, @else_block].map(&:list_entity_classes_written_to).flatten
      end

      def to_adsl
        else_code = @else_block.statements.empty? ? "" : " else {\n#{ @else_block.to_adsl.adsl_indent }}"
        "if #{@condition.to_adsl} {\n#{ @then_block.to_adsl.adsl_indent }}#{ else_code }\n"
      end
    end

    class ASTDeleteObj < ASTNode
      node_type :objset, :node_type => :statement

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        return [] if objset.type_sig.nil_sig?
        return ADSL::DS::DSDeleteObj.new :objset => objset
      end

      def to_adsl
        "delete #{ @objset.to_adsl }\n"
      end
    end

    class ASTCreateTup < ASTNode
      node_type :objset1, :rel_name, :objset2, :node_type => :statement

      def typecheck_and_resolve(context)
        objset1 = @objset1.typecheck_and_resolve context
        objset2 = @objset2.typecheck_and_resolve context
        raise ADSLError, "Ambiguous type on the left hand side on line #{@objset1.lineno}" if objset1.type_sig.nil_sig?
        return [] if objset2.type_sig.nil_sig?
        relation = context.find_relation objset1.type_sig, @rel_name.text, @rel_name.lineno, objset2.type_sig
        return ADSL::DS::DSCreateTup.new :objset1 => objset1, :relation => relation, :objset2 => objset2
      end

      def to_adsl
        "#{ @objset1.to_adsl }.#{ @rel_name.text } += #{ @objset2.to_adsl }\n"
      end
    end

    class ASTDeleteTup < ASTNode
      node_type :objset1, :rel_name, :objset2, :node_type => :statement
      
      def typecheck_and_resolve(context)
        objset1 = @objset1.typecheck_and_resolve context
        objset2 = @objset2.typecheck_and_resolve context
        raise ADSLError, "Ambiguous type on the left hand side on line #{@objset1.lineno}" if objset1.type_sig.nil_sig?
        return [] if objset2.type_sig.nil_sig?
        relation = context.find_relation objset1.type_sig, @rel_name.text, @rel_name.lineno, objset2.type_sig
        return ADSL::DS::DSDeleteTup.new :objset1 => objset1, :relation => relation, :objset2 => objset2
      end

      def to_adsl
        "#{ @objset1.to_adsl }.#{ @rel_name.text } -= #{ @objset2.to_adsl }\n"
      end
    end

    class ASTSetTup < ASTNode
      node_type :objset1, :rel_name, :objset2, :node_type => :statement

      def typecheck_and_resolve(context)
        objset1 = @objset1.typecheck_and_resolve context
        objset2 = @objset2.typecheck_and_resolve context
        raise ADSLError, "Ambiguous type on the left hand side on line #{@objset1.lineno}" if objset1.type_sig.nil_sig?
        return [] if objset2.type_sig.nil_sig?
        relation = context.find_relation objset1.type_sig, @rel_name.text, @rel_name.lineno, objset2.type_sig
        return [
          ADSL::DS::DSDeleteTup.new(:objset1 => objset1, :relation => relation, :objset2 => ADSL::DS::DSAllOf.new(:klass => relation.to_class)),
          ADSL::DS::DSCreateTup.new(:objset1 => objset1, :relation => relation, :objset2 => objset2)
        ]
      end

      def to_adsl
        "#{ @objset1.to_adsl }.#{ @rel_name.text } = #{ @objset2.to_adsl }\n"
      end
    end

    class ASTAllOf < ASTNode
      node_type :class_name, :node_type => :objset

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
      node_type :objset, :node_type => :objset

      def objset_has_side_effects?
        @objset.nil? ? false : @objset.objset_has_side_effects?
      end

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        return ADSL::DS::DSEmptyObjset.new if objset.type_sig.nil_sig?
        return ADSL::DS::DSSubset.new :objset => objset
      end

      def optimize
        until_no_change super do |node|
          next node.optimize unless node.is_a?(ASTSubset)
          next node.objset if node.objset.is_a?(ASTSubset) || node.objset.is_a?(ASTOneOf)
          next ASTOneOf.new :objset => node.objset.objset if node.objset.is_a?(ASTForceOneOf)
          ASTSubset.new :objset => node.objset.optimize
        end
      end

      def to_adsl
        "subset(#{ @objset.to_adsl })"
      end
    end
    
    class ASTOneOf < ASTNode
      node_type :objset, :node_type => :objset
      
      def objset_has_side_effects?
        @objset.nil? ? false : @objset.objset_has_side_effects?
      end

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        return ADSL::DS::DSEmptyObjset.new if objset.type_sig.nil_sig?
        return ADSL::DS::DSOneOf.new :objset => objset
      end

      def optimize
        until_no_change super do |oneof|
          next oneof.optimize unless oneof.is_a?(ASTOneOf)
          next oneof.objset if oneof.objset.is_a?(ASTOneOf) || oneof.objset.is_a?(ASTSubset)
          ASTOneOf.new :objset => oneof.objset.optimize
        end
      end

      def to_adsl
        "oneof(#{ @objset.to_adsl })"
      end
    end

    class ASTForceOneOf < ASTNode
      node_type :objset, :node_type => :objset
      
      def objset_has_side_effects?
        @objset.nil? ? false : @objset.objset_has_side_effects?
      end

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        raise ADSLError, "Unknown forced oneof type at line #{lineno}" if objset.type_sig.nil_sig?
        return ADSL::DS::DSForceOneOf.new :objset => objset
      end

      def optimize
        until_no_change super do |oneof|
          next oneof.optimize unless oneof.is_a?(ASTForceOneOf)
          next oneof.objset if oneof.objset.is_a?(ASTOneOf) || oneof.objset.is_a?(ASTForceOneOf)
          ASTForceOneof.new :objset => oneof.objset.optimize
        end
      end

      def to_adsl
        "oneof(#{ @objset.to_adsl })"
      end
    end
    
    class ASTUnion < ASTNode
      node_type :objsets, :node_type => :objset
      
      def objset_has_side_effects?
        @objsets.nil? ? false : @objsets.map{ |o| o.objset_has_side_effects? }.include?(true)
      end

      def typecheck_and_resolve(context)
        objsets = @objsets.map{ |o| o.typecheck_and_resolve context }
        objsets.reject!{ |o| o.type_sig.nil_sig? }
        
        return ADSL::DS::DSEmptyObjset.new if objsets.length == 0
        return objsets.first if objsets.length == 1

        # will raise an error if no single common supertype exists
        ADSL::DS::DSTypeSig.join objsets.map(&:type_sig)

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
      node_type :objsets, :node_type => :objset
      
      def objset_has_side_effects?
        @objsets.nil? ? false : @objsets.map{ |o| o.objset_has_side_effects? }.include?(true)
      end

      def typecheck_and_resolve(context)
        objsets = @objsets.map{ |o| o.typecheck_and_resolve context }
        
        # will raise an error if no single common supertype exists
        ADSL::DS::DSTypeSig.join objsets.map(&:type_sig)
        
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
          if !o.is_a?(ASTOneOfObjset)
            o
          elsif o.objsets.empty?
            ASTEmptyObjset.new
          elsif o.objsets.length == 1
            o.objsets.first
          else
            ASTOneOfObjset.new(:objsets => o.objsets.uniq)
          end
        end
      end

      def to_adsl
        "any_of(#{ @objsets.map(&:to_adsl).join ', ' })"
      end
    end
    
    class ASTVariable < ASTNode
      node_type :var_name, :node_type => :objset

      def typecheck_and_resolve(context)
        var_node, var = context.lookup_var @var_name.text
        raise ADSLError, "Undefined variable #{@var_name.text} on line #{@var_name.lineno}" if var.nil?
        var
      end

      def to_adsl
        @var_name.text
      end
    end

    class ASTDereference < ASTNode
      node_type :objset, :rel_name, :node_type => :objset
      
      def objset_has_side_effects?
        @objset.nil? ? false : @objset.objset_has_side_effects?
      end

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        raise ADSLError, 'Empty objset dereference' if objset.type_sig.nil_sig?
        relation = context.find_relation objset.type_sig, @rel_name.text, @rel_name.lineno
        return ADSL::DS::DSDereference.new :objset => objset, :relation => relation
      end

      def to_adsl
        "#{ @objset.to_adsl }.#{ rel_name.text }"
      end
    end

    class ASTDereferenceCreate < ASTNode
      node_type :objset, :rel_name, :empty_first, :node_type => :objset

      def objset_has_side_effects?; true; end

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        raise ADSLError, 'Cannot create an object on an empty objset' if objset.type_sig.nil_sig?
        relation = context.find_relation objset.type_sig, @rel_name.text, @rel_name.lineno
       
        create_objset = ASTCreateObjset.new(
          :class_name => ASTIdent.new(:text => relation.to_class.name)
        )
        
        assoc_builder = (@empty_first ? ASTSetTup : ASTCreateTup).new(
          :objset1 => @objset,
          :rel_name => @rel_name,
          :objset2 => create_objset
        )
        context.pre_stmts << assoc_builder.typecheck_and_resolve(context)

        create_objset.typecheck_and_resolve(context)
      end

      def to_adsl
        "derefcreate(#{@objset.to_adsl}.#{@rel_name.text})"
      end
    end

    class ASTEmptyObjset < ASTNode
      node_type :node_type => :objset

      def typecheck_and_resolve(context)
        return ADSL::DS::DSEmptyObjset.new
      end

      def to_adsl
        "empty"
      end
    end

    class ASTInvariant < ASTNode
      node_type :name, :formula, :node_type => :formula

      def typecheck_and_resolve(context)
        @formula.preorder_traverse do |node|
          if node.class.is_objset?
            raise ADSLError, "Object set cannot have sideeffects at line #{node.lineno}" if node.objset_has_side_effects?
          end
          if node.class.is_a?(ASTBoolean)
            raise ADSLError, "Star cannot be used in invariants (line #{node.lineno})" if node.bool_value.nil?
          end
          node
        end
        
        formula = @formula.typecheck_and_resolve context
        name = @name.nil? ? nil : @name.text
            
        return ADSL::DS::DSInvariant.new :name => name, :formula => formula
      end

      def optimize
        until_no_change super do |node|
          node.formula = node.formula.optimize
        end
      end

      def to_adsl
        n = (@name.nil? || @name.text.nil?) ? "" : "#{ @name.text.gsub(/\s/, '_') }: "
        "invariant #{n}#{ @formula.to_adsl }\n"
      end
    end

    class ASTBoolean < ASTNode
      node_type :bool_value, :node_type => :formula

      def typecheck_and_resolve(context)
        case @bool_value
        when true;  ADSL::DS::DSBoolean::TRUE
        when false; ADSL::DS::DSBoolean::FALSE
        when nil;   ADSL::DS::DSBoolean::UNKNOWN
        else raise "Unknown bool value #{@bool_value}"
        end
      end

      def optimize
        self
      end

      def to_adsl
        "#{ @bool_value }"
      end
    end

    class ASTForAll < ASTNode
      node_type :vars, :subformula, :node_type => :formula

      def typecheck_and_resolve(context)
        context.in_stack_frame do
          vars = []
          objsets = []
          @vars.each do |var_node, objset_node|
            objset = objset_node.typecheck_and_resolve context
        
            var = ADSL::DS::DSQuantifiedVariable.new :name => var_node.text, :type_sig => objset.type_sig
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

      def optimize
        until_no_change super do |node|
          next node.optimize unless node.is_a?(ASTForAll)
          next node.subformula if node.subformula.is_a?(ASTBoolean)
          ASTForAll.new(
            :vars       => node.vars.map{ |var, objset| [var, objset.optimize] },
            :subformula => node.subformula.optimize
          )
        end
      end
    end

    class ASTExists < ASTNode
      node_type :vars, :subformula, :node_type => :formula

      def typecheck_and_resolve(context)
        context.in_stack_frame do
          vars = []
          objsets = []
          @vars.each do |var_node, objset_node|
            objset = objset_node.typecheck_and_resolve context
            
            var = ADSL::DS::DSQuantifiedVariable.new :name => var_node.text, :type_sig => objset.type_sig
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

      def optimize
        until_no_change super do |node|
          next node.optimize unless node.is_a?(ASTEither)
          ASTExists.new(
            :vars       => node.vars.map{ |var, objset| [var, objset.optimize] },
            :subformula => node.subformula.optimize
          )
        end
      end
    end

    class ASTNot < ASTNode
      node_type :subformula, :node_type => :formula

      def typecheck_and_resolve(context)
        subformula = @subformula.typecheck_and_resolve context
        return ADSL::DS::DSNot.new :subformula => subformula
      end

      def to_adsl
        "not(#{ @subformula.to_adsl })"
      end

      def optimize
        until_no_change super do |node|
          next node.optimize unless node.is_a?(ASTNot)
          next node.subformula.subformula if node.subformula.is_a?(ASTNot)
          if node.subformula.is_a?(ASTBoolean)
            if [true, false].include?(node.subformula.bool_value)
              next ASTBoolean.new :bool_value => !node.subformula.bool_value
            end
            next node.subformula
          end
          next node
        end
      end
    end

    class ASTAnd < ASTNode
      node_type :subformulae, :node_type => :formula

      def typecheck_and_resolve(context)
        subformulae = @subformulae.map{ |o| o.typecheck_and_resolve context }
        return ADSL::DS::DSAnd.new :subformulae => subformulae
      end

      def optimize
        until_no_change super do |node|
          next node.optimize unless node.is_a?(ASTAnd)
          formulae = []
          node.subformulae.each do |subf|
            subf = subf.optimize
            if subf.is_a?(ASTAnd)
              formulae += subf.subformulae
            else
              formulae << subf
            end
          end
          formulae.delete_if{ |subf| subf.is_a?(ASTBoolean) && subf.bool_value == true }
          unless formulae.select{ |subf| subf.is_a?(ASTBoolean) && subf.bool_value == false }.empty?
            next ASTBoolean.new(:bool_value => false)
          end
          next formulae.first if formulae.length == 1
          next ASTBoolean.new(:bool_value => true) if formulae.empty?
          ASTAnd.new :subformulae => formulae
        end
      end

      def to_adsl
        "and(#{ @subformulae.map(&:to_adsl).join ", " })"
      end
    end
    
    class ASTOr < ASTNode
      node_type :subformulae, :node_type => :formula

      def typecheck_and_resolve(context)
        subformulae = @subformulae.map{ |o| o.typecheck_and_resolve context }
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
      
      def optimize
        until_no_change super do |node|
          next node.optimize unless node.is_a?(ASTOr)
          formulae = []
          node.subformulae.each do |subf|
            subf = subf.optimize
            if subf.is_a?(ASTOr)
              formulae += subf.subformulae
            else
              formulae << subf
            end
          end
          formulae.delete_if{ |subf| subf.is_a?(ASTBoolean) && subf.bool_value == false }
          unless formulae.select{ |subf| subf.is_a?(ASTBoolean) && subf.bool_value == true }.empty?
            next ASTBoolean.new(:bool_value => true)
          end
          next formulae.first if formulae.length == 1
          next ASTBoolean.new(:bool_value => false) if formulae.empty?
          ASTAnd.new :subformulae => formulae
        end
      end

      def to_adsl
        "or(#{ @subformulae.map(&:to_adsl).join ", " })"
      end
    end

    class ASTEquiv < ASTNode
      node_type :subformulae, :node_type => :formula

      def typecheck_and_resolve(context)
        subformulae = @subformulae.map{ |o| o.typecheck_and_resolve context }
        return ADSL::DS::DSEquiv.new :subformulae => subformulae
      end

      def optimize
        until_no_change super do |node|
          next node.optimize unless node.is_a?(ASTEquiv)
          subfs = node.subformulae.map(&:optimize).uniq
          if subfs.select{ |subf| subf.is_a?(ASTBoolean) && subf.bool_value == true }
            next ASTAnd.new(:subformulae => subfs).optimize
          end
          if subfs.select{ |subf| subf.is_a?(ASTBoolean) && subf.bool_value == false }
            next ASTAnd.new(:subformulae => subfs.map{ |subf| ASTNot.new(:subformula => subf) }).optimize
          end
          next subfs.first if subfs.length == 1
          ASTEquiv.new :subformulae => subfs
        end
      end

      def to_adsl
        "equiv(#{ @subformulae.map(&:to_adsl).join ", " })"
      end
    end

    class ASTImplies < ASTNode
      node_type :subformula1, :subformula2, :node_type => :formula

      def typecheck_and_resolve(context)
        subformula1 = @subformula1.typecheck_and_resolve context
        subformula2 = @subformula2.typecheck_and_resolve context
        return ADSL::DS::DSImplies.new :subformula1 => subformula1, :subformula2 => subformula2
      end

      def to_adsl
        "implies(#{ @subformula1.to_adsl }, #{ @subformula2.to_adsl })"
      end
    end

    class ASTEqual < ASTNode
      node_type :objsets, :node_type => :formula
      
      def typecheck_and_resolve(context)
        objsets = @objsets.map{ |o| o.typecheck_and_resolve context }

        # will raise an error if no single common supertype exists
        ADSL::DS::DSTypeSig.join objsets.map(&:type_sig)
          
        return ADSL::DS::DSEqual.new :objsets => objsets
      end
      
      def to_adsl
        "equal(#{ @objsets.map(&:to_adsl).join ", " })"
      end
    end

    class ASTIn < ASTNode
      node_type :objset1, :objset2, :node_type => :formula

      def typecheck_and_resolve(context)
        objset1 = @objset1.typecheck_and_resolve context
        objset2 = @objset2.typecheck_and_resolve context
        
        return ADSL::DS::Boolean::TRUE if objset1.type_sig.nil_sig?
        return ADSL::DS::DSEmpty.new :objset => objset1 if objset2.type_sig.nil_sig?

        unless objset1.type_sig <= objset2.type_sig
          raise ADSLError, "Object sets are not of compatible types: #{objset1.type_sig} and #{objset2.type_sig}"
        end
        return ADSL::DS::DSIn.new :objset1 => objset1, :objset2 => objset2
      end
      
      def to_adsl
        "#{ @objset1.to_adsl } in #{ @objset2.to_adsl }"
      end
    end
    
    class ASTIsEmpty < ASTNode
      node_type :objset, :node_type => :formula

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        return ADSL::DS::Boolean::TRUE if objset.type_sig.nil_sig?
        return ADSL::DS::DSIsEmpty.new :objset => objset
      end

      def to_adsl
        "isempty(#{ @objset.to_adsl })"
      end
    end
  end
end
