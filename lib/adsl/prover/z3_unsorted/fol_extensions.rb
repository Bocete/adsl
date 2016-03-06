require 'adsl/ds/fol_translation/typed_string'
require 'adsl/fol/first_order_logic'

class String
  def to_smt2_unsorted_string
    self
  end
end

class Symbol
  def to_smt2_unsorted_string
    to_s
  end
end

class TrueClass
  def to_smt2_unsorted_string
    "true"
  end
end

class FalseClass
  def to_smt2_unsorted_string
    "false"
  end
end

module ADSL
  class DS::FOLTranslation::TypedString
    alias_method :to_smt2_unsorted_string, :str
  end
  
  module FOL

    class Theorem
      def to_smt2_unsorted_string
        output = []

        output << "(set-option :produce-proofs true)"
        output << "(declare-sort Sort 0)"
        output += @sorts.map{ |s| "(declare-fun #{s.name} (Sort) Bool)" }
        output << "(declare-fun SMT2Unsorted (Sort) Bool)"
        output << "(assert (forall ((x Sort)) #{ Xor.new("(SMT2Unsorted x)", *@sorts.map{ |s| "(#{s.name} x)" }).to_smt2_unsorted_string }))"
        output += @functions.map(&:to_smt2_unsorted_string).flatten
        output += @predicates.map(&:to_smt2_unsorted_string).flatten

        output += @axioms.map{ |f| "(assert #{ f.to_smt2_unsorted_string })" }

        output << "(assert (not #{ @conjecture.to_smt2_unsorted_string }))"
        output << "(check-sat)"
      
        "#{ output.join("\n") }\n"
      end
    end

    class Function
      def to_smt2_unsorted_string
        args = @sorts.length.times.map{ |i| "o#{ i+1 }" }
        declaration = []
        if @sorts.empty?
          [
            "(declare-const #{@name} Sort)",
            "(assert (#{@ret_sort.name} (#{@name})))"
          ]
        else
          [
            "(declare-fun #{@name} (#{ @sorts.map{ 'Sort' }.join ' ' }) Sort)",
            "(assert (forall (#{ args.map{ |a| "(#{a} Sort)" }.join ' ' }) (#{@ret_sort.name} (#{ @name } #{args.join ' ' }))))"
          ]
        end
      end
    end
    
    class Predicate
      def to_smt2_unsorted_string
        if @sorts.empty?
          [
            "(declare-const #{@name} Bool)"
          ]
        else
          args = @sorts.length.times.map{ |i| "o#{ i+1 }" }
          conclusion = @sorts.length.times.map{ |i| "(#{ @sorts[i].name } o#{ i+1 })" }
          implication = "(=> (#{@name} #{ args.join ' ' }) #{ And.new(*conclusion).to_smt2_unsorted_string })"
          [  
            "(declare-fun #{@name} (#{ @sorts.map{ 'Sort' }.join ' ' }) Bool)",
            "(assert (forall (#{ args.map{ |a| "(#{a} Sort)" }.join ' ' }) #{implication}))"
          ]
        end
      end
    end

    class PredicateCall
      def to_smt2_unsorted_string
        @predicate.arity == 0 ? @predicate.name : "(#{@predicate.name} #{@args.map(&:to_smt2_unsorted_string).join ' '})"
      end
    end
    
    class FunctionCall
      def to_smt2_unsorted_string
        @function.arity == 0 ? @function.name : "(#{@function.name} #{@args.map(&:to_smt2_unsorted_string).join ' '})"
      end
    end

    class Not
      def to_smt2_unsorted_string
        children = @formulae.map &:to_smt2_unsorted_string
        return And.new(children.map{ |child| "(not #{child})" }).to_smt2_unsorted_string
      end
    end

    class And
      def to_smt2_unsorted_string
        children = @subformulae.map &:to_smt2_unsorted_string
        return 'true' if children.empty?
        return children.first if children.length == 1
        return "(and #{children.join(' ')})"
      end
    end

    class Or
      def to_smt2_unsorted_string
        children = @subformulae.map &:to_smt2_unsorted_string
        return 'false' if children.empty?
        return children.first if children.length == 1
        return "(or #{children.join(' ')})"
      end
    end

    class ForAll
      def to_smt2_unsorted_string
        return @formula.to_smt2_unsorted_string if args.empty?
        
        extra_conditions = []
        args = @args.map do |type, name|
          sig = type.to_sig if type.respond_to? :to_sig
          sig ||= type if type.is_a? ADSL::DS::TypeSig::ObjsetType
          unless sig.nil?
            extra_conditions << sig[name]
          else
            sort = type.respond_to?(:to_sort) ? type.to_sort : type
            extra_conditions << sort[name]
          end
          name
        end

        f = @formula
        f = Implies.new(And.new(extra_conditions), f).optimize if extra_conditions.any?
        "(forall (#{ args.map{ |name| "(#{name} Sort)" }.join ' ' }) #{f.to_smt2_unsorted_string})" 
      end
    end

    class Exists
      def to_smt2_unsorted_string
        return @formula.to_smt2_unsorted_string if args.empty?
        
        extra_conditions = []
        args = @args.map do |type, name|
          sig = type.to_sig if type.respond_to? :to_sig
          sig ||= type if type.is_a? ADSL::DS::TypeSig::ObjsetType
          unless sig.nil?
            extra_conditions << sig[name]
          else
            sort = type.respond_to?(:to_sort) ? type.to_sort : type
            extra_conditions << sort[name]
          end
          name
        end

        f = @formula
        f = And.new(*extra_conditions, f).optimize if extra_conditions.any?
        "(exists (#{ args.map{ |name| "(#{name} Sort)" }.join ' ' }) #{f.to_smt2_unsorted_string})" 
      end
    end

    class Equal
      def to_smt2_unsorted_string
        subformulae = @subformulae.map &:to_smt2_unsorted_string
        "(= #{subformulae.join ' '})"
      end
    end

    class Equiv
      def to_smt2_unsorted_string
        subformulae = @subformulae.map &:to_smt2_unsorted_string
        "(= #{subformulae.join ' '})"
      end
    end

    class Implies
      def to_smt2_unsorted_string
        return "(=> #{@from.to_smt2_unsorted_string} #{@to.to_smt2_unsorted_string})"
      end
    end

    class Xor
      def to_smt2_unsorted_string
        return 'false' if @formulae.empty?
        return @formulae.first.to_smt2_unsorted_string if @formulae.length == 1
        "(xor #{ @formulae.map(&:to_smt2_unsorted_string).join ' ' })"
      end
    end

    class IfThenElse
      def to_smt2_unsorted_string
        And.new(Implies.new(@iif, @tthen), Implies.new(Not.new(@iif), @eelse)).optimize.to_smt2_unsorted_string
      end
    end

    class IfThenElseEq
      def to_smt2_unsorted_string
        And.new(Equiv.new(@iif, @tthen), Equiv.new(Not.new(@iif), @eelse)).optimize.to_smt2_unsorted_string
      end
    end

    class PairwiseEqual
      def to_smt2_unsorted_string
        equalities = []
        @list1.length.times do |i|
          equalities << Equal.new(@list1[i], @list2[i])
        end
        return And.new(equalities).optimize.to_smt2_unsorted_string
      end
    end
  end
end
