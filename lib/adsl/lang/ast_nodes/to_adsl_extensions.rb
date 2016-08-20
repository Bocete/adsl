
class Numeric
  alias_method :to_adsl, :to_s
end

class NilClass
  alias_method :to_adsl, :to_s
end

class TrueClass
  alias_method :to_adsl, :to_s
end

class FalseClass
  alias_method :to_adsl, :to_s
end

module ADSL
  module Lang

    class ASTNode
      def in_block
        ASTBlock.new :exprs => [self]
      end
    end

    class ASTDummyObjset < ASTNode
      def to_adsl
        "DummyObjset(#{ @type_sig })"
      end
    end
    
    class ASTFlag < ASTNode
      def to_adsl
        "Flag(#{ @label })"
      end
    end

    class ASTSpec < ASTNode
      def to_adsl
        output = [@classes, @usergroups, @rules, @ac_rules, @actions, @invariants].map do |coll|
          coll.map(&:to_adsl).join("\n")
        end.join("\n\n")
        output.gsub(/\n{2,}/, "\n\n")
      end
    end
    
    class ASTUserGroup < ASTNode
      def to_adsl
        "usergroup #{@name.text}"
      end
    end
    
    class ASTClass < ASTNode
      def to_adsl
        par_names = @parent_names.empty? ? "" : "extends #{@parent_names.map(&:text).join(', ')} "
        "#{authenticable? ? 'authenticable ' : ''}class #{ @name.text } #{ par_names }{\n#{ @members.map(&:to_adsl).map{ |e| "#{e}\n" }.join('').adsl_indent }}"
      end
    end
    
    class ASTRelation < ASTNode
      def to_adsl
        card_str = cardinality[1] == Float::INFINITY ? "#{cardinality[0]}+" : "#{cardinality[0]}..#{cardinality[1]}"
        inv_str = inverse_of_name.nil? ? "" : " inverseof #{inverse_of_name.text}"
        "#{ card_str } #{ @to_class_name.text } #{ @name.text }#{ inv_str }"
      end
    end

    class ASTField < ASTNode
      def to_adsl
        "#{ @type_name } #{ @name }"
      end
    end

    class ASTAction < ASTNode
      def to_adsl
        "action #{@name.text} #{ @expr.in_block.to_adsl }"
      end
    end

    class ASTBlock < ASTNode
      def to_adsl
        return "{}" if @exprs.empty?
        "{\n#{ @exprs.map(&:to_adsl).map{ |e| "#{e}\n" }.join("").adsl_indent }}"
      end

      def in_block
        self
      end
    end

    class ASTAssignment < ASTNode
      def to_adsl
        "#{ @var_name.text } = #{ @expr.to_adsl }"
      end
    end

    class ASTAssertFormula < ASTNode
      def to_adsl
        "assert #{ @formula.to_adsl }"
      end
    end

    class ASTCreateObjset < ASTNode
      def to_adsl
        "create #{ @class_name.text }"
      end
    end

    class ASTForEach < ASTNode
      def to_adsl
        "foreach #{ @var_name.text }: #{ @objset.to_adsl } #{ @expr.in_block.to_adsl }"
      end
    end

    class ASTReturnGuard < ASTNode
      def to_adsl
        "returnguard #{ @expr.to_adsl }"
      end
    end

    class ASTReturn < ASTNode
      def to_adsl
        "return #{ @expr.to_adsl }"
      end
    end

    class ASTVariableRead < ASTNode
      def to_adsl
        @var_name.text
      end
    end

    class ASTRaise < ASTNode
      def to_adsl
        "raise"
      end
    end

    class ASTIf < ASTNode
      def to_adsl
        if @then_expr.noop? && !@else_expr.noop?
          return "if not (#{@condition.to_adsl}) #{ @else_expr.in_block.to_adsl }"
        end
        else_code = @else_expr.is_a?(ASTEmptyObjset) ? "" : " else #{ @else_expr.in_block.to_adsl }"
        "if (#{@condition.to_adsl}) #{ @then_expr.in_block.to_adsl }#{ else_code }"
      end
    end

    class ASTDeleteObj < ASTNode
      def to_adsl
        "delete(#{ @objset.to_adsl })"
      end
    end

    class ASTCreateTup < ASTNode
      def to_adsl
        "#{ @objset1.to_adsl }.#{ @rel_name.text } += #{ @objset2.to_adsl }"
      end
    end

    class ASTDeleteTup < ASTNode
      def to_adsl
        "#{ @objset1.to_adsl }.#{ @rel_name.text } -= #{ @objset2.to_adsl }"
      end
    end

    class ASTMemberSet < ASTNode
      def to_adsl
        "#{ @objset.to_adsl }.#{ @member_name.text } = #{ @expr.to_adsl }"
      end
    end

    class ASTAllOf < ASTNode
      def to_adsl
        @class_name.text
      end
    end

    class ASTSubset < ASTNode
      def to_adsl
        "subset(#{ @objset.to_adsl })"
      end
    end
    
    class ASTTryOneOf < ASTNode
      def to_adsl
        "tryoneof(#{ @objset.to_adsl })"
      end
    end

    class ASTOneOf < ASTNode
      def to_adsl
        "oneof(#{ @objset.to_adsl })"
      end
    end
    
    class ASTUnion < ASTNode
      def to_adsl
        "union(#{ @objsets.map(&:to_adsl).join(', ') })"
      end
    end

    class ASTMemberAccess < ASTNode
      def to_adsl
        "#{ @objset.to_adsl }.#{ @member_name.text }"
      end
    end

    class ASTDereferenceCreate < ASTNode
      def to_adsl
        "create((#{@objset.to_adsl}).#{@rel_name.text})"
      end
    end

    class ASTEmptyObjset < ASTNode
      def to_adsl
        "empty"
      end

      def in_block
        ASTBlock.new :exprs => []
      end
    end

    class ASTCurrentUser < ASTNode
      def to_adsl
        "currentuser"
      end
    end

    class ASTInUserGroup < ASTNode
      def to_adsl
        if @objset.nil? || @objset.is_a?(ASTCurrentUser)
          "inusergroup(#{@groupname.text})"
        else
          "inusergroup(#{@objset.to_adsl}, #{@groupname.text})"
        end
      end
    end

    class ASTAllOfUserGroup < ASTNode
      def to_adsl
        "allofusergroup(#{ groupname.text })"
      end
    end

    class ASTPermitted < ASTNode
      def to_adsl
        "permitted(#{@ops.map(&:to_s).join ', '} #{@expr.to_adsl})"
      end
    end

    class ASTPermit < ASTNode
      def to_adsl
        "permit #{ @group_names.map(&:text).join ', ' } #{ @ops.map(&:to_s).join ', ' } #{@expr.to_adsl}".gsub(/ +/, ' ')
      end
    end

    class ASTInvariant < ASTNode
      def to_adsl
        n = (@name.nil? || @name.text.nil? || @name.text.blank?) ? "" : "#{ @name.text.gsub(/\s/, '_') }: "
        "invariant #{n}#{ @formula.to_adsl }"
      end
    end

    class ASTRule < ASTNode
      def to_adsl
        "rule #{@formula.to_adsl}"
      end
    end

    class ASTBoolean < ASTNode
      def to_adsl
        @bool_value.nil? ? '*' : "#{ @bool_value }"
      end
    end

    class ASTForAll < ASTNode
      def to_adsl
        v = @vars.map{ |var, objset| "#{ var.text } in #{ objset.to_adsl }" }.join ", " 
        "forall(#{v}: #{ @subformula.to_adsl })"
      end
    end

    class ASTExists < ASTNode
      def to_adsl
        v = @vars.map{ |var, objset| "#{ var.text } in #{ objset.to_adsl }" }.join ", " 
        "exists(#{v}: #{ @subformula.nil? ? 'true' : @subformula.to_adsl })"
      end
    end

    class ASTNot < ASTNode
      def to_adsl
        "not #{ @subformula.to_adsl }"
      end
    end

    class ASTAnd < ASTNode
      def to_adsl
        if @subformulae.length == 1
          @subformulae.first.to_adsl
        elsif @subformulae.length == 2
          "(#{ @subformulae.first.to_adsl } and #{@subformulae.last.to_adsl})"
        else
          string = @subformulae[0].to_adsl
          @subformulae[1..-1].each do |f|
            string = "(#{ string } and #{ f.to_adsl })"
          end
          string
        end
      end
    end
    
    class ASTOr < ASTNode
      def to_adsl
        if @subformulae.empty?
          return "(false)"
        elsif @subformulae.length == 1
          @subformulae.first.to_adsl
        elsif @subformulae.length == 2
          "(#{ @subformulae.first.to_adsl } or #{@subformulae.last.to_adsl})"
        else
          string = @subformulae[0].to_adsl
          @subformulae[1..-1].each do |f|
            string = "(#{ string } or #{ f.to_adsl })"
          end
          string
        end
      end
    end

    class ASTXor < ASTNode
      def to_adsl
        if @subformulae.length == 1
          @subformulae.first.to_adsl
        elsif @subformulae.length == 2
          "(#{ @subformulae[0].to_adsl } xor #{ @subformulae[1].to_adsl })"
        else
          string = @subformulae[0].to_adsl
          @subformulae[1..-1].each do |f|
            string = "(#{ string } xor #{ f.to_adsl })"
          end
          string
        end
      end
    end

    class ASTImplies < ASTNode
      def to_adsl
        "implies(#{ @subformula1.to_adsl }, #{ @subformula2.to_adsl })"
      end
    end

    class ASTEqual < ASTNode
      def to_adsl
        "equal(#{ @exprs.map(&:to_adsl).join ", " })"
      end
    end

    class ASTIn < ASTNode
      def to_adsl
        "#{ @objset1.to_adsl } in #{ @objset2.to_adsl }"
      end
    end
    
    class ASTIsEmpty < ASTNode
      def to_adsl
        "isempty(#{ @objset.to_adsl })"
      end
    end
  end
end
