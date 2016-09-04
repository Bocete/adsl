require 'adsl/lang/ast_node'
require 'adsl/lang/ds_translation/util'
require 'adsl/lang/ds_translation/ds_translation_context'
require 'adsl/lang/ds_translation/ds_translation_result'

module ADSL
  module Lang

    class ASTNode
      def gen_translation_result(args = {})
        args[:expr] ||= ADSL::DS::DSEmptyObjset::INSTANCE
        args[:state_transitions] ||= []
        ADSL::Lang::DSTranslation::DSTranslationResult.new args
      end
    end
    
    class ASTDummyObjset < ASTNode
      def typecheck_and_resolve(context)
        gen_translation_result
      end
    end
    
    class ASTFlag < ASTNode
      def typecheck_and_resolve(context)
        gen_translation_result
      end
    end
    
    class ASTSpec < ASTNode

      def typecheck_and_resolve
        context = ADSL::Lang::DSTranslation::DSTranslationContext.new

        # make sure class names are unique
        @classes.each do |class_node|
          if context.classes.include? class_node.name.text
            raise ADSLError, "Duplicate class name '#{class_node.name.text}' on line #{class_node.name.lineno} (first definition on line #{context.classes[class_node.name.text][0].name.lineno}"
          end
          klass = ADSL::DS::DSClass.new :name => class_node.name.text, :authenticable => class_node.authenticable
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

        # auth stuff
        # this call might raise exceptions
        authclass = context.auth_class
        if authclass
          @usergroups.each do |ug_node|
            ug_node.typecheck_and_resolve context
          end
        elsif @usergroups.length > 0
          raise ADSLError, "UserGroups can only be declared if there exists an authenticable class"
        end

        # setup children of said classes
        context.classes.values.each do |class_node, klass|
          klass.parents.each do |parent|
            parent.children << klass
          end
        end

        # make sure relations are valid and refer to existing classes
        context.classes.values.each do |class_node, klass|
          class_node.members.each do |rel_node|
            klass.all_parents(true).each do |superclass|
              if context.members[superclass.name].include? rel_node.name.text
                raise ADSLError, "Duplicate member name '#{class_node.name.text}' under class '#{klass.name}' on line #{rel_node.lineno} (first definition on line #{context.members[superclass.name][rel_node.name.text][0].lineno}"
              end
            end
            
            rel_node.class_name = klass.name
            if rel_node.is_a? ASTRelation
              ds_obj = ADSL::DS::DSRelation.new :name => rel_node.name.text, :from_class => klass
            else
              ds_obj = ADSL::DS::DSField.new :name => rel_node.name.text, :from_class => klass
            end
            context.members[klass.name][ds_obj.name] = [rel_node, ds_obj]
            klass.members << ds_obj
          end
        end

        # now that classes and rels are initialized, check them
        @classes.each do |class_node|
          class_node.typecheck_and_resolve context
        end

        @actions.each do |action_node|
          action_node.typecheck_and_resolve context
        end

        @rules.each do |rule_node|
          context.rules << (rule_node.typecheck_and_resolve context)
        end

        # make sure invariants have unique names; create names for unnamed invariants
        names = Set.new
        @invariants.each do |invariant_node|
          invariant = invariant_node.typecheck_and_resolve context
          invariant_name = invariant.name.blank? ? nil : invariant.name
          if invariant_name && names.include?(invariant_name)
            raise ADSLError, "Duplicate invariant name #{invariant.name} on line #{invariant_node.lineno}"
          end
          invariant_name ||= "unnamed_line_#{invariant_node.lineno}"
          while names.include? invariant_name
            invariant_name = invariant_name.increment_suffix
          end
          invariant.name = invariant_name
          context.invariants << invariant
          names << invariant_name
        end

        @invariants.each do |invariant_node|
          invariant = invariant_node.typecheck_and_resolve context
        end

        @ac_rules.each do |ac_rule|
          context.ac_rules << ac_rule.typecheck_and_resolve(context)
        end

        ADSL::DS::DSSpec.new(
          :classes => context.classes.map{ |a, b| b[1] }, 
          :usergroups => context.usergroups.map{ |a, b| b[1] },
          :actions => context.actions.map{ |a, b| b[1] },
          :invariants => context.invariants.dup,
          :ac_rules => context.ac_rules.dup,
          :rules => context.rules.dup
        )
      end
    end
    
    class ASTUserGroup < ASTNode
      def typecheck_and_resolve(context)
        name = @name.text
        if context.usergroups.include? name
          raise ADSLError, "Duplicate usergroup name #{name} at line #{@lineno}"
        end
        ug = ADSL::DS::DSUserGroup.new :name => name
        context.usergroups[name] = [self, ug]
      end
    end
    
    class ASTClass < ASTNode
      def typecheck_and_resolve(context)
        klass = context.classes[@name.text][1]
        @members.each do |member_node|
          member_node.typecheck_and_resolve context
        end
      end
    end
    
    class ASTRelation < ASTNode
      def typecheck_and_resolve(context)
        rel = context.members[@class_name][@name.text][1]
          
        if @cardinality[0] > @cardinality[1]
          raise ADSLError, "Invalid cardinality of relation #{@class_name}.#{@name.text} on line #{@cardinality[2]}: minimum cardinality #{@cardinality[0]} must not be greater than the maximum cardinality #{@cardinality[1]}"
        end
        if @cardinality[1] == 0
          raise ADSLError, "Invalid cardinality of relation #{@class_name}.#{@name.text} on line #{@cardinality[2]}: maximum cardinality #{@cardinality[1]} must be positive"
        end
        unless context.classes.include? @to_class_name.text
          raise ADSLError, "Unknown class name #{@to_class_name.text} in relation #{@class_name}.#{@name.text} on line #{@to_class_name.lineno}"
        end

        rel.to_class = context.classes[@to_class_name.text][1]
        rel.cardinality = ADSL::DS::TypeSig::ObjsetCardinality.new *@cardinality

        if @inverse_of_name
          target_class = rel.to_class
          target_rel = (target_class.all_parents(true)).map{ |klass| klass.members }.flatten.select{ |rel| rel.name == @inverse_of_name.text}.first
           
          if target_rel.nil?
            raise ADSLError, "Unknown relation to which #{@class_name}.#{rel.name} relation is inverse to: #{rel.to_class.name}.#{@inverse_of_name.text} on line #{@inverse_of_name.lineno}"
          end
          unless target_rel.is_a? ADSL::DS::DSRelation
            raise ADSLError, "Inverse relation of #{@class_name}.#{rel.name} is not a relation (#{rel.to.class.name}.#{@inverse_of_name.text}) on line #{@inverse_of_name.lineno}"
          end

          rel.inverse_of = target_rel

          if target_rel.inverse_of
            raise ADSLError, "Relation #{@class_name}.#{rel.name} cannot be inverse to an inverse relation #{rel.to_class.name}.#{@inverse_of_name.text} on line #{@inverse_of_name.lineno}"
          end
        end
      end
    end

    class ASTField < ASTNode
      def typecheck_and_resolve(context)
        type = ADSL::DS::TypeSig::BasicType.for_sym type_name.to_sym

        if type.nil?
          raise ADSLError, "Unknown basic type `#{@type_name}` on line #{@lineno}"
        end

        field = context.members[@class_name][@name.text][1]
        field.type = type
      end
    end

    class ASTAction < ASTNode
      def typecheck_and_resolve(context)
        old_action_node, old_action = context.actions[@name.text]
        raise ADSLError, "Duplicate action name #{@name.text} on line #{@name.lineno}; first definition on line #{old_action_node.name.lineno}" unless old_action.nil?

        flatten_returns!

        expr_result = nil
        context.in_stack_frame do
          expr_result = @expr.typecheck_and_resolve context
        end
        block = ADSL::DS::DSBlock.new :statements => expr_result.state_transitions
        action = ADSL::DS::DSAction.new(
          :name => @name.text,
          :block => block
        )
        context.actions[action.name] = [self, action]
        action
      end
    end

    class ASTBlock < ASTNode
      def typecheck_and_resolve(context, open_subcontext=true)
        return gen_translation_result if @exprs.empty?

        if open_subcontext
          context.push_frame
          pushed = true
        end
        
        results = @exprs.map{ |e| e.typecheck_and_resolve context }

        return gen_translation_result(
          :state_transitions => results.map(&:state_transitions).flatten,
          :expr => results.last.expr
        )
      ensure
        context.pop_frame if pushed
      end
    end

    class ASTAssignment < ASTNode
      def typecheck_and_resolve(context)
        expr_result = @expr.typecheck_and_resolve context
        assignment_result = ASTAssignment.typecheck_and_resolve_assignment context, @var_name, expr_result.expr
        gen_translation_result(
          :state_transitions => expr_result.state_transitions + assignment_result.state_transitions,
          :expr => assignment_result.expr
        )
      end

      def self.typecheck_and_resolve_assignment(context, var_name, ds_expr)
        # assignments to booleans are not supported yet
        unless ds_expr.type_sig.is_objset_type?
          raise ADSLError, "Assignments to booleans are not supported (var name #{ var_name.text })"
        end

        var = ADSL::DS::DSVariable.new :name => var_name.text, :type_sig => ds_expr.type_sig

        context.redefine_var var, var_name
        assignment = ADSL::DS::DSAssignment.new :var => var, :expr => ds_expr

        # even though we want to join types for the variable, we don't want to join the cardinality
        var.type_sig = var.type_sig.with_cardinality ds_expr.type_sig.cardinality.dup if var.type_sig.is_a? ADSL::DS::TypeSig::ObjsetType
        
        var_read = ADSL::DS::DSVariableRead.new :variable => var
        ADSL::Lang::DSTranslation::DSTranslationResult.new(
          :state_transitions => [assignment],
          :expr => var_read
        )
      end
    end

    class ASTAssertFormula < ASTNode
      def typecheck_and_resolve(context)
        formula_result = @formula.typecheck_and_resolve context
        unless formula_result.type_sig.is_bool_type?
          raise ADSLError, "Asserted formula is not of boolean type (type provided `#{formula_result.type_sig}` on line #{ @lineno })"
        end
        gen_translation_result(
          :state_transitions => formula_result.state_transitions + [ADSL::DS::DSAssertFormula.new(:formula => formula_result.expr)]
        )
      end
    end

    class ASTCreateObjset < ASTNode
      def typecheck_and_resolve(context)
        klass_node, klass = context.classes[@class_name.text]
        raise ADSLError, "Undefined class #{@class_name.text} referred to at line #{@class_name.lineno}" if klass.nil?
          
        create_obj =    ADSL::DS::DSCreateObj.new :klass => klass
        create_objset = ADSL::DS::DSCreateObjset.new :createobj => create_obj
        
        gen_translation_result :state_transitions => [create_obj], :expr => create_objset
      end
    end

    class ASTForEach < ASTNode
      def typecheck_and_resolve(context)
        before_context = context.dup
        objset_result = @objset.typecheck_and_resolve context

        return objset_result if objset_result.type_sig.cardinality.empty?

        unless objset_result.type_sig.is_objset_type?
          raise ADSLError, "ForEach can iterate over object sets only (type provided `#{objset_result.type_sig}` on line #{ @lineno })"
        end
        
        for_each = ADSL::DS::DSForEach.new :objset => objset_result.expr
        iterator_objset = ADSL::DS::DSForEachIteratorObjset.new :for_each => for_each
        
        vars_written_to = Set[]
        vars_read = Set[]
        vars_read_before_being_written_to = Set[]
        
        context.push_frame

        assignment_result = ASTAssignment.typecheck_and_resolve_assignment context, @var_name, iterator_objset
        
        context.on_var_write do |name|
          vars_written_to << name
        end
        context.on_var_read do |name|
          var_node, var = context.lookup_var name, false
          vars_read_before_being_written_to << name unless
              vars_written_to.include?(name) or vars_read_before_being_written_to.include? name
          vars_read << name unless vars_read.include? name
        end
        
        block_result = @expr.typecheck_and_resolve context

        for_each.block = ADSL::DS::DSBlock.new(
          :statements => assignment_result.state_transitions + block_result.state_transitions
        )

        vars_read_before_being_written_to.each do |var_name|
          vars_read_before_being_written_to.delete var_name unless vars_written_to.include? var_name
        end

        vars_needing_post_lambdas = vars_written_to & Set[*before_context.stack_frame_stack.map(&:keys).flatten]
        
        flat = if @force_flat.nil?
          if vars_needing_post_lambdas.empty?
            info = ADSL::DS::NodeEffectDomainInfo.new
            for_each.block.effect_domain_analysis context, info
            !info.conflicting?
          else
            false
          end
        else
          @force_flat
        end

        for_each.force_flat flat

        vars_read_before_being_written_to.each do |var_name|
          before_var_node, before_var = before_context.lookup_var var_name, false
          inside_var_node, inside_var = context.lookup_var var_name, false
          lambda_expr = ADSL::DS::DSForEachPreLambdaExpr.new(
            :for_each => for_each, :before_var => before_var, :inside_var => inside_var
          )
          var = ADSL::DS::DSVariable.new :name => var_name, :type_sig => before_var.type_sig
          assignment = ADSL::DS::DSAssignment.new :var => var, :expr => lambda_expr
          for_each.block.replace before_var, var
          for_each.block.statements.unshift assignment
        end

        post_lambda_assignments = vars_needing_post_lambdas.map do |var_name|
          before_var_node, before_var = before_context.lookup_var var_name, false
          inside_var_node, inside_var = context.lookup_var var_name, false

          lambda_expr = ADSL::DS::DSForEachPostLambdaExpr.new(
            :for_each => for_each, :before_var => before_var, :inside_var => inside_var
          )
          var = ADSL::DS::DSVariable.new :name => var_name, :type_sig => ADSL::DS::TypeSig.join(before_var.type_sig, inside_var.type_sig)
          ADSL::DS::DSAssignment.new :var => var, :expr => lambda_expr
        end

        context.pop_frame

        gen_translation_result(
          :state_transitions => [for_each] + post_lambda_assignments
        )
      end
    end

    class ASTReturnGuard < ASTNode
      def typecheck_and_resolve(context)
        raise 'This is not translated to DS. The action is supposed to get rid of these'
      end
    end

    class ASTReturn < ASTNode
      def typecheck_and_resolve(context)
        raise 'This is not translated to DS. The action is supposed to get rid of these'
      end
    end

    class ASTRaise < ASTNode
      def typecheck_and_resolve(context)
        gen_translation_result :state_transitions => [ADSL::DS::DSRaise.new]
      end
    end

    class ASTIf < ASTNode
      def typecheck_and_resolve(context)
        context.push_frame
        
        condition_result = @condition.typecheck_and_resolve(context)
        if condition_result.type_sig.is_objset_type?
          condition_result.expr = ADSL::DS::DSNot.new(:subformula => ADSL::DS::DSIsEmpty.new(:objset => condition_result.expr))
        end

        unless condition_result.type_sig.is_bool_type?
          raise ADSLError, "If condition is not of boolean type (type provided `#{condition_result.type_sig}` on line #{ @lineno })"
        end
        
        contexts = [context, context.dup]
        then_result = @then_expr.typecheck_and_resolve(contexts[0])
        else_result = @else_expr.typecheck_and_resolve(contexts[1])
        contexts.each{ |c| c.pop_frame }

        @ds_if = ADSL::DS::DSIf.new(
          :condition => condition_result.expr,
          :then_block => ADSL::DS::DSBlock.new(:statements => then_result.state_transitions),
          :else_block => ADSL::DS::DSBlock.new(:statements => else_result.state_transitions)
        )

        lambdas = []
        ADSL::Lang::DSTranslation::DSTranslationContext.context_vars_that_differ(*contexts).each do |var_name, variables|
          variables = variables.map{ |v| ADSL::DS::DSVariableRead.new :variable => v }
          type_sig = ADSL::DS::TypeSig.join variables.map(&:type_sig)
          var = ADSL::DS::DSVariable.new :name => var_name, :type_sig => type_sig
          expr = ADSL::DS::DSIfLambdaExpr.new :if => @ds_if, :then_expr => variables[0], :else_expr => variables[1]
          assignment = ADSL::DS::DSAssignment.new :var => var, :expr => expr
          context.redefine_var var, nil
          lambdas << assignment
        end

        return_expr = ADSL::DS::DSIfLambdaExpr.new(:if => @ds_if,
                                                   :then_expr => then_result.expr,
                                                   :else_expr => else_result.expr)

        gen_translation_result(
          :state_transitions => condition_result.state_transitions + [@ds_if] + lambdas,
          :expr => return_expr
        )
      end
    end

    class ASTDeleteObj < ASTNode
      def typecheck_and_resolve(context)
        objset_result = @objset.typecheck_and_resolve context
        unless objset_result.type_sig.is_objset_type?
          raise ADSLError, "DeleteObj can delete object sets only (type provided `#{objset_result.type_sig}` on line #{ @lineno })"
        end
        return gen_translation_result if objset_result.type_sig.cardinality.empty?
        gen_translation_result(
          :state_transitions => objset_result.state_transitions + [ADSL::DS::DSDeleteObj.new(:objset => objset_result.expr)]
        )
      end
    end

    class ASTCreateTup < ASTNode
      def typecheck_and_resolve(context)
        objset1_result = @objset1.typecheck_and_resolve context
        objset2_result = @objset2.typecheck_and_resolve context
        
        unless objset1_result.type_sig.is_objset_type?
          raise ADSLError, "Tuples can be created between object sets only (type provided `#{objset1_result.type_sig}` on line #{ @lineno })"
        end
        unless objset2_result.type_sig.is_objset_type?
          raise ADSLError, "Tuples can be created between objset sets only (type provided `#{objset2_result.type_sig}` on line #{ @lineno })"
        end
        if objset1_result.type_sig.is_ambiguous_objset_type?
          raise ADSLError, "Ambiguous type on the left hand side on line #{@objset1.lineno}"
        end
        if objset1_result.type_sig.cardinality.empty? || objset2_result.type_sig.cardinality.empty?
          return gen_translation_result :expr => objset2_result.expr
        end

        relation = context.find_member objset1_result.type_sig, @rel_name.text, @rel_name.lineno, objset2_result.type_sig
        raise ADSLError, "#{objset1_result.type_sig}.#{@rel_name.text} is not a relation" unless relation.is_a? ADSL::DS::DSRelation

        tuple_create = ADSL::DS::DSCreateTup.new :objset1 => objset1_result.expr, :relation => relation, :objset2 => objset2_result.expr
        gen_translation_result(
          :state_transitions => objset1_result.state_transitions + objset2_result.state_transitions + [tuple_create],
          :expr => objset2_result.expr
        )
      end
    end

    class ASTDeleteTup < ASTNode
      def typecheck_and_resolve(context)
        objset1_result = @objset1.typecheck_and_resolve context
        objset2_result = @objset2.typecheck_and_resolve context
        
        unless objset1_result.type_sig.is_objset_type?
          raise ADSLError, "Tuples can be deleted between object sets only (type provided `#{objset1_result.type_sig}` on line #{ @lineno })"
        end
        unless objset2_result.type_sig.is_objset_type?
          raise ADSLError, "Tuples can be deleted between objset sets only (type provided `#{objset2_result.type_sig}` on line #{ @lineno })"
        end
        if objset1_result.type_sig.is_ambiguous_objset_type?
          raise ADSLError, "Ambiguous type on the left hand side on line #{@objset1.lineno}"
        end
        if objset1_result.type_sig.cardinality.empty? || objset2_result.type_sig.cardinality.empty?
          return gen_translation_result
        end

        relation = context.find_member objset1_result.type_sig, @rel_name.text, @rel_name.lineno, objset2_result.type_sig
        raise ADSLError, "#{objset1_result.type_sig}.#{@rel_name.text} is not a relation" unless relation.is_a? ADSL::DS::DSRelation

        tuple_delete = ADSL::DS::DSDeleteTup.new :objset1 => objset1_result.expr, :relation => relation, :objset2 => objset2_result.expr
        gen_translation_result(
          :state_transitions => objset1_result.state_transitions + objset2_result.state_transitions + [tuple_delete],
          :expr => objset2_result.expr
        )
      end
    end

    class ASTMemberSet < ASTNode
      def typecheck_and_resolve(context)
        objset_result = @objset.typecheck_and_resolve context
        expr_result   = @expr.typecheck_and_resolve context
        
        unless objset_result.type_sig.is_objset_type?
          raise ADSLError, "Member set possible only on objset sets (type provided `#{objset.type_sig}` on line #{ @lineno })"
        end
        if objset_result.type_sig.is_ambiguous_objset_type?
          raise ADSLError, "Ambiguous type on the left hand side on line #{@objset.lineno}"
        end

        member = context.find_member objset_result.type_sig, @member_name.text, @member_name.lineno, expr_result.type_sig

        if member.is_a?(ADSL::DS::DSRelation)
          stmts = objset_result.state_transitions + expr_result.state_transitions
          stmts += member.type_sig.classes.map do |c|
            ADSL::DS::DSDeleteTup.new(
              :objset1 => objset_result.expr,
              :relation => member,
              :objset2 => ADSL::DS::DSAllOf.new(:klass => c)
            )
          end
          stmts << ADSL::DS::DSCreateTup.new(:objset1 => objset_result.expr, :relation => member, :objset2 => expr_result.expr)

          gen_translation_result(
            :state_transitions => stmts,
            :expr => expr_result.expr
          )
        else
          field_set = ADSL::DS::DSFieldSet.new(:objset => objset_result.expr, :field => member, :expr => expr_result.expr)
          stmts = objset_result.state_transitions + expr_result.state_transitions + [field_set] 
          gen_translation_result(
            :state_transitions => stmts,
            :expr => expr_result.expr
          )
        end
      end
    end

    class ASTAllOf < ASTNode
      def typecheck_and_resolve(context)
        klass_node, klass = context.classes[@class_name.text]
        raise ADSLError, "Unknown class name #{@class_name.text} on line #{@class_name.lineno}" if klass.nil?
        gen_translation_result(
          :expr => ADSL::DS::DSAllOf.new(:klass => klass)
        )
      end
    end

    class ASTSubset < ASTNode
      def typecheck_and_resolve(context)
        objset_result = @objset.typecheck_and_resolve context
       
        unless objset_result.type_sig.is_objset_type?
          raise ADSLError, "Subset possible only on objset sets (type provided `#{objset_result.type_sig}` on line #{ @lineno })"
        end

        return objset_result if objset_result.type_sig.cardinality.to_one?
        
        objset_result.with_expr ADSL::DS::DSSubset.new(:objset => objset_result.expr)
      end
    end
    
    class ASTTryOneOf < ASTNode
      def typecheck_and_resolve(context)
        objset_result = @objset.typecheck_and_resolve context
       
        unless objset_result.type_sig.is_objset_type?
          raise ADSLError, "TryOneOf possible only on objset sets (type provided `#{objset_result.type_sig}` on line #{ @lineno })"
        end
        if objset_result.type_sig.cardinality.empty?
          return objset_result.with_expr ADSL::DS::DSEmptyObjset.new
        end

        objset_result.with_expr ADSL::DS::DSTryOneOf.new(:objset => objset_result.expr)
      end
    end

    class ASTOneOf < ASTNode
      def typecheck_and_resolve(context)
        objset_result = @objset.typecheck_and_resolve context
       
        unless objset_result.type_sig.is_objset_type?
          raise ADSLError, "TryOneOf possible only on objset sets (type provided `#{objset_result.type_sig}` on line #{ @lineno })"
        end

        objset_result.with_expr ADSL::DS::DSOneOf.new(:objset => objset_result.expr)
      end
    end
    
    class ASTUnion < ASTNode
      def typecheck_and_resolve(context)
        objset_results = @objsets.map{ |o| o.typecheck_and_resolve context }
        
        objset_results.each do |objset_result|
          unless objset_result.type_sig.is_objset_type?
            raise ADSLError, "TryOneOf possible only on objset sets (type provided `#{objset_result.type_sig}` on line #{ @lineno })"
          end
        end

        state_transitions = objset_results.map(&:state_transitions).flatten
        objsets = objset_results.map(&:expr)
        objsets.reject!{ |o| o.type_sig.cardinality.empty? }

        if objsets.empty?
          expr = ADSL::DS::DSEmptyObjset.new
        elsif objsets.length == 1
          expr = objsets.first
        else
          # will raise an error if no single common supertype exists
          ADSL::DS::TypeSig.join objsets.map(&:type_sig)
          expr = ADSL::DS::DSUnion.new :objsets => objsets
        end

        gen_translation_result(
          :state_transitions => state_transitions,
          :expr => expr
        )
      end
    end
    
    class ASTVariableRead < ASTNode
      def typecheck_and_resolve(context)
        var_node, var = context.lookup_var @var_name.text
        raise ADSLError, "Undefined variable #{@var_name.text} on line #{@var_name.lineno}" if var.nil?
        gen_translation_result :expr => ADSL::DS::DSVariableRead.new(:variable => var)
      end
    end

    class ASTMemberAccess < ASTNode
      def typecheck_and_resolve(context)
        objset_result = @objset.typecheck_and_resolve context
        unless objset_result.type_sig.is_objset_type?
          raise ADSLError, "Member access possible only on objset sets (type provided `#{objset_result.type_sig}` on line #{ @lineno })"
        end

        if objset_result.type_sig.is_ambiguous_objset_type?
          raise ADSLError, "Origin type of member access unknown on line #{lineno}"
        end

        member = context.find_member objset_result.type_sig, @member_name.text, @member_name.lineno
        if member.is_a?(ADSL::DS::DSRelation)
          expr = ADSL::DS::DSDereference.new :objset => objset_result.expr, :relation => member
        else
          unless objset_result.type_sig.cardinality.max == 1
            raise ADSLError, "Field values can only be read on singleton object sets (line #{ @lineno })"
          end
          expr = ADSL::DS::DSFieldRead.new :objset => objset_result.expr, :field => member
        end
        gen_translation_result :state_transitions => objset_result.state_transitions, :expr => expr
      end
    end

    class ASTDereferenceCreate < ASTNode
      def typecheck_and_resolve(context)
        objset_result = @objset.typecheck_and_resolve context

        relations = objset_result.expr.type_sig.classes.map{ |c| c.relations.select{ |rel| rel.name == @rel_name.text.to_s } }.flatten
        raise "Relation by name #{ @rel_name.text } not found in class #{ objset_result.expr.type_sig } in line #{ @lineno }" if relations.empty?
        raise "Multiple relations by name#{ @rel_name.text } not found in class #{ objset_result.expr.type_sig } in line #{ @lineno }" if relations.length > 1

        relation = relations.first

        create  = ADSL::DS::DSCreateObj.new(:klass => relation.to_class)
        created = ADSL::DS::DSCreateObjset.new(:createobj => create)
        delete  = ADSL::DS::DSDeleteTup.new(:objset1 => objset_result.expr, :relation => relation, :objset2 => ADSL::DS::DSAllOf.new(:klass => relation.to_class)) if @empty_first
        assign  = ADSL::DS::DSCreateTup.new(:objset1 => objset_result.expr, :relation => relation, :objset2 => created)

        gen_translation_result(
          :state_transitions => objset_result.state_transitions + [create, delete, assign].compact,
          :expr => created
        )
      end
    end

    class ASTEmptyObjset < ASTNode
      def typecheck_and_resolve(context)
        gen_translation_result
      end
    end

    class ASTCurrentUser < ASTNode
      def typecheck_and_resolve(context)
        auth_class_node, auth_class = context.auth_class
        raise ADSLError, "currentuser (line #{@lineno}) cannot be used in lack of an authclass" if auth_class_node.nil?
        gen_translation_result :expr => ADSL::DS::DSCurrentUser.new(:type_sig => auth_class.to_sig.with_cardinality(1))
      end
    end

    class ASTInUserGroup < ASTNode
      def typecheck_and_resolve(context)
        auth_class_node, auth_class = context.auth_class
        if auth_class.nil?
          raise ADSLError, "Inusergroup cannot be used without having defined an authenticable class (line #{@lineno})"
        end
        if @objset
          objset_result = @objset.typecheck_and_resolve context
          unless objset_result.type_sig <= auth_class.to_sig
            raise ADSLError, "Only instances of the authenticable class may belong to usergroups (line #{@lineno})"
          end
        else
          objset_result = gen_translation_result :expr => ADSL::DS::DSCurrentUser.new
        end
        group = context.usergroups[@groupname.text]
        if group.nil?
          raise ADSLError, "No groupname found by name #{@groupname.text} on line #{@lineno}"
        end
        gen_translation_result(
          :state_transitions => objset_result.state_transitions,
          :expr => ADSL::DS::DSInUserGroup.new(:objset => objset_result.expr, :usergroup => group[1])
        )
      end
    end

    class ASTAllOfUserGroup < ASTNode
      def typecheck_and_resolve(context)
        auth_class_node, auth_class = context.auth_class
        if auth_class.nil?
          raise ADSLError, "Inusergroup cannot be used without having defined an authenticable class (line #{@lineno})"
        end
        group = context.usergroups[@groupname.text]
        if group.nil?
          raise ADSLError, "No groupname found by name #{@groupname.text} on line #{@lineno}"
        end
        type_sig = auth_class.to_sig.with_cardinality(1)
        gen_translation_result :expr => ADSL::DS::DSAllOfUserGroup.new(:usergroup => group[1], :type_sig => type_sig)
      end
    end

    class ASTPermitted < ASTNode
      def typecheck_and_resolve(context)
        auth_class_node, auth_class = context.auth_class
        if auth_class.nil?
          raise ADSLError, "Permissions cannot be checked in a permissionless system (line #{@lineno})"
        end

        ops, expr_result = ADSL::Lang::DSTranslation::Util.ops_and_expr_from_nodes context, @ops, @expr
        
        gen_translation_result :state_transitions => expr_result.state_transitions, :expr => ADSL::DS::DSPermitted.new(:ops => ops, :expr => expr_result.expr)
      end
    end

    class ASTPermit < ASTNode
      def typecheck_and_resolve(context)
        auth_class_node, auth_class = context.auth_class
        if auth_class.nil?
          raise ADSLError, "Inusergroup cannot be used without having defined an authenticable class (line #{@lineno})"
        end

        groups = @group_names.map do |gn|
          group_name = gn.text
          group = context.usergroups[group_name]
          raise ADSLError, "No groupname found by name #{gn.text} on line #{gn.lineno}" if group.nil?
          group[1]
        end
        groups << ADSL::DS::DSAllUsers.new if groups.empty?

        ops, expr_result = ADSL::Lang::DSTranslation::Util.ops_and_expr_from_nodes context, @ops, @expr

        ADSL::DS::DSPermit.new :usergroups => groups, :ops => ops, :expr => expr_result.expr
      end
    end

    class ASTInvariant < ASTNode
      def typecheck_and_resolve(context)
        formula_result = @formula.typecheck_and_resolve context
        unless formula_result.type_sig.is_bool_type?
          raise ADSLError, "Invariant formula is not boolean (type provided `#{formula_result.type_sig}` on line #{ @lineno })"
        end
        if formula_result.has_side_effects?
          raise ADSLError, "Invariant formulas cannot have side effects (line #{ @lineno })"
        end

        name = @name.nil? ? nil : @name.text
            
        ADSL::DS::DSInvariant.new :name => name, :formula => formula_result.expr
      end
    end

    class ASTRule < ASTNode
      def typecheck_and_resolve(context)
        formula_result = @formula.typecheck_and_resolve context
        unless formula_result.type_sig.is_bool_type?
          raise ADSLError, "Rule formula is not boolean (type provided `#{formula_result.type_sig}` on line #{ @lineno })"
        end
        if formula_result.has_side_effects?
          raise ADSLError, "Rule formulas cannot have side effects (line #{ @lineno })"
        end

        return ADSL::DS::DSRule.new :formula => formula_result.expr
      end
    end

    class ASTBoolean < ASTNode
      def typecheck_and_resolve(context)
        expr = case @bool_value
        when true;  ADSL::DS::DSConstant::TRUE
        when false; ADSL::DS::DSConstant::FALSE
        when nil;   ADSL::DS::DSConstant::BOOL_STAR
        else raise "Unknown bool value #{@bool_value}"
        end
        gen_translation_result :expr => expr
      end
    end
    
    class ASTForAll < ASTNode
      def typecheck_and_resolve(context)
        context.in_stack_frame do
          vars = []
          objsets = []
          state_transitions = []
          @vars.each do |var_node, objset_node|
            objset_result = objset_node.typecheck_and_resolve context
            unless objset_result.type_sig.is_objset_type?
              raise ADSLError, "Quantification possible only over objset sets (type provided `#{objset_result.type_sig}` on line #{ @lineno })"
            end
        
            var = ADSL::DS::DSQuantifiedVariable.new :name => var_node.text, :type_sig => objset_result.type_sig
            context.define_var var, var_node

            vars << var
            objsets << objset_result.expr
            state_transitions += objset_result.state_transitions
          end
          subformula_result = @subformula.typecheck_and_resolve context
          unless subformula_result.type_sig.is_bool_type?
            raise ADSLError, "Quantification formula is not boolean (type provided `#{subformula_result.type_sig}` on line #{ @lineno })"
          end

          gen_translation_result(
            :state_transitions => state_transitions,
            :expr => ADSL::DS::DSForAll.new(:vars => vars, :objsets => objsets, :subformula => subformula_result.expr)
          )
        end
      end
    end

    class ASTExists < ASTNode
      def typecheck_and_resolve(context)
        context.in_stack_frame do
          state_transitions = []
          vars = []
          objsets = []
          @vars.each do |var_node, objset_node|
            objset_result = objset_node.typecheck_and_resolve context
            unless objset_result.type_sig.is_objset_type?
              raise ADSLError, "Quantification possible only over objset sets (type provided `#{objset_result.type_sig}` on line #{ @lineno })"
            end
            
            var = ADSL::DS::DSQuantifiedVariable.new :name => var_node.text, :type_sig => objset_result.type_sig
            context.define_var var, var_node

            vars << var
            objsets << objset_result.expr
            state_transitions += objset_result.state_transitions
          end
          subformula_result = if @subformula
            @subformula.typecheck_and_resolve(context)
          else
            gen_translation_result(:expr => ADSL::DS::DSConstant::TRUE)
          end
          unless subformula_result.type_sig.is_bool_type?
            raise ADSLError, "Quantification formula is not boolean (type provided `#{subformula_result.type_sig}` on line #{ @lineno })"
          end

          gen_translation_result(
            :state_transitions => state_transitions,
            :expr => ADSL::DS::DSExists.new(:vars => vars, :objsets => objsets, :subformula => subformula_result.expr)
          )
        end
      end
    end

    class ASTNot < ASTNode
      def typecheck_and_resolve(context)
        subformula_result = @subformula.typecheck_and_resolve context
        unless subformula_result.type_sig.is_bool_type?
          raise ADSLError, "Negation subformula is not boolean (type provided `#{subformula_result.type_sig}` on line #{ @lineno })"
        end
        subformula_result.with_expr(ADSL::DS::DSNot.new :subformula => subformula_result.expr)
      end
    end

    class ASTAnd < ASTNode
      def typecheck_and_resolve(context)
        subformula_results = @subformulae.map{ |o| o.typecheck_and_resolve context }
        subformula_results.each do |subformula_result|
          unless subformula_result.type_sig.is_bool_type?
            raise ADSLError, "Negation subformula is not boolean (type provided `#{subformula_result.type_sig}` on line #{ @lineno })"
          end
        end
        gen_translation_result(
          :state_transitions => subformula_results.map(&:state_transitions).flatten,
          :expr => ADSL::DS::DSAnd.new(:subformulae => subformula_results.map(&:expr))
        )
      end
    end
    
    class ASTOr < ASTNode
      def typecheck_and_resolve(context)
        subformula_results = @subformulae.map{ |o| o.typecheck_and_resolve context }
        subformula_results.each do |subformula_result|
          unless subformula_result.type_sig.is_bool_type?
            raise ADSLError, "Negation subformula is not boolean (type provided `#{subformula_result.type_sig}` on line #{ @lineno })"
          end
        end
        gen_translation_result(
          :state_transitions => subformula_results.map(&:state_transitions).flatten,
          :expr => ADSL::DS::DSOr.new(:subformulae => subformula_results.map(&:expr))
        )
      end
    end

    class ASTXor < ASTNode
      def typecheck_and_resolve(context)
        subformula_results = @subformulae.map{ |o| o.typecheck_and_resolve context }
        subformula_results.each do |subformula_result|
          unless subformula_result.type_sig.is_bool_type?
            raise ADSLError, "Xor subformula is not boolean (type provided `#{subformula_result.type_sig}` on line #{ @lineno })"
          end
        end
        gen_translation_result(
          :state_transitions => subformula_results.map(&:state_transitions).flatten,
          :expr => ADSL::DS::DSXor.new(:subformulae => subformula_results.map(&:expr))
        )
      end
    end

    class ASTImplies < ASTNode
      def typecheck_and_resolve(context)
        subformula1_result = @subformula1.typecheck_and_resolve context
        subformula2_result = @subformula2.typecheck_and_resolve context
        unless subformula1_result.type_sig.is_bool_type?
          raise ADSLError, "Implication subformula 1 is not boolean (type provided `#{subformula1_result.type_sig}` on line #{ @lineno })"
        end
        unless subformula2_result.type_sig.is_bool_type?
          raise ADSLError, "Implication subformula 2 is not boolean (type provided `#{subformula2_result.type_sig}` on line #{ @lineno })"
        end
        gen_translation_result(
          :state_transitions => subformula1_result.state_transitions + subformula2_result.state_transitions,
          :expr => ADSL::DS::DSImplies.new(:subformula1 => subformula1_result.expr, :subformula2 => subformula2_result.expr)
        )
      end
    end

    class ASTEqual < ASTNode
      def typecheck_and_resolve(context)
        expr_results = @exprs.map{ |o| o.typecheck_and_resolve context }

        # will raise an error if no single common supertype exists
        if ADSL::DS::TypeSig.join(expr_results.map(&:type_sig), false).is_invalid_type?
          raise ADSLError, "Comparison of incompatible types #{expr_results.map(&:type_sig).map(&:to_s).join ' and '} on line #{@lineno}"
        end
        
        gen_translation_result(
          :state_transitions => expr_results.map(&:state_transitions).flatten,
          :expr => ADSL::DS::DSEqual.new(:exprs => expr_results.map(&:expr))
        )
      end
    end

    class ASTIn < ASTNode
      def typecheck_and_resolve(context)
        objset1_result = @objset1.typecheck_and_resolve context
        objset2_result = @objset2.typecheck_and_resolve context
        
        unless objset1_result.type_sig.is_objset_type?
          raise ADSLError, "In relation possible only on objset sets (type provided `#{objset1_result.type_sig}` on line #{ @lineno })"
        end
        unless objset2_result.type_sig.is_objset_type?
          raise ADSLError, "In relation possible only on objset sets (type provided `#{objset2_result.type_sig}` on line #{ @lineno })"
        end
        unless objset1_result.type_sig <= objset2_result.type_sig
          raise ADSLError, "Object sets are not of compatible types: #{objset1_result.type_sig} and #{objset2_result.type_sig}"
        end

        expr = ADSL::DS::Boolean::TRUE if objset1_result.type_sig.cardinality.empty?
        expr ||= ADSL::DS::Boolean::FALSE if objset1_result.type_sig.cardinality.min > objset2_result.type_sig.cardinality.max
        expr ||= ADSL::DS::DSEmpty.new :objset => objset1_result.expr if objset2_result.type_sig.cardinality.empty?
        expr ||= ADSL::DS::Boolean::TRUE if objset2_result.is_a?(ADSL::DS::DSAllOf) && objset2_result.klass.parents.empty?
        
        expr ||= ADSL::DS::DSIn.new :objset1 => objset1_result.expr, :objset2 => objset2_result.expr

        gen_translation_result(
          :state_transitions => objset1_result.state_transitions + objset2_result.state_transitions,
          :expr => expr
        )
      end
    end
    
    class ASTIsEmpty < ASTNode
      def typecheck_and_resolve(context)
        objset_result = @objset.typecheck_and_resolve context
        unless objset_result.type_sig.is_objset_type?
          raise ADSLError, "IsEmpty possible only on objset sets (type provided `#{objset_result.type_sig}` on line #{ @lineno })"
        end

        expr = ADSL::DS::DSConstant::TRUE if objset_result.type_sig.cardinality.empty?
        expr ||= ADSL::DS::DSConstant::FALSE if objset_result.type_sig.cardinality.any?
        expr ||= ADSL::DS::DSIsEmpty.new :objset => objset_result.expr

        objset_result.with_expr expr
      end
    end

  end
end
