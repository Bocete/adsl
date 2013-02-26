require 'rubygems'
require 'active_support/all'
require 'util/util'

class String
  def resolve_spass
    self
  end

  def split_by_zero_level_comma
    parts = []
    sequence_beginning_index = 0
    index = 0
    paren_level = 0
    while index < length
      if self[index, 1] == '('
        paren_level += 1
      elsif self[index, 1] == ')'
        paren_level -= 1
        raise ArgumentError, 'Unmatching parenthesis' if paren_level < 0
      elsif self[index, 1] == ',' and paren_level == 0
        parts << self[sequence_beginning_index, index - sequence_beginning_index].strip
        sequence_beginning_index = index + 1
      end
      index += 1
    end
    parts << self[sequence_beginning_index, length - sequence_beginning_index].strip
    parts
  end
end

class Symbol
  def resolve_spass
    to_s
  end
end

class TrueClass
  def resolve_spass
    "true"
  end
end

class FalseClass
  def resolve_spass
    "false"
  end
end

module FOL
  class Not
    def initialize(*formulae)
      @formulae = formulae.flatten
      raise ArgumentError, "At least one subformula required" if @formulae.empty?
    end

    def resolve_spass
      children = @formulae.map{ |obj| obj.resolve_spass }
      children.delete_if{ |a| a == 'false' }
      return 'false' if children.include? 'true'
      return And.new(children.map{ |child| child.match('\Anot\((.*)\)\z') ? $1 : "not(#{child})" }).resolve_spass
    end
  end

  
  class And
    attr_reader :objs
    
    def initialize(*objs)
      @objs = objs.flatten
    end

    def resolve_spass
      children = @objs.map{ |child| child.resolve_spass }
      children = children.map{ |child| child.match('\Aand\((.*)\)\z') ? $1.split_by_zero_level_comma : child }.flatten
      children.delete_if{ |a| a == 'true' }
      return 'false' if children.include? 'false'
      return 'true' if children.empty?
      return children.first if children.length == 1
      return "and(#{children.join(', ')})"
    end
  end

  class Or
    attr_reader :objs

    def initialize(*objs)
      @objs = objs.flatten
    end

    def resolve_spass
      children = @objs.map{ |child| child.resolve_spass }
      children = children.map{ |child| child.match('\Aor\((.*)\)\z') ? $1.split_by_zero_level_comma : child }.flatten
      children.delete_if{ |a| a == 'false' }
      return 'true' if children.include? 'true'
      return 'false' if children.empty?
      return children.first if children.length == 1
      return "or(#{children.join(', ')})"
    end
  end
  
  class ForAll
    def initialize(*params)
      params = params.flatten
      raise ArgumentError, "At least a formula required" if params.length < 1
      @args = params.first(params.length - 1)
      @formula = params.last
    end

    def resolve_spass
      args = @args.map{ |obj| obj.resolve_spass }
      formula = @formula.resolve_spass
      return formula if args.empty?
      return 'true' if formula == 'true'
      return 'false' if formula == 'false'
      "forall( [#{args.join(', ')}], #{formula})" 
    end
  end

  class Exists
    def initialize(*params)
      params = params.flatten
      raise ArgumentError, "At least a formula required" if params.length < 1
      @args = params.first(params.length - 1)
      @formula = params.last
    end

    def resolve_spass
      args = @args.map{ |obj| obj.resolve_spass }
      formula = @formula.resolve_spass
      return formula if args.empty?
      return 'true' if formula == 'true'
      return 'false' if formula == 'false'
      "exists( [#{args.join(', ')}], #{formula})" 
    end
  end
  
  class Equal
    def initialize(*subformulae)
      @subformulae = subformulae.flatten
      raise ArgumentError, "At least two subformulae required" if @subformulae.length < 2
    end

    def resolve_spass
      return @subformulae.first.resolve_spass if @subformulae.length == 1
      combinations = []
      (@subformulae.length-1).times do |index|
        combinations << "equal(#{@subformulae[index].resolve_spass}, #{@subformulae[index+1].resolve_spass})"
      end
      return And.new(combinations).resolve_spass
    end
  end

  class Equiv
    def initialize(*subformulae)
      @subformulae = subformulae.flatten
      raise ArgumentError, "At least two subformulae required" if @subformulae.length < 2
    end

    def resolve_spass
      subformulae = @subformulae.map{ |sub| sub.resolve_spass }
      return subformulae.first if subformulae.length == 1
      return And.new(subformulae).resolve_spass if subformulae.include? 'true'
      return Not.new(subformulae).resolve_spass if subformulae.include? 'false'
      combinations = []
      (subformulae.length-1).times do |index|
        combinations << "equiv(#{subformulae[index]}, #{subformulae[index+1]})"
      end
      return And.new(combinations).resolve_spass
    end
  end
  
  class Implies
    def initialize(from, to)
      @from = from
      @to = to
    end

    def resolve_spass
      from = @from.resolve_spass
      to = @to.resolve_spass
      return to if from == 'true'
      return 'true' if from == 'false'
      return Not.new(from).resolve_spass if to == 'false'
      return 'true' if to == 'true'
      return "implies(#{from}, #{to})"
    end
  end

  class OneOf
    def initialize(*formulae)
      @formulae = formulae.flatten
    end

    def resolve_spass
      return 'false' if @formulae.empty?
      return @formulae.first.resolve_spass if @formulae.length == 1
      return Equiv.new(Not.new(@formulae.first), @formulae.last).resolve_spass if @formulae.length == 2

      substatements = []
      @formulae.length.times do |i|
        formulae_without_i = @formulae.first(i) + @formulae.last(@formulae.length - 1 - i)
        substatements << Implies.new(@formulae[i], Not.new(formulae_without_i))
      end
      And.new(Or.new(@formulae), substatements).resolve_spass
    end
  end

  class IfThenElse
    def initialize(iif, tthen, eelse)
      @iif = iif
      @tthen = tthen
      @eelse = eelse
    end

    def resolve_spass
      And.new(Implies.new(@iif, @tthen), Implies.new(Not.new(@iif), @eelse)).resolve_spass
    end
  end
  
  class IfThenElseEq
    def initialize(iif, tthen, eelse)
      @iif = iif
      @tthen = tthen
      @eelse = eelse
    end

    def resolve_spass
      And.new(Equiv.new(@iif, @tthen), Equiv.new(Not.new(@iif), @eelse)).resolve_spass
    end
  end
  
  class PairwiseEqual
    def initialize(*list)
      list = list.flatten
      @list1 = list.first((list.length/2.0).ceil)
      @list2 = list.last((list.length/2.0).floor)
      raise ArgumentError, "Lists not of equal length: [#{@list1.join(", ")}], [#{@list2.join(", ")}]" if @list1.length != @list2.length
    end

    def resolve_spass
      equalities = []
      @list1.length.times do |i|
        equalities << Equal.new(@list1[i], @list2[i])
      end
      return And.new(equalities).resolve_spass
    end
  end

  # define a function for each of the above classes, starting with underscore and underscored* afterwards
  # *see: http://api.rubyonrails.org/v2.3.8/classes/ActiveSupport/CoreExtensions/String/Inflections.html
  self.constants.each do |klass_name|
    instance_eval do
      klass = FOL.const_get(klass_name)
      self.send :define_method, "_#{klass_name.underscore}".to_sym do |*args|
        klass.new(*args).resolve_spass
      end
    end
  end
end

