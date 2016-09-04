require 'backports'

class Array
  def optimize
    map! do |e|
      e.respond_to?(:optimize) ? e.optimize : e
    end
    self
  end
end

module ADSL
  module Lang

    class ASTNode
      def self.has_side_effects(*args)
        raise if args.empty?
        if args.length == 1 && args.first == true || args.first == false
          @has_side_effects = args.first
        elsif Set[*args] < Set[*container_for_fields.map(&:to_sym)]
          @has_side_effects_delegate = args
        else
          "What do these args mean? #{ args }"
        end
      end
      
      def self.evals_to_something(*args)
        raise if args.empty?
        if args.length == 1 && (args.first == true || args.first == false)
          @evals_to_something = args.first
        elsif Set[*args] < Set[*container_for_fields.map(&:to_sym)]
          @evals_to_something_delegate = args
        else
          "What do these args mean? #{ args }"
        end
      end

      def has_side_effects?
        default_val = self.class.instance_variable_get :@has_side_effects
        return default_val unless default_val.nil?

        delegate_fields = self.class.instance_variable_get(:@has_side_effects_delegate) || self.class.container_for_fields
        delegates = delegate_fields.map{ |field_name| send field_name }.flatten.compact
        delegates.any?{ |c| c.has_side_effects? }
      end

      def evals_to_something?
        default_val = self.class.instance_variable_get :@evals_to_something
        return default_val unless default_val.nil?
        
        delegate_fields = self.class.instance_variable_get(:@evals_to_something_delegate) || self.class.container_for_fields
        delegates = delegate_fields.map{ |field_name| send field_name }.flatten.compact
        delegates.any?{ |c| c.evals_to_something? }
      end

      def evals_to_something_always?
        return true if @evals_to_something_always
        default_val = self.class.instance_variable_get :@evals_to_something
        return default_val == :always unless default_val.nil?
        
        delegate_fields = self.class.instance_variable_get(:@evals_to_something_delegate) || self.class.container_for_fields
        delegates = delegate_fields.map{ |field_name| send field_name }.flatten.compact
        delegates.any?{ |c| c.evals_to_something_always? }
      end

      def noop?
        !has_side_effects? && !evals_to_something?
      end

      def optimize
        return ASTRaise.new if self.raises?
        children = self.class.container_for_fields.map{ |field_name| [field_name, send(field_name)] }
        until children.empty?
          child_name, child = children.pop
          if child.respond_to?(:optimize)
            new_value = child.optimize
            send "#{child_name}=", new_value unless new_value.equal? child
          end
        end
        self
      end

      def reaches_view?
        false
      end
    end

    class ASTFlag < ASTNode
      evals_to_something false

      def arbitrary?
        @label != :render
      end

      def reaches_view?
        @label == :render
      end
      
      def has_side_effects?
        !arbitrary?
      end

      def optimize
        ASTEmptyObjset.new
      end
    end

    class ASTSpec < ASTNode
      def split_into_individual_ac_rules
        @ac_rules ||= []
        @ac_rules = @ac_rules.map do |rule|
          subrules = []
          group_name_lists = rule.group_names.map{ |name| [name] }
          group_name_lists = [[]] if group_name_lists.empty?
          group_name_lists.each do |group_names|
            rule.ops.each do |op|
              subrules << ADSL::Lang::ASTPermit.new(:group_names => group_names, :ops => [op], :expr => rule.expr.dup)
            end
          end
          subrules
        end.flatten.uniq
      end

      def remove_redundant_rules
        rules_that_cover_all = @ac_rules.select{ |a| a.expr.is_a? ADSL::Lang::ASTAllOf }.group_by{ |a| a.expr.class_name.text }
        rules_that_dereference = @ac_rules.select{ |a| a.expr.is_a? ADSL::Lang::ASTMemberAccess }

        rules_that_dereference.each do |deref_entry|
          login_class ||= @classes.select{ |c| c.authenticable }.first
          to_class = login_class.members.select{ |a| a.name.text == deref_entry.expr.member_name.text }.first.to_class_name.text
          cover_alls = rules_that_cover_all[to_class]
          next if cover_alls.nil? || cover_alls.empty?

          deref_covered_by_all = cover_alls.any? do |cover_all_entry|
            cover_all_entry.group_names == deref_entry.group_names && cover_all_entry.ops == deref_entry.ops
          end
          @ac_rules.delete deref_entry if deref_covered_by_all
        end
      end

      def merge_rule_ops
        rules_by_non_ops = @ac_rules.group_by{ |e| [e.group_names, e.expr] }
        @ac_rules = rules_by_non_ops.map do |pair, entries|
          next entries.first if entries.length == 1
          ADSL::Lang::ASTPermit.new :group_names => pair[0], :ops => entries.map(&:ops).flatten.uniq.sort, :expr => pair[1]
        end
      end

      def merge_rule_groups
        rules_by_non_role_groups = @ac_rules.group_by{ |e| [e.ops, e.expr] }
        @ac_rules = rules_by_non_role_groups.map do |pair, entries|
          next entries.first if entries.length == 1
          ADSL::Lang::ASTPermit.new :group_names => entries.map(&:group_names).flatten.uniq.sort_by(&:text), :ops => pair[0], :expr => pair[1]
        end
      end

      def optimize_ac_rules
        split_into_individual_ac_rules
        remove_redundant_rules
        merge_rule_ops
        merge_rule_groups
        @ac_rules.sort_by!{ |rule| [rule.group_names.map(&:text), rule.expr.to_adsl] }
      end

      def optimize!
        @pre_optimize_adsl_ast_size ||= adsl_ast_size
        optimize_ac_rules
        @actions.each &:optimize!
        self
      end

      def pre_optimize_adsl_ast_size
        @pre_optimize_adsl_ast_size || adsl_ast_size
      end
    end
    
    class ASTAction < ASTNode
     
      def variable_read_by_view?(var_name)
        var_name.start_with? 'at__'
      end
     
      def optimize!
        @pre_optimize_adsl_ast_size ||= adsl_ast_size

        loop do
          pre_loop_size = adsl_ast_size
          @expr = @expr.optimize

          # remove variables that are assigned to but are not read
          variables_read = Set[]
          @expr.preorder_traverse do |node|
            next unless node.is_a? ASTVariableRead
            variables_read << node.var_name.text
          end
          @expr.preorder_traverse do |node|
            next unless node.is_a? ASTBlock
            next unless node.reaches_view?
            assignments = node.exprs.select{ |s| s.is_a?(ASTAssignment) }
            variables_read += assignments.map{ |s| s.var_name.text }
          end
          @expr.block_replace do |node|
            next unless node.is_a? ASTAssignment
            next if node.var_name.nil? || variables_read.include?(node.var_name.text)
            next if variable_read_by_view? node.var_name.text.to_s
            node.expr
          end

          expr.block_replace do |expr|
            next unless expr.is_a? ASTBlock
            expr.exprs.reject!{ |s| s.is_a? ASTFlag }
            nil
          end

          @expr.exprs.select! &:has_side_effects? if @expr.is_a? ASTBlock
          
          new_adsl_ast_size = adsl_ast_size
          break if new_adsl_ast_size == pre_loop_size
        end
      end

      def pre_optimize_adsl_ast_size
        @pre_optimize_adsl_ast_size || adsl_ast_size
      end
    end

    class ASTBlock < ASTNode
      def flatten!
        @exprs.map! do |e|
          e.is_a?(ASTBlock) ? e.exprs : e
        end.flatten!
        self
      end

      def optimize
        optimized = super
        return optimized unless optimized == self

        return ASTEmptyObjset::INSTANCE if @exprs.empty?
        return ASTRaise.new if raises?
        @exprs = @exprs.map do |stmt|
          stmt.is_a?(ASTBlock) ? stmt.exprs : [stmt]
        end.flatten(1)

        @exprs = @exprs[0..-2].select(&:has_side_effects?) + [@exprs.last]

        return @exprs.first if @exprs.length == 1

        self
      end

      def evals_to_something?
        @exprs.any? && @exprs.last.evals_to_something?
      end

      def reaches_view?
        results = @exprs.map(&:reaches_view?)
        return true if results.any?{ |v| v == true }
        return nil  if results.any?{ |v| v == nil }
        false
      end
    end

    class ASTAssignment < ASTNode
      has_side_effects true
      evals_to_something :expr
    end

    class ASTDeclareVar < ASTNode
      has_side_effects true
      evals_to_something true
    end

    class ASTAssertFormula < ASTNode
      has_side_effects true
      evals_to_something false

      def optimize
        optimized = super
        return optimized unless optimized == self

        if @formula.is_a? ASTBoolean
          case @formula.bool_value
          when true, nil
            return ASTEmptyObjset.new
          when false
            return ASTRaise.new
          end
        elsif @formula.is_a? ASTEmptyObjset
          return ASTRaise.new
        end

        self
      end
    end

    class ASTCreateObjset < ASTNode
      has_side_effects true
      evals_to_something true
    end

    class ASTForEach < ASTNode
      @@include_empty_loops = false

      def self.include_empty_loops?
        @@include_empty_loops
      end

      def self.include_empty_loops=(val)
        @@include_empty_loops = val
      end
      
      has_side_effects :objset, :expr
      evals_to_something :objset

      def has_side_effects?
        return true if ASTForEach.include_empty_loops?
        super
      end

      def evals_to_something?
        return true if ASTForEach.include_empty_loops?
        super
      end

      def optimize
        optimized = super
        return optimized unless optimized == self

        @expr = ASTEmptyObjset.new unless @expr.has_side_effects?
        return self if ASTForEach.include_empty_loops?
        
        return @objset if @expr.noop?
        self
      end
    end

    class ASTReturnGuard < ASTNode
    end

    class ASTReturn < ASTNode
    end

    class ASTRaise < ASTNode
      has_side_effects true
      evals_to_something false
    end

    class ASTIf < ASTNode
      def has_side_effects?
        return @condition.has_side_effects? if @condition.has_side_effects?
        return @then_expr.has_side_effects? if @condition == ASTBoolean::TRUE
        return @else_expr.has_side_effects? if @condition == ASTBoolean::FALSE
        @then_expr.has_side_effects? || @else_expr.has_side_effects?
      end
      
      def evals_to_something?
        return @then_expr.evals_to_something? if @condition == ASTBoolean::TRUE
        return @else_expr.evals_to_something? if @condition == ASTBoolean::FALSE
        @then_expr.evals_to_something? || @else_expr.evals_to_something?
      end

      def optimize
        optimized = super
        return optimized unless optimized == self
        
        return @then_expr if @condition == ASTBoolean::TRUE
        return @else_expr if @condition == ASTBoolean::FALSE

        if @then_expr.raises?
          return ASTBlock.new :exprs => [
            ASTAssertFormula.new(:formula => ASTNot.new(:subformula => @condition)),
            @else_expr
          ].optimize
        elsif @else_expr.raises?
          return ASTBlock.new :exprs => [
            ASTAssertFormula.new(:formula => @condition),
            @then_expr
          ].optimize
        end

        if @then_expr.noop? && @else_expr.noop?
          return ASTBlock.new :exprs => [ @condition, ASTEmptyObjset::INSTANCE ] if @condition.has_side_effects?
          return ASTEmptyObjset::INSTANCE
        end

        if @then_expr.noop?
          t = @then_expr
          @then_expr = @else_expr
          @else_expr = t
          @condition = ASTNot.new(:subformula => @condition).optimize
        end

        flush_halting_status

        return (ASTBlock.new :exprs => [@condition, @then_expr]).optimize if @then_expr == @else_expr

        self
      end

      def reaches_view?
        results = [@then_expr, @else_expr].map(&:reaches_view?)
        return true if results.any?{ |v| v == true }
        return nil  if results.any?{ |v| v == nil }
        false
      end
    end
    
    class ASTDeleteObj < ASTNode
      has_side_effects true
      evals_to_something false
    end

    class ASTCreateTup < ASTNode
      def has_side_effects?
        @objset1.evals_to_something? && @objset2.evals_to_something?
      end
      
      evals_to_something :objset2
    end

    class ASTDeleteTup < ASTNode
      def has_side_effects?
        @objset1.evals_to_something? && @objset2.evals_to_something?
      end
      
      evals_to_something :objset2
    end

    class ASTMemberSet < ASTNode
      has_side_effects true
      evals_to_something :expr
    end

    class ASTAllOf < ASTNode
      has_side_effects false
      evals_to_something true

      def optimize
        optimized = super
        return optimized unless optimized == self

        return @objset if @objset.is_a?(ASTSubset) || @objset.is_a?(ASTTryOneOf)
        return ASTTryOneOf.new :objset => @objset.objset if @objset.is_a?(ASTOneOf)

        self
      end
    end

    class ASTSubset < ASTNode
      has_side_effects :objset
      evals_to_something true

      def optimize
        optimized = super
        return optimized unless optimized == self

        return @objset if @objset.is_a?(ASTSubset)
        return ASTTryOneOf.new :objset => @objset.objset if @objset.is_a?(ASTTryOneOf) or @objset.is_a?(ASTOneOf)

        self
      end
    end
    
    class ASTTryOneOf < ASTNode
      has_side_effects false
      evals_to_something :objset

      def optimize
        optimized = super
        return optimized unless optimized == self

        return @objset if @objset.is_a?(ASTOneOf) or @objset.is_a?(ASTTryOneOf)
        @objset = @objset.objset if @objset.is_a?(ASTSubset)

        self
      end
    end

    class ASTOneOf < ASTNode
      has_side_effects false
      evals_to_something :always

      def optimize
        optimized = super
        return optimized unless optimized == self

        return @objset if @objset.is_a?(ASTOneOf) or @objset.is_a?(ASTTryOneOf)
        @objset = @objset.objset if @objset.is_a?(ASTSubset)
        
        self
      end
    end
    
    class ASTUnion < ASTNode
      has_side_effects :objsets
      evals_to_something :objsets
      
      def optimize
        optimized = super
        return optimized unless optimized == self

        flat_objsets = @objsets.map{ |objset| objset.is_a?(ASTUnion) ? objset.objsets : [objset] }.flatten(1)
        flat_objsets.select!{ |o| o.evals_to_something? }
        flat_objsets.uniq!{ |o| o.has_side_effects? ? o.object_id : o }

        return ASTEmptyObjset.new if flat_objsets.empty?
        return flat_objsets.first if flat_objsets.length == 1

        @objsets = flat_objsets

        self
      end
    end

    class ASTVariableRead < ASTNode
      has_side_effects false
      evals_to_something true
    end

    class ASTMemberAccess < ASTNode
      has_side_effects false
      evals_to_something :objset
    end

    class ASTDereferenceCreate < ASTNode
      has_side_effects true
      evals_to_something true
    end

    class ASTEmptyObjset < ASTNode
      has_side_effects false
      evals_to_something false
    end

    class ASTCurrentUser < ASTNode
      has_side_effects false
      evals_to_something true
    end

    class ASTInUserGroup < ASTNode
      has_side_effects false
      evals_to_something true
    end

    class ASTAllOfUserGroup < ASTNode
      has_side_effects false
      evals_to_something true
    end

    class ASTPermitted < ASTNode
      has_side_effects false
      evals_to_something true
    end

    class ASTPermit < ASTNode
    end

    class ASTInvariant < ASTNode
    end

    class ASTRule < ASTNode
    end

    class ASTBoolean < ASTNode
      has_side_effects false
      evals_to_something true
    end

    class ASTForAll < ASTNode
      has_side_effects :subformula
      evals_to_something true

      def optimize
        optimized = super
        return optimized unless optimized == self

        quantified_vars = Set[]
        @subformula.preorder_traverse do |node|
          quantified_vars << node.var_name.text if node.is_a?(ASTQuantifiedVariable)
        end
        @vars.select! do |v|
          quantified_vars.include? v[0].var_name.text
        end
        return @subformula if @vars.empty?

        self
      end
    end

    class ASTExists < ASTNode
      has_side_effects :subformula
      evals_to_something true
    end

    class ASTNot < ASTNode
      has_side_effects :subformula
      evals_to_something true

      def optimize
        optimized = super
        return optimized unless optimized == self

        return @subformula.subformula if @subformula.is_a?(ASTNot)

        if @subformula.is_a? ASTBoolean
          case @subformula.bool_value
          when true, false
            return ASTBoolean.new :bool_value => !@subformula.bool_value
          when nil
            return @subformula
          end
        elsif @subformula.is_a? ASTEmptyObjset
          return ASTBoolean.new :bool_value => true
        end

        self
      end
    end

    class ASTAnd < ASTNode
      has_side_effects :subformulae
      evals_to_something true

      def optimize
        optimized = super
        return optimized unless optimized == self
        
        @subformulae = @subformulae.map{ |subf| subf.is_a?(ASTAnd) ? subf.subformulae : [subf] }.flatten(1)
        @subformulae.delete ASTBoolean::TRUE
        return ASTBoolean::FALSE if @subformulae.include? ASTBoolean::FALSE
        return ASTBoolean::TRUE if @subformulae.empty?
        return @subformulae.first if @subformulae.length == 1

        self
      end
    end
    
    class ASTOr < ASTNode
      has_side_effects :subformulae
      evals_to_something true

      def optimize
        optimized = super
        return optimized unless optimized == self
        
        @subformulae = @subformulae.map{ |subf| subf.is_a?(ASTOr) ? subf.subformulae : [subf] }.flatten(1)
        @subformulae.delete ASTBoolean::FALSE
        return ASTBoolean::TRUE if @subformulae.include? ASTBoolean::TRUE
        return ASTBoolean::FALSE if @subformulae.empty?
        return @subformulae.first if @subformulae.length == 1

        self
      end
    end

    class ASTXor < ASTNode
      has_side_effects :subformulae
      evals_to_something true

      def optimize
        optimized = super
        return optimized unless optimized == self
          
        @subformulae.delete ASTBoolean::FALSE
        if @subformulae.include? ASTBoolean::TRUE
          return ASTBoolean::FALSE if @subformulae.count(ASTBoolean::TRUE) >= 2
          return ASTAnd.new(:subformulae => @subformulae.reject(ASTBoolean::TRUE)).optimize
        end
        if @subformulae.empty
          return ASTBoolean::FALSE
        elsif @subformulae.length == 1
          return @subformulae.first
        end

        self
      end
    end

    class ASTImplies < ASTNode
      has_side_effects :subformula1, :subformula2
      evals_to_something true
    end

    class ASTEqual < ASTNode
      has_side_effects :exprs
      evals_to_something true

      def optimize
        optimized = super
        return optimized unless optimized == self

        @exprs.uniq!
        if @exprs.include? ASTBoolean::TRUE
          return ASTAnd.new(:subformulae => @exprs).optimize
        end
        if @exprs.include? ASTBoolean::FALSE
          return ASTAnd.new(:subformulae => @exprs.map{ |sub| ASTNot.new(:subformula => sub) }).optimize
        end
        # if there are fewer than 2 elements, we had duplicates making 'equal' trivially true
        return ASTBoolean::TRUE if @exprs.length < 2

        self
      end
    end

    class ASTIn < ASTNode
      has_side_effects :exprs
      evals_to_something true

      def optimize
        optimized = super
        return optimized unless optimized == self

        return ASTBoolean::TRUE  if !@objset1.evals_to_something?
        return ASTBoolean::FALSE if !@objset2.evals_to_something?

        self
      end
    end
    
    class ASTIsEmpty < ASTNode
      has_side_effects :objset
      evals_to_something true

      def optimize
        optimized = super
        return optimized unless optimized == self
        
        return ASTBoolean::TRUE if !@objset.evals_to_something?
        return ASTBoolean::FALSE if @objset.is_a?(ASTOneOf) || @objset.is_a?(ASTCurrentUser)
        self
      end
    end
  end
end

