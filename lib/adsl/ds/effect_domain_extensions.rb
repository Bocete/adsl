require 'set'
require 'adsl/parser/ast_nodes'

module ADSL
  module Parser
    class ASTTypecheckResolveContext
      def children(type_sig)
        type_sig.classes.map{ |c| c.children(true) }.inject(&:+)
      end

      def set_children_to_classes
        @classes.values.map(&:last).each do |klass|
          klass.to_sig.all_parents(false).each do |parent|
            parent.children << klass
          end
        end
      end

      def relations_around(*classes)
        classes = classes.flatten.map do |c|
          c.respond_to?(:to_a) ? c.to_a : c
        end
        classes = Set[*classes.flatten]
        Set[*@relations.values.map(&:values).flatten(1).map(&:last).select do |rel|
          classes.include?(rel.from_class) || classes.include?(rel.to_class)
        end]
      end
    end

    class ASTNode
    end

    class ASTDummyObjset < ::ADSL::Parser::ASTNode
      def objset_effect_domain_analysis(context, info)
        return @type_sig.children(true), false
      end
    end
  end

  module DS
    class DSClass
      # to be initialized by the context
      def children(include_self = false)
        @children ||= Set.new
        include_self ? @children + [self] : @children
      end
    end

    class DSTypeSig
      def children(include_self = false)
        @classes.map{ |c| c.children include_self }.inject(&:+)
      end
    end

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
        if domain.is_a?(ADSL::DS::DSTypeSig)
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

    class DSBlock
      def effect_domain_analysis(context, info)
        @statements.each do |s|
          s.effect_domain_analysis context, info
        end
      end
    end

    class DSCreateObj
      def effect_domain_analysis(context, info)
        info.create [@klass], true
      end
    end

    class DSCreateObjset
      def objset_effect_domain_analysis(context, info)
        return [@createobj.klass], true
      end
    end

    class DSDeleteObj
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

    class DSAssignment
      def effect_domain_analysis(context, info)
        types, local = @objset.objset_effect_domain_analysis context, info
        @var.assigned_types = types
        @var.assigned_local = local
      end
    end

    class DSCreateTup
      def effect_domain_analysis(context, info)
        objset1_types, local1 = @objset1.objset_effect_domain_analysis context, info
        objset2_types, local2 = @objset2.objset_effect_domain_analysis context, info
        
        rel = @relation.inverse_of || @relation

        info.create rel, local1 && local2
      end
    end
    
    class DSDeleteTup
      def effect_domain_analysis(context, info)
        objset1_types, local1 = @objset1.objset_effect_domain_analysis context, info
        objset2_types, local2 = @objset2.objset_effect_domain_analysis context, info
        
        rel = @relation.inverse_of || @relation

        info.delete rel, local1 && local2
      end
    end

    class DSEither
      def effect_domain_analysis(context, info)
        @blocks.each do |b|
          b.effect_domain_analysis context, info
        end
      end
    end

    class DSEitherLambdaObjset
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

    class DSIf
      def effect_domain_analysis(context, info)
        @condition.formula_effect_domain_analysis context, info
        @then_block.effect_domain_analysis context, info
        @else_block.effect_domain_analysis context, info
      end
    end

    class DSIfLambdaObjset
      def objset_effect_domain_analysis(context, info)
        then_types, then_local = @then_objset.objset_effect_domain_analysis(context, info)
        else_types, else_local = @else_objset.objset_effect_domain_analysis(context, info)
        
        return Set[*(then_types + else_types)], then_local && else_local
      end
    end

    class DSForEachCommon
      def effect_domain_analysis(context, info)
        types, local = @objset.objset_effect_domain_analysis(context, info)
        info.read types, local

        @block.effect_domain_analysis context, info
      end
    end

    class DSForEachIteratorObjset
      def objset_effect_domain_analysis(context, info)
        return @for_each.objset.type_sig.children(true), true
      end
    end

    class DSForEachPreLambdaObjset
      def objset_effect_domain_analysis(context, info)
        before_types, before_local = @before_var.objset_effect_domain_analysis(context, info)
        inside_types, inside_local = @inside_var.objset_effect_domain_analysis(context, info)
        
        return Set[*(before_types + inside_types)], before_local && inside_local
      end
    end

    class DSForEachPostLambdaObjset
      def objset_effect_domain_analysis(context, info)
        before_types, before_local = @before_var.objset_effect_domain_analysis(context, info)
        inside_types, inside_local = @inside_var.objset_effect_domain_analysis(context, info)
        
        return Set[*(before_types + inside_types)], before_local && inside_local
      end
    end

    class DSVariable
      attr_accessor :assigned_types, :assigned_local

      def objset_effect_domain_analysis(context, info)
        @assigned_types ||= type_sig.children(true)
        @assigned_local = false if @assigned_local.nil?
        return @assigned_types, @assigned_local
      end
    end

    class DSUnion
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

    class DSJoinObjset
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

    class DSDereference
      def objset_effect_domain_analysis(context, info)
        objset_types, local = @objset.objset_effect_domain_analysis context, info
        relation = @relation.inverse_of.nil? ? @relation : @relation.inverse_of
        
        info.read objset_types, local
        info.read relation, local

        return relation.to_class.children(true), false
      end
    end

    class DSAllOf
      def objset_effect_domain_analysis(context, info)
        return @klass.children(true), false
      end
    end

    class DSSubset
      def objset_effect_domain_analysis(context, info)
        return @objset.objset_effect_domain_analysis(context, info)
      end
    end
    
    class DSOneOf
      def objset_effect_domain_analysis(context, info)
        return @objset.objset_effect_domain_analysis(context, info)
      end
    end
    
    class DSForceOneOf
      def objset_effect_domain_analysis(context, info)
        return @objset.objset_effect_domain_analysis(context, info)
      end
    end

    class DSEmptyObjset
      def objset_effect_domain_analysis(context, info)
        return Set[], true
      end
    end

    class DSBoolean
      def formula_effect_domain_analysis(context, info)
      end
    end

    class DSForAll
      def formula_effect_domain_analysis(context, info)
        @vars.each_index do |index|
          @vars[index].assigned_types, @vars[index].assigned_local = @objsets[index].objset_effect_domain_analysis(context, info)
        end
        @subformula.formula_effect_domain_analysis context, info
      end
    end
    
    class DSExists
      def formula_effect_domain_analysis(context, info)
        @vars.each_index do |index|
          @vars[index].assigned_types, @vars[index].assigned_local = @objsets[index].objset_effect_domain_analysis(context, info)
        end
        @subformula.formula_effect_domain_analysis context, info
      end
    end

    class DSQuantifiedVariable
      attr_accessor :assigned_types, :assigned_local

      def objset_effect_domain_analysis(context, info)
        @assigned_types ||= type_sig.children(true)
        @assigned_local = false if @assigned_local.nil?
        return @assigned_types, @assigned_local
      end
    end

    class DSIn
      def formula_effect_domain_analysis(context, info)
        [@objset1, @objset2].each do |o|
          types, local = o.objset_effect_domain_analysis context, info
          info.read types, local
        end
      end
    end
    
    class DSIsEmpty
      def formula_effect_domain_analysis(context, info)
        types, local = @objset.objset_effect_domain_analysis context, info
        info.read types, local
      end
    end
    
    class DSNot
      def formula_effect_domain_analysis(context, info)
        @subformula.formula_effect_domain_analysis context, info
      end
    end

    class DSOr
      def formula_effect_domain_analysis(context, info)
        @subformulae.each do |f|
          f.formula_effect_domain_analysis context, info
        end
      end
    end
    
    class DSAnd
      def formula_effect_domain_analysis(context, info)
        @subformulae.each do |f|
          f.formula_effect_domain_analysis context, info
        end
      end
    end
    
    class DSImplies
      def formula_effect_domain_analysis(context, info)
        [@subformula1, @subformula2].each do |f|
          f.formula_effect_domain_analysis context, info
        end
      end
    end

    class DSEquiv
      def formula_effect_domain_analysis(context, info)
        @subformulae.each do |f|
          f.formula_effect_domain_analysis context, info
        end
      end
    end

    class DSEqual
      def formula_effect_domain_analysis(context, info)
        @objsets.each do |o|
          types, local = o.objset_effect_domain_analysis context, info
          info.read types, local
        end
      end
    end
  end
end
