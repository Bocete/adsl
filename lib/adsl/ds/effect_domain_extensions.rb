require 'set'
require 'adsl/lang/ast_nodes'

module ADSL
  # module Parser
  #   class ASTDummyObjset < ::ADSL::Lang::Parser::ASTNode
  #     def objset_effect_domain_analysis(context, info)
  #       return [], true if @type_sig.cardinality.empty?
  #       return @type_sig.all_children(true), false
  #     end
  #   end
  # end

  module DS
    class NodeEffectDomainInfo
      attr_accessor :info

      def initialize
        @info = Hash.new{ |hash, key| hash[key] = Set.new }
      end

      def read(domain, local = false)
        _effect_domain :read, domain, local
      end

      def create(domain, local = false)
        _effect_domain :create, domain, local
      end
      
      def delete(domain, local = false)
        _effect_domain :delete, domain, local
      end

      def conflicting?
        @info.each do |domain, ops|
          return true if ops.length >= 2 && ops.count{ |op| !op[1] } >= 1
        end
        false
      end
      
      def +(other)
        new = NodeEffectDomainInfo.new
        new.info = @info.merge other.info
        new._level_info
        new
      end

      def to_s
        @info.to_s
      end

      private

      def _effect_domain(cmd, domain, local = false)
        domain = domain.to_sig if domain.is_a? ADSL::DS::DSClass

        domains = nil
        if domain.is_a?(ADSL::DS::TypeSig::ObjsetType)
          domains = domain.classes
        elsif domain.respond_to?(:each)
          domains = domain
        else
          domains = [domain]
        end

        domains.each do |d|
          @info[d] << [cmd, local]
        end

        _level_info

        self
      end
      
      def _level_info
        @info.each do |domain, ops|
          [:read, :delete, :true].each do |op|
            ops.delete([op, true]) if ops.include? [op, false]
          end
        end
      end
    end

    class DSBlock < DSNode
      def effect_domain_analysis(context, info)
        @statements.each do |s|
          s.effect_domain_analysis context, info
        end
      end
    end

    class DSCreateObj < DSNode
      def effect_domain_analysis(context, info)
        info.create [@klass], true
      end
    end

    class DSCreateObjset < DSNode
      def objset_effect_domain_analysis(context, info)
        return [@createobj.klass], true
      end
    end

    class DSDeleteObj < DSNode
      def effect_domain_analysis(context, info)
        objset_types, local = @objset.objset_effect_domain_analysis(context, info)
        info.delete objset_types, local

        parents = objset_types.map{ |c| c.to_sig.all_parents(true) }.inject(&:+)
        context.relations_around(parents).each do |rel|
          next if rel.inverse_of
          info.delete rel, false
        end
      end
    end

    class DSAssignment < DSNode
      def effect_domain_analysis(context, info)
        types, local = @expr.objset_effect_domain_analysis context, info
        @var.assigned_types = types
        @var.assigned_local = local
      end
    end

    class DSCreateTup < DSNode
      def effect_domain_analysis(context, info)
        objset1_types, local1 = @objset1.objset_effect_domain_analysis context, info
        objset2_types, local2 = @objset2.objset_effect_domain_analysis context, info
        
        rel = @relation.inverse_of || @relation

        info.create rel, local1 && local2
      end
    end
    
    class DSDeleteTup < DSNode
      def effect_domain_analysis(context, info)
        objset1_types, local1 = @objset1.objset_effect_domain_analysis context, info
        objset2_types, local2 = @objset2.objset_effect_domain_analysis context, info
        
        rel = @relation.inverse_of || @relation

        info.delete rel, local1 && local2
      end
    end

    class DSFieldSet < DSNode
      def effect_domain_analysis(context, info)
      end
    end

    class DSEither < DSNode
      def effect_domain_analysis(context, info)
        @blocks.each do |b|
          b.effect_domain_analysis context, info
        end
      end
    end

    class DSEitherLambdaExpr < DSNode
      def objset_effect_domain_analysis(context, info)
        types_aggregate, local_aggregate = Set[], true
        @objsets.each do |o|
          types, local = o.objset_effect_domain_analysis(context, info)
          types_aggregate += types
          local_aggregate &&= local
        end
        return types, local_aggregate
      end
    end

    class DSIf < DSNode
      def effect_domain_analysis(context, info)
        @condition.formula_effect_domain_analysis context, info
        @then_block.effect_domain_analysis context, info
        @else_block.effect_domain_analysis context, info
      end
    end

    class DSIfLambdaExpr < DSNode
      def objset_effect_domain_analysis(context, info)
        then_types, then_local = @then_expr.objset_effect_domain_analysis(context, info)
        else_types, else_local = @else_expr.objset_effect_domain_analysis(context, info)
        
        return Set[*(then_types + else_types)], then_local && else_local
      end
    end

    class DSForEach < DSNode
      def effect_domain_analysis(context, info)
        types, local = @objset.objset_effect_domain_analysis(context, info)
        info.read types, local

        @block.effect_domain_analysis context, info
      end
    end

    class DSForEachIteratorObjset < DSNode
      def objset_effect_domain_analysis(context, info)
        return @for_each.objset.type_sig.all_children(true), true
      end
    end

    class DSForEachPreLambdaExpr < DSNode
      def objset_effect_domain_analysis(context, info)
        before_types, before_local = @before_var.objset_effect_domain_analysis(context, info)
        inside_types, inside_local = @inside_var.objset_effect_domain_analysis(context, info)
        
        return Set[*(before_types + inside_types)], before_local && inside_local
      end
    end

    class DSForEachPostLambdaExpr < DSNode
      def objset_effect_domain_analysis(context, info)
        before_types, before_local = @before_var.objset_effect_domain_analysis(context, info)
        inside_types, inside_local = @inside_var.objset_effect_domain_analysis(context, info)
        
        return Set[*(before_types + inside_types)], before_local && inside_local
      end
    end

    class DSVariable < DSNode
      attr_accessor :assigned_types, :assigned_local

      def objset_effect_domain_analysis(context, info)
        @assigned_types ||= type_sig.all_children(true)
        @assigned_local = false if @assigned_local.nil?
        return @assigned_types, @assigned_local
      end
    end

    class DSVariableRead < DSNode
      def objset_effect_domain_analysis(context, info)
        @variable.objset_effect_domain_analysis context, info
      end
    end

    class DSUnion < DSNode
      def objset_effect_domain_analysis(context, info)
        types_aggregate, local_aggregate = Set[], true
        @objsets.each do |o|
          types, local = o.objset_effect_domain_analysis(context, info)
          types_aggregate += types
          local_aggregate &&= local
        end
        return types, local_aggregate
      end
    end

    class DSJoinObjset < DSNode
      def objset_effect_domain_analysis(context, info)
        types_aggregate, local_aggregate = Set[], true
        @objsets.each do |o|
          types, local = o.objset_effect_domain_analysis(context, info)
          types_aggregate += types
          local_aggregate &&= local
        end
        return types, local_aggregate
      end
    end

    class DSDereference < DSNode
      def objset_effect_domain_analysis(context, info)
        objset_types, local = @objset.objset_effect_domain_analysis context, info
        relation = @relation.inverse_of.nil? ? @relation : @relation.inverse_of
        
        info.read objset_types, local
        info.read relation, local

        return relation.to_class.all_children(true), false
      end
    end

    class DSAllOf < DSNode
      def objset_effect_domain_analysis(context, info)
        return @klass.all_children(true), false
      end
    end

    class DSSubset < DSNode
      def objset_effect_domain_analysis(context, info)
        return @objset.objset_effect_domain_analysis(context, info)
      end
    end
    
    class DSOneOf < DSNode
      def objset_effect_domain_analysis(context, info)
        return @objset.objset_effect_domain_analysis(context, info)
      end
    end
    
    class DSForceOneOf < DSNode
      def objset_effect_domain_analysis(context, info)
        return @objset.objset_effect_domain_analysis(context, info)
      end
    end

    class DSEmptyObjset < DSNode
      def objset_effect_domain_analysis(context, info)
        return Set[], true
      end
    end

    class DSConstant < DSNode
      def formula_effect_domain_analysis(context, info)
      end
    end

    class DSForAll < DSNode
      def formula_effect_domain_analysis(context, info)
        @vars.each_index do |index|
          @vars[index].assigned_types, @vars[index].assigned_local = @objsets[index].objset_effect_domain_analysis(context, info)
        end
        @subformula.formula_effect_domain_analysis context, info
      end
    end
    
    class DSExists < DSNode
      def formula_effect_domain_analysis(context, info)
        @vars.each_index do |index|
          @vars[index].assigned_types, @vars[index].assigned_local = @objsets[index].objset_effect_domain_analysis(context, info)
        end
        @subformula.formula_effect_domain_analysis context, info
      end
    end

    class DSQuantifiedVariable < DSNode
      attr_accessor :assigned_types, :assigned_local

      def objset_effect_domain_analysis(context, info)
        @assigned_types ||= type_sig.all_children(true)
        @assigned_local = false if @assigned_local.nil?
        return @assigned_types, @assigned_local
      end
    end

    class DSIn < DSNode
      def formula_effect_domain_analysis(context, info)
        [@objset1, @objset2].each do |o|
          types, local = o.objset_effect_domain_analysis context, info
          info.read types, local
        end
      end
    end
    
    class DSIsEmpty < DSNode
      def formula_effect_domain_analysis(context, info)
        types, local = @objset.objset_effect_domain_analysis context, info
        info.read types, local
      end
    end
    
    class DSNot < DSNode
      def formula_effect_domain_analysis(context, info)
        @subformula.formula_effect_domain_analysis context, info
      end
    end

    class DSOr < DSNode
      def formula_effect_domain_analysis(context, info)
        @subformulae.each do |f|
          f.formula_effect_domain_analysis context, info
        end
      end
    end
    
    class DSAnd < DSNode
      def formula_effect_domain_analysis(context, info)
        @subformulae.each do |f|
          f.formula_effect_domain_analysis context, info
        end
      end
    end
    
    class DSImplies < DSNode
      def formula_effect_domain_analysis(context, info)
        [@subformula1, @subformula2].each do |f|
          f.formula_effect_domain_analysis context, info
        end
      end
    end

    class DSEquiv < DSNode
      def formula_effect_domain_analysis(context, info)
        @subformulae.each do |f|
          f.formula_effect_domain_analysis context, info
        end
      end
    end

    class DSEqual < DSNode
      def formula_effect_domain_analysis(context, info)
        @objsets.each do |o|
          types, local = o.objset_effect_domain_analysis context, info
          info.read types, local
        end
      end
    end
  end
end
