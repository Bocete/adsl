require 'adsl/ds/fol_translation/typed_string'
require 'adsl/fol/first_order_logic'

class String
  def to_smt2_string
    self
  end
end

class Symbol
  def to_smt2_string
    to_s
  end
end

class TrueClass
  def to_smt2_string
    "true"
  end
end

class FalseClass
  def to_smt2_string
    "false"
  end
end

module ADSL
  class DS::FOLTranslation::TypedString
    alias_method :to_smt2_string, :str
  end
  
  module FOL

    class Theorem
      def to_smt2_string
        output = []

        output << "(set-option :produce-proofs true)"
        output += @sorts.map{ |s| "(declare-sort #{s.name} 0)" }
        output += @functions.map(&:to_smt2_string)
        output += @predicates.map(&:to_smt2_string)

        output += @axioms.map{ |f| "(assert #{ f.to_smt2_string })" }

        output << "(assert (not #{ @conjecture.to_smt2_string }))"
        output << "(check-sat)"
      
        "#{ output.join("\n") }\n"
      end
    end

    class Function
      def to_smt2_string
        if @sorts.empty?
          "(declare-const #{@name} #{@ret_sort.name})"
        else
          "(declare-fun #{@name} (#{ @sorts.map(&:name).join ' ' }) #{@ret_sort.name})"
        end
      end
    end
    
    class FunctionCall
      def to_smt2_string
        @function.arity == 0 ? @function.name : "(#{@function.name} #{@args.map(&:to_smt2_string).join ' '})"
      end
    end
    
    class Predicate
      def to_smt2_string
        if @sorts.empty?
          "(declare-const #{@name} Bool)"
        else
          "(declare-fun #{@name} (#{ @sorts.map(&:name).join ' ' }) Bool)"
        end
      end
    end

    class PredicateCall
      def to_smt2_string
        @predicate.arity == 0 ? @predicate.name : "(#{@predicate.name} #{@args.map(&:to_smt2_string).join ' '})"
      end
    end

    class Not
      def to_smt2_string
        children = @formulae.map &:to_smt2_string
        return And.new(children.map{ |child| "(not #{child})" }).to_smt2_string
      end
    end

    class And
      def to_smt2_string
        children = @subformulae.map &:to_smt2_string
        return 'true' if children.empty?
        return children.first if children.length == 1
        return "(and #{children.join(' ')})"
      end
    end

    class Or
      def to_smt2_string
        children = @subformulae.map &:to_smt2_string
        return 'false' if children.empty?
        return children.first if children.length == 1
        return "(or #{children.join(' ')})"
      end
    end

    class ForAll
      def to_smt2_string
        return @formula.to_smt2_string if args.empty?
        
        extra_conditions = []
        args = @args.map do |type, name|
          sig = type.to_sig if type.respond_to? :to_sig
          sig ||= type if type.is_a? ADSL::DS::TypeSig::ObjsetType
          extra_conditions << sig[name] unless sig.nil?
          
          sort = type.respond_to?(:to_sort) ? type.to_sort : type
          [sort, name]
        end

        f = @formula
        f = Implies.new(And.new(extra_conditions), f).optimize if extra_conditions.any?
        "(forall (#{ args.map{ |sort, name| "(#{name} #{sort.name})" }.join ' ' }) #{f.to_smt2_string})" 
      end
    end

    class Exists
      def to_smt2_string
        return @formula.to_smt2_string if args.empty?
        
        extra_conditions = []
        args = @args.map do |type, name|
          sig = type.to_sig if type.respond_to? :to_sig
          sig ||= type if type.is_a? ADSL::DS::TypeSig::ObjsetType
          extra_conditions << sig[name] unless sig.nil?
          
          sort = type.respond_to?(:to_sort) ? type.to_sort : type
          [sort, name]
        end

        f = @formula
        f = And.new(*extra_conditions, f).optimize if extra_conditions.any?
        "(exists (#{ args.map{ |sort, name| "(#{name} #{sort.name})" }.join ' ' }) #{f.to_smt2_string})" 
      end
    end

    class Equal
      def to_smt2_string
        subformulae = @subformulae.map &:to_smt2_string
        "(= #{subformulae.join ' '})"
      end
    end

    class Equiv
      def to_smt2_string
        subformulae = @subformulae.map &:to_smt2_string
        "(= #{subformulae.join ' '})"
      end
    end

    class Implies
      def to_smt2_string
        return "(=> #{@from.to_smt2_string} #{@to.to_smt2_string})"
      end
    end

    class Xor
      def to_smt2_string
        return 'false' if @formulae.empty?
        return @formulae.first.to_smt2_string if @formulae.length == 1
        "(xor #{ @formulae.map(&:to_smt2_string).join ' ' })"
      end
    end

    class IfThenElse
      def to_smt2_string
        And.new(Implies.new(@iif, @tthen), Implies.new(Not.new(@iif), @eelse)).optimize.to_smt2_string
      end
    end

    class IfThenElseEq
      def to_smt2_string
        And.new(Equiv.new(@iif, @tthen), Equiv.new(Not.new(@iif), @eelse)).optimize.to_smt2_string
      end
    end

    class PairwiseEqual
      def to_smt2_string
        equalities = []
        @list1.length.times do |i|
          equalities << Equal.new(@list1[i], @list2[i])
        end
        return And.new(equalities).optimize.to_smt2_string
      end
    end
  end
end
