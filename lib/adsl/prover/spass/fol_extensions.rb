require 'adsl/ds/fol_translation/typed_string'
require 'adsl/fol/first_order_logic'

class String
  def to_spass_string
    self
  end
end

class Symbol
  def to_spass_string
    to_s
  end
end

class TrueClass
  def to_spass_string
    "true"
  end
end

class FalseClass
  def to_spass_string
    "false"
  end
end

module ADSL
  class DS::FOLTranslation::TypedString
    alias_method :to_spass_string, :str
  end
  
  module FOL

    class Theorem
      def spass_wrap(with, what)
        return "" if what.length == 0
        return with % what
      end

      def spass_list_of(what, *content)
        spass_wrap "list_of_#{what.to_s}.%s\nend_of_list.", content.flatten.map{ |c| "\n  " + c.to_s }.join("")
      end

      def to_spass_string
        sorts = @sorts.map{ |s| s.name }.join ', '
        functions = @functions.map{ |f| "(#{f.name}, #{ f.arity })" }.join ', '
        predicates = @predicates.map{ |p| "(#{p.name}, #{ p.arity })" }.join ', '
        
        axioms = []
              
        if @sorts.size > 1
          axioms << "formula(forall( [o], #{ FOL::Xor.new(@sorts.map{ |s| s[:o] }).optimize.to_spass_string } ))."
        end
        axioms += @predicates.map do |p|
          next if p.arity == 0
          args = p.arity.times.map{ |i| "o#{i}" }
          "formula(forall( [#{args.join ', '}], implies(#{p.name}(#{args.join ', '}), #{And.new(
            p.arity.times.map{ |i| p.sorts[i][args[i]] }
          ).optimize.to_spass_string }) ))."
        end
        axioms += @functions.map do |f|
          next if f.arity == 0
          args = f.arity.times.map{ |i| "o#{i}" }
          args = [:o] if args.empty?
          "formula(forall( [#{args.join ', '}], #{f.ret_sort.name}(#{f.name}(#{args.join ', '})) ))."
        end
       
        axioms += @axioms.map{ |f| "formula(#{ f.optimize.to_spass_string })." }

        conjecture = "formula(#{@conjecture.optimize.to_spass_string})."
        
        spass = <<-SPASS.gsub(/\n\s*\n/, "\n").gsub(/\ {8}/, "")
        begin_problem(Blahblah).
        list_of_descriptions.
          name({* *}).
          author({* *}).
          status(satisfiable).
          description( {* *} ).
        end_of_list.
        #{spass_list_of( :symbols,
          spass_wrap("functions[%s].", functions),
          spass_wrap("predicates[%s].", predicates),
          spass_wrap("sorts[%s].", sorts)
        )}
        #{spass_list_of( "formulae(axioms)",
          axioms
        )}
        #{spass_list_of( "formulae(conjectures)",
          conjecture
        )}
        end_problem.
        SPASS
        spass
      end
    end

    class PredicateCall
      def to_spass_string
        return @predicate.name if @predicate.arity == 0
        "#{@predicate.name}(#{@args.map(&:to_spass_string).join ', '})"
      end
    end
    
    class FunctionCall
      def to_spass_string
        return @function.name if @function.arity == 0
        "#{@function.name}(#{@args.map(&:to_spass_string).join ', '})"
      end
    end

    class Not
      def to_spass_string
        children = @formulae.map &:to_spass_string
        return And.new(children.map{ |child| "not(#{child})" }).to_spass_string
      end
    end

    class And
      def to_spass_string
        children = @subformulae.map &:to_spass_string
        return 'true' if children.empty?
        return children.first if children.length == 1
        return "and(#{children.join(', ')})"
      end
    end

    class Or
      def to_spass_string
        children = @subformulae.map &:to_spass_string
        return 'false' if children.empty?
        return children.first if children.length == 1
        return "or(#{children.join(', ')})"
      end
    end

    class ForAll
      def to_spass_string
        return @formula.to_spass_string if args.empty?
        
        extra_conditions = []
        args = @args.map do |type, name|
          sig = type.to_sig if type.respond_to? :to_sig
          sig ||= type if type.is_a? ADSL::DS::TypeSig::ObjsetType
          extra_conditions << sig[name] unless sig.nil?

          sort = type.respond_to?(:to_sort) ? type.to_sort : type
          sort[name]
        end

        f = @formula
        f = Implies.new(And.new(extra_conditions), f).optimize if extra_conditions.any?
        "forall( [#{args.map(&:to_spass_string).join(', ')}], #{f.to_spass_string})" 
      end
    end

    class Exists
      def to_spass_string
        return @formula.to_spass_string if args.empty?
        
        extra_conditions = []
        args = @args.map do |type, name|
          sig = type.to_sig if type.respond_to? :to_sig
          sig ||= type if type.is_a? ADSL::DS::TypeSig::ObjsetType
          extra_conditions << sig[name] unless sig.nil?
          
          sort = type.respond_to?(:to_sort) ? type.to_sort : type
          sort[name]
        end

        f = @formula || true
        f = And.new(*extra_conditions, f).optimize if extra_conditions.any?
        "exists( [#{args.map(&:to_spass_string).join(', ')}], #{f.to_spass_string})" 
      end
    end

    class Equal
      def to_spass_string
        subformulae = @subformulae.map &:to_spass_string
        combinations = []
        (subformulae.length-1).times do |index|
          combinations << "equal(#{subformulae[index]}, #{subformulae[index+1]})"
        end
        return And.new(combinations).to_spass_string
      end
    end

    class Equiv
      def to_spass_string
        subformulae = @subformulae.map &:to_spass_string
        combinations = []
        (subformulae.length-1).times do |index|
          combinations << "equiv(#{subformulae[index]}, #{subformulae[index+1]})"
        end
        return And.new(combinations).to_spass_string
      end
    end

    class Implies
      def to_spass_string
        return "implies(#{@from.to_spass_string}, #{@to.to_spass_string})"
      end
    end

    class Xor
      def to_spass_string
        return 'false' if @formulae.empty?
        return @formulae.first.to_spass_string if @formulae.length == 1
        return Equiv.new(Not.new(@formulae[0]), @formulae[1]).to_spass_string if @formulae.length == 2
        substatements = []
        @formulae.length.times do |i|
          formulae_without_i = @formulae.first(i) + @formulae.last(@formulae.length - 1 - i)
          substatements << Implies.new(@formulae[i], Not.new(formulae_without_i))
        end
        And.new(Or.new(@formulae), substatements).optimize.to_spass_string
      end
    end

    class IfThenElse
      def to_spass_string
        And.new(Implies.new(@iif, @tthen), Implies.new(Not.new(@iif), @eelse)).optimize.to_spass_string
      end
    end

    class IfThenElseEq
      def to_spass_string
        And.new(Equiv.new(@iif, @tthen), Equiv.new(Not.new(@iif), @eelse)).optimize.to_spass_string
      end
    end

    class PairwiseEqual
      def to_spass_string
        equalities = []
        @list1.length.times do |i|
          equalities << Equal.new(@list1[i], @list2[i])
        end
        return And.new(equalities).optimize.to_spass_string
      end
    end
  end
end
