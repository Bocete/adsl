require 'ds/data_store_spec'
require 'rubygems'
require 'active_support'
require 'util/util'
require 'pp'
require 'set'

module ADSL

  class ADSLNode
    def self.node_type(*fields)
      container_for *fields
      container_for :lineno
    end
  end

  class ADSLError < StandardError; end

  class ADSLDummyObjset < ADSLNode
    node_type :type

    def typecheck_and_resolve(context)
      self
    end
  end

  class ADSLSpec < ADSLNode
    node_type :classes, :actions, :invariants

    def typecheck_and_resolve
      context = ADSLTypecheckResolveContext.new

      # make sure class names are unique
      @classes.each do |class_node|
        if context.classes.include? class_node.name.text
          raise ADSLError, "Duplicate class name '#{class_node.name.text}' on line #{class_node.name.lineno} (first definition on line #{context.classes[class_node.name.text][0].name.lineno}"
        end
        klass = DS::DSClass.new :name => class_node.name.text
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
          rel = DS::DSRelation.new :name => rel_node.name.text, :from_class => klass
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

      DS::DSSpec.new(
        :classes => context.classes.map{ |a, b| b[1] }, 
        :actions => context.actions.map{ |a, b| b[1] },
        :invariants => context.invariants.dup
      )
    end
  end
  
  class ADSLClass < ADSLNode
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
  end
  
  class ADSLRelation < ADSLNode
    node_type :cardinality, :to_class_name, :name, :inverse_of_name
  end

  class ADSLIdent < ADSLNode
    node_type :text
  end

  class ADSLTypecheckResolveContext
    attr_accessor :classes, :relations, :actions, :invariants, :var_stack, :pre_stmts 

    class ADSLStackFrame < ActiveSupport::OrderedHash
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
        other = ADSLStackFrame.new
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
      @var_stack.push ADSLStackFrame.new
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
      
        raise ADSL::ADSLError, "Unmatched type '#{var.type.name}' for variable '#{var.name}' on line #{node.lineno}" if var.type != old_var.type

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

  class ADSLAction < ADSLNode
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
          var = DS::DSVariable.new :name => @arg_names[i].text, :type => klass
          context.define_var var, @arg_types[i]
          arguments << var
          cardinalities << cardinality
        end
        block = @block.typecheck_and_resolve context, false
      end
      action = DS::DSAction.new :name => @name.text, :args => arguments, :cardinalities => cardinalities, :block => block
      context.actions[action.name] = [self, action]
      return action
    end
  end

  class ADSLBlock < ADSLNode
    node_type :statements

    def typecheck_and_resolve(context, open_subcontext=true)
      context.push_frame if open_subcontext
      stmts = []
      @statements.each do |node|
        main_stmt = node.typecheck_and_resolve context
        stmts += context.pre_stmts
        stmts << main_stmt
        context.pre_stmts = []
      end
      return DS::DSBlock.new :statements => stmts.flatten
    ensure
      context.pop_frame if open_subcontext
    end
  end

  class ADSLAssignment < ADSLNode
    node_type :var_name, :objset

    def typecheck_and_resolve(context)
      objset = @objset.typecheck_and_resolve context
      @var = DS::DSVariable.new :name => @var_name.text, :type => objset.type
      context.redefine_var @var, @var_name
      return DS::DSAssignment.new :var => @var, :objset => objset
    end
  end

  class ADSLObjsetStmt < ADSLNode
    node_type :objset

    def typecheck_and_resolve(context)
      DS::DSObjsetStmt.new :objset => @objset.typecheck_and_resolve(context)
    end
  end

  class ADSLCreateObj < ADSLNode
    node_type :var_name, :class_name

    def typecheck_and_resolve(context)
      klass_node, klass = context.classes[@class_name.text]
      raise ADSLError, "Undefined class #{@class_name.text} referred to at line #{@class_name.lineno}" if klass.nil?
      create_obj = DS::DSCreateObj.new :klass => klass
      context.pre_stmts << create_obj
      DS::DSCreateObjset.new :createobj => create_obj
    end
  end

  class ADSLForEach < ADSLNode
    node_type :var_name, :objset, :block

    def typecheck_and_resolve(context)
      before_context = context.dup
      objset = @objset.typecheck_and_resolve context
      
      temp_iterator_objset = ADSL::ADSLDummyObjset.new :type => objset.type
      assignment = ADSL::ADSLAssignment.new :lineno => @lineno, :var_name => @var_name, :objset => temp_iterator_objset
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
        for_each = DS::DSFlatForEach.new :objset => objset, :block => block
      else
        for_each = DS::DSForEach.new :objset => objset, :block => block
      end

      vars_read_before_being_written_to.each do |var_name|
        before_var_node, before_var = before_context.lookup_var var_name, false
        inside_var_node, inside_var = context.lookup_var var_name, false
        lambda_objset = DS::DSForEachPreLambdaObjset.new :for_each => for_each, :before_var => before_var, :inside_var => inside_var
        var = DS::DSVariable.new :name => var_name, :type => before_var.type
        assignment = DS::DSAssignment.new :var => var, :objset => lambda_objset
        block.replace before_var, var
        block.statements.unshift assignment
      end
      
      iterator_objset = DS::DSForEachIteratorObjset.new :for_each => for_each
      block.replace temp_iterator_objset, iterator_objset
      return for_each
    end

    def list_creations
      @block.list_creations
    end
  end

  class ADSLEither < ADSLNode
    node_type :blocks

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

      either = DS::DSEither.new :blocks => blocks

      lambdas = []

      ADSLTypecheckResolveContext::context_vars_that_differ(*contexts).each do |var_name, vars|
        var = DS::DSVariable.new :name => var_name, :type => vars.first.type
        objset = DS::DSEitherLambdaObjset.new :either => either, :vars => vars
        assignment = DS::DSAssignment.new :var => var, :objset => objset
        context.redefine_var var, nil
        lambdas << assignment
      end

      return [ either, lambdas ]
    end

    def list_entity_classes_written_to
      @blocks.map{ block.list_entity_classes_written_to }.flatten
    end
  end

  class ADSLDeleteObj < ADSLNode
    node_type :objset

    def typecheck_and_resolve(context)
      objset = @objset.typecheck_and_resolve context
      return DS::DSDeleteObj.new :objset => objset
    end
  end

  def self.find_relation(context, from_type, rel_name, lineno, to_type=nil)
    iter = from_type
    relation_node, relation = context.relations[iter.name][rel_name]
    while relation.nil?
      iter = iter.parent
      raise ADSLError, "Unknown relation #{from_type.name}.#{rel_name} on line #{lineno}" if iter.nil?
      relation_node, relation = context.relations[iter.name][rel_name]
    end
    
    unless to_type.nil?
      raise ADSLError, "Mismatched right-hand-side type for relation #{from_type.name}.#{rel_name} on line #{lineno}. Expected #{relation.to_class.name} but was #{to_type.name}" unless relation.to_class.superclass_of? to_type
    end

    relation
  end

  class ADSLCreateTup < ADSLNode
    node_type :objset1, :rel_name, :objset2

    def typecheck_and_resolve(context)
      objset1 = @objset1.typecheck_and_resolve context
      objset2 = @objset2.typecheck_and_resolve context
      relation = ADSL::find_relation context, objset1.type, @rel_name.text, @rel_name.lineno, objset2.type
      return DS::DSCreateTup.new :objset1 => objset1, :relation => relation, :objset2 => objset2
    end
  end

  class ADSLDeleteTup < ADSLNode
    node_type :objset1, :rel_name, :objset2
    
    def typecheck_and_resolve(context)
      objset1 = @objset1.typecheck_and_resolve context
      objset2 = @objset2.typecheck_and_resolve context
      relation = ADSL::find_relation context, objset1.type, @rel_name.text, @rel_name.lineno, objset2.type 
      return DS::DSDeleteTup.new :objset1 => objset1, :relation => relation, :objset2 => objset2
    end
  end

  class ADSLAllOf < ADSLNode
    node_type :class_name

    def typecheck_and_resolve(context)
      klass_node, klass = context.classes[@class_name.text]
      raise ADSLError, "Unknown class name #{@class_name.text} on line #{@class_name.lineno}" if klass.nil?
      return DS::DSAllOf.new :klass => klass
    end

    def list_entity_classes_read
      Set[context.classes[@class_name.text]]
    end
  end

  class ADSLSubset < ADSLNode
    node_type :objset

    def typecheck_and_resolve(context)
      objset = @objset.typecheck_and_resolve context
      return DS::DSSubset.new :objset => objset
    end
  end
  
  class ADSLOneOf < ADSLNode
    node_type :objset

    def typecheck_and_resolve(context)
      objset = @objset.typecheck_and_resolve context
      return DS::DSOneOf.new :objset => objset
    end
  end
  
  class ADSLVariable < ADSLNode
    node_type :var_name

    def typecheck_and_resolve(context)
      var_node, var = context.lookup_var @var_name.text
      raise ADSLError, "Undefined variable #{@var_name.text} on line #{@var_name.lineno}" if var.nil?
      return var
    end
  end

  class ADSLDereference < ADSLNode
    node_type :objset, :rel_name

    def typecheck_and_resolve(context)
      objset = @objset.typecheck_and_resolve context
      klass = objset.type
      relation = ADSL::find_relation context, objset.type, @rel_name.text, @rel_name.lineno
      return DS::DSDereference.new :objset => objset, :relation => relation
    end
  end

  class ADSLInvariant < ADSLNode
    node_type :name, :formula

    def typecheck_and_resolve(context)
      formula = @formula.typecheck_and_resolve context
      name = @name.nil? ? nil : @name.text
      return DS::DSInvariant.new :name => name, :formula => formula
    end
  end

  class ADSLBoolean < ADSLNode
    node_type :bool_value

    def typecheck_and_resolve(context)
      return DS::DSBoolean::TRUE if @bool_value
      return DS::DSBoolean::FALSE
    end
  end

  class ADSLForAll < ADSLNode
    node_type :vars, :subformula

    def typecheck_and_resolve(context)
      context.in_stack_frame do
        vars = []
        objsets = []
        @vars.each do |var_node, objset_node|
          objset = objset_node.typecheck_and_resolve context
          
          var = DS::DSVariable.new :name => var_node.text, :type => objset.type
          context.define_var var, var_node

          vars << var
          objsets << objset
        end
        subformula = @subformula.typecheck_and_resolve context
        return DS::DSForAll.new :vars => vars, :objsets => objsets, :subformula => subformula
      end
    end
  end

  class ADSLExists < ADSLNode
    node_type :vars, :subformula

    def typecheck_and_resolve(context)
      context.in_stack_frame do
        vars = []
        objsets = []
        @vars.each do |var_node, objset_node|
          objset = objset_node.typecheck_and_resolve context
          
          var = DS::DSVariable.new :name => var_node.text, :type => objset.type
          context.define_var var, var_node

          vars << var
          objsets << objset
        end
        subformula = @subformula.nil? ? nil : @subformula.typecheck_and_resolve(context)
        return DS::DSExists.new :vars => vars, :objsets => objsets, :subformula => subformula
      end
    end
  end

  class ADSLNot < ADSLNode
    node_type :subformula

    def typecheck_and_resolve(context)
      subformula = @subformula.typecheck_and_resolve context
      raise "Substatement not a formula on line #{@subformula.lineno}" unless subformula.type == :formula
      return subformula.subformula if subformula.is_a? DS::DSNot
      return DS::DSNot.new :subformula => subformula
    end
  end

  class ADSLAnd < ADSLNode
    node_type :subformulae

    def typecheck_and_resolve(context)
      subformulae = @subformulae.map{ |o| o.typecheck_and_resolve context }
      subformulae.each do |subformula|
        raise "Substatement not a formula on line #{subformula.lineno}" unless subformula.type == :formula  
      end
      flattened_subformulae = []
      subformulae.each do |subformula|
        if subformula.is_a? DS::DSAnd
          flattened_subformulae += subformula.subformulae
        else
          flattened_subformulae << subformula
        end
      end
      return DS::DSAnd.new :subformulae => flattened_subformulae
    end
  end
  
  class ADSLOr < ADSLNode
    node_type :subformulae

    def typecheck_and_resolve(context)
      subformulae = @subformulae.map{ |o| o.typecheck_and_resolve context }
      subformulae.each do |subformula|
        raise "Substatement not a formula on line #{subformula.lineno}" unless subformula.type == :formula  
      end
      flattened_subformulae = []
      subformulae.each do |subformula|
        if subformula.is_a? DS::DSOr
          flattened_subformulae += subformula.subformulae
        else
          flattened_subformulae << subformula
        end
      end
      return DS::DSOr.new :subformulae => flattened_subformulae
    end
  end

  class ADSLEquiv < ADSLNode
    node_type :subformulae

    def typecheck_and_resolve(context)
      subformulae = @subformulae.map{ |o| o.typecheck_and_resolve context }
      subformulae.each do |subformula|
        raise "Substatement not a formula on line #{subformula.lineno}" unless subformula.type == :formula  
      end
      return DS::DSEquiv.new :subformulae => subformulae
    end
  end

  class ADSLImplies < ADSLNode
    node_type :subformula1, :subformula2

    def typecheck_and_resolve(context)
      subformula1 = @subformula1.typecheck_and_resolve context
      subformula2 = @subformula2.typecheck_and_resolve context
      
      [subformula1, subformula2].each do |subformula|
        raise "Substatement not a formula on line #{subformula.lineno}" unless subformula.type == :formula  
      end
      return DS::DSImplies.new :subformula1 => subformula1, :subformula2 => subformula2
    end
  end

  class ADSLEqual < ADSLNode
    node_type :objsets
    
    def typecheck_and_resolve(context)
      objsets = @objsets.map{ |o| o.typecheck_and_resolve context }

      types = objsets.map{ |o| o.type }.uniq
      while types.length > 1
        type1 = types.pop
        type2 = types.pop
        if type1.superclass_of? type2
          types << type2
        elsif type2.superclass_of? type1
          types << type1
        else
          raise ADSLError, "Object sets are not of compatible types: #{objsets.map { |o| o.type.name }.join(", ")}"
        end
      end

      return DS::DSEqual.new :objsets => objsets
    end
  end

  class ADSLIn < ADSLNode
    node_type :objset1, :objset2

    def typecheck_and_resolve(context)
      objset1 = @objset1.typecheck_and_resolve context
      objset2 = @objset2.typecheck_and_resolve context
      raise ADSLError, "Object sets are not of compatible types: #{objset1.type.name}, #{objset2.type.name}" unless objset2.type.superclass_of? objset1.type
      return DS::DSIn.new :objset1 => objset1, :objset2 => objset2
    end
  end
  
  class ADSLEmpty < ADSLNode
    node_type :objset

    def typecheck_and_resolve(context)
      objset = @objset.typecheck_and_resolve context
      return DS::DSEmpty.new :objset => objset
    end
  end
end
