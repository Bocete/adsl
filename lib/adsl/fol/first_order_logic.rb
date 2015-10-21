require 'adsl/util/general'
require 'adsl/util/container'
require 'adsl/ds/type_sig'
require 'active_support/all'

class TrueClass
  def optimize
    self
  end
end

class FalseClass
  def optimize
    self
  end
end

class String
  def optimize
    self
  end
end

class Symbol
  def optimize
    self
  end
end

module ADSL
  module FOL
    class Theorem
      container_for :sorts, :predicates, :functions, :axioms, :conjecture
      recursively_comparable
      
      def initialize(opts={})
        @sorts      = opts[:sorts] || []
        @predicates = opts[:predicates] || []
        @functions  = opts[:functions] || []
        @axioms     = opts[:axioms] || []
        @conjecture = opts[:conjecture].nil? ? true : opts[:conjecture]
      end

      def enforce_hard_sorts!
        undefined_sort = Sort.new :undefined
        undefined_sort.singleton_class.instance_eval do
          def [](arg)
            arg.to_s
          end
        end
        @axioms << ForEach.new(undefined_sort, :o, Xor.new(@sorts.map{ |s| s[:o] }))
        self
      end

      def optimize!
        @axioms = @axioms.map &:optimize
        @axioms.delete true
        @conjecture = @conjecture.optimize
        self
      end
    end
    
    class Predicate
      container_for :name, :sorts
      recursively_comparable

      def initialize(name, *sorts)
        @name = name.to_s
        sorts = sorts.flatten
        sorts.each do |s|
          raise ArgumentError, "Invalid sort #{s} provided for predicate" unless s.is_a? ADSL::FOL::Sort
        end
        @sorts = sorts
      end

      def [](*args)
        PredicateCall.new self, *args
      end

      def arity
        @sorts.length
      end

      def negate
        NotPredicate.new(self)
      end

      def to_s
        "#{name}(#{sorts.map(&:to_s).join ', '})"
      end
    end

    class NotPredicate
      container_for :predicate
      recursively_comparable

      def initialize(predicate)
        @predicate = predicate
      end

      def [](*args)
        Not[@predicate[*args]]
      end

      def arity
        @predicate.arity
      end

      def to_s
        "not(#{@predicate.to_s})"
      end
    end

    class PredicateCall
      container_for :predicate, :args
      recursively_comparable

      def initialize(predicate, *args)
        args.flatten!
        if args.length != predicate.arity
          raise "Incorrect arity used to refer to predicate #{predicate.name} " +
            "(was #{args.length}, should be #{predicate.arity})"
        end
        args.each_index do |arg, index|
          next unless arg.respond_to? :to_sort
          if arg.to_sort != predicate.sorts[index]
            raise "Incorrect sort used as arg ##{index} of predicate #{predicate.name} " +
              "(was #{arg.to_sort.name} instead of #{predicate.sorts[index].name})"
          end
        end
        @predicate = predicate
        @args = args
      end

      def optimize
        self
      end
    end

    class Function
      container_for :ret_sort, :name, :sorts
      recursively_comparable

      def initialize(ret_sort, name, *sorts)
        raise ArgumentError, "Invalid function sort #{ret_sort}" unless ret_sort.is_a? ADSL::FOL::Sort
        sorts.each do |s|
          raise ArgumentError, "Invalid sort #{s} provided for predicate" unless s.is_a? ADSL::FOL::Sort
        end
        @name = name.to_s
        @ret_sort = ret_sort
        @sorts = sorts
      end

      def [](*args)
        FunctionCall.new self, *args
      end

      def arity
        @sorts.length
      end

      def to_s
        "#{name}(#{sorts.map(&:to_s).join ', '})"
      end
    end

    class FunctionCall
      container_for :function, :args
      recursively_comparable

      def initialize(function, *args)
        args.flatten!
        if args.length != function.arity
          raise "Incorrect arity used to refer to function #{function.name} " +
            "(was #{args.length}, should be #{function.arity})"
        end
        args.each_index do |arg, index|
          next unless arg.respond_to? :to_sort
          if arg.to_sort != function.sorts[index]
            raise "Incorrect sort used as arg ##{index} of function #{function.name} " +
              "(was #{arg.to_sort.name} instead of #{function.sorts[index].name})"
          end
        end
        @function = function
        @args = args
      end

      def to_sort
        @function.ret_sort
      end

      def optimize
        self
      end
    end
    
    class Sort < Predicate
      container_for :name
      recursively_comparable

      def initialize(name)
        @name = name
        super name, self
      end

      alias_method :to_s, :name
    end
      
    class Not
      container_for :formulae
      recursively_comparable

      def initialize(*formulae)
        @formulae = formulae.flatten
      end

      def optimize
        @formulae.map!(&:optimize).uniq!
        return false if @formulae.include? true
        @formulae.delete false
        return true if @formulae.empty?
        if @formulae.length == 1
          f = @formulae.first
          return !f if [true, false].include? f
          return And.new(f.formulae).optimize if f.is_a? Not
        end
        self
      end
    end
    
    class And
      container_for :subformulae
      recursively_comparable
      
      def initialize(*subformulae)
        @subformulae = subformulae.flatten
      end

      def optimize
        @subformulae.map!(&:optimize)
        @subformulae.map!{ |obj| obj.is_a?(And) ? obj.subformulae : obj }
        @subformulae.flatten!
        @subformulae.uniq!
        @subformulae.delete true
        return false if @subformulae.include? false
        return true if @subformulae.empty?
        return @subformulae.first if @subformulae.length == 1
        self
      end
    end

    class Or
      container_for :subformulae
      recursively_comparable

      def initialize(*subformulae)
        @subformulae = subformulae.flatten
      end

      def optimize
        @subformulae.map!(&:optimize)
        @subformulae.map!{ |obj| obj.is_a?(Or) ? obj.subformulae : obj }
        @subformulae.flatten!
        @subformulae.uniq!
        @subformulae.delete false
        return true if @subformulae.include? true
        return false if @subformulae.empty?
        return @subformulae.first if @subformulae.length == 1
        self
      end
    end
    
    class ForAll
      container_for :formula, :args
      recursively_comparable
      
      def initialize(*params)
        params = params.flatten
        params.try_map!(:unroll).flatten!
        params.compact!
        raise ArgumentError, "At least a formula required" if params.length < 1
        raise ArgumentError, "Quantification requires an odd number of args (was #{params.length})" unless params.length.odd?
        @formula = params.pop
        @args = []
        while params.length > 1
          var_type, var_name = params.shift(2)
          var_type = var_type.type_sig if var_type.respond_to? :type_sig
          args << [var_type, var_name]
        end
      end

      def optimize
        @formula = @formula.optimize
        return @formula if @args.empty? or @formula == true
        self
      end
    end

    class Exists
      container_for :formula, :args
      recursively_comparable
      
      def initialize(*params)
        params = params.flatten
        params.try_map!(:unroll).flatten!
        raise ArgumentError, "At least a formula required" if params.length < 1
        @formula = params.length.even? ? true : params.pop
        @args = []
        while params.length > 1
          var_type, var_name = params.shift(2)
          var_type = var_type.type_sig if var_type.respond_to? :type_sig
          args << [var_type, var_name]
        end
      end

      def optimize
        @formula = @formula.optimize
        return @formula if @args.empty?
        self
      end
    end
    
    class Equal
      container_for :subformulae
      recursively_comparable
      
      def initialize(*subformulae)
        @subformulae = subformulae.flatten
        raise ArgumentError, "At least two subformulae required" if @subformulae.length < 2
      end

      def optimize
        @subformulae.map! &:optimize
        @subformulae.uniq!
        return true if @subformulae.length < 2
        self
      end
    end

    class Equiv
      container_for :subformulae
      recursively_comparable

      def initialize(*subformulae)
        @subformulae = subformulae.flatten
        raise ArgumentError, "At least two subformulae required" if @subformulae.length < 2
      end

      def optimize
        @subformulae.map! &:optimize
        @subformulae.uniq!
        return true if @subformulae.length == 1
        return And.new(subformulae).optimize if @subformulae.include? true
        return Not.new(subformulae).optimize if @subformulae.include? false
        self
      end
    end
    
    class Implies
      container_for :from, :to
      recursively_comparable

      def initialize(from, to)
        @from = from
        @to = to
      end

      def optimize
        @from = @from.optimize
        @to = @to.optimize
        return @to if from == true
        return true if from == false
        return Not.new(from) if to == false
        return true if to == true
        if @to.is_a? Implies
          return Implies.new(And.new(@from, @to.from), @to.to).optimize
        end
        self
      end
    end

    class Xor
      container_for :formulae
      recursively_comparable
      
      def initialize(*formulae)
        @formulae = formulae.flatten
      end

      def optimize
        @formulae.map! &:optimize
        return false if @formulae.empty?
        return @formulae.first if @formulae.length == 1
        return Equiv.new(Not.new(@formulae.first), @formulae.last) if @formulae.length == 2
        self
      end
    end

    class IfThenElse
      container_for :iif, :tthen, :eelse
      recursively_comparable
      
      def initialize(iif, tthen, eelse)
        @iif = iif
        @tthen = tthen
        @eelse = eelse
      end

      def optimize
        @iif = @iif.optimize
        @tthen = @tthen.optimize
        @eelse = @eelse.optimize
        return @tthen if @iif == true
        return @eelse if @iif == false
        self
      end
    end
    
    class IfThenElseEq
      container_for :iif, :tthen, :eelse
      recursively_comparable
      
      def initialize(iif, tthen, eelse)
        @iif = iif
        @tthen = tthen
        @eelse = eelse
      end

      def optimize
        @iif = @iif.optimize
        @tthen = @tthen.optimize
        @eelse = @eelse.optimize
        return @tthen if @iif == true
        return @eelse if @iif == false
        self
      end
    end
    
    class PairwiseEqual
      container_for :list1, :list2
      recursively_comparable
      
      def initialize(*list)
        list = list.flatten
        raise ArgumentError, "Number of arguments not even (#{list.length})" unless list.length.even?
        @list1 = list.first((list.length/2.0).ceil)
        @list2 = list.last((list.length/2.0).floor)
      end

      def optimize
        return true if @list1.empty?
        return Equal.new(@list1.first, @list2.first).optimize if @list1.length == 1
        self
      end
    end

    # define a method for each of the above classes, name starting with a underscore and underscored* afterwards
    # *see: http://api.rubyonrails.org/v2.3.8/classes/ActiveSupport/CoreExtensions/String/Inflections.html
    self.constants.each do |klass_name|
      instance_eval do
        klass = FOL.const_get klass_name
        method_name = "_#{klass_name.to_s.underscore}"
        send :define_method, method_name do |*args|
          klass.new(*args)
        end
        klass.singleton_class.send :define_method, :[] do |*args|
          new *args
        end
      end
    end
  end
end

