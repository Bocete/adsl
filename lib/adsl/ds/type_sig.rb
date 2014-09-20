require 'adsl/util/general'
require 'adsl/util/partial_ordered'
require 'adsl/fol/first_order_logic'
require 'active_support/all'

module ADSL
  module DS
    module TypeSig

      def self.join(*args) # *type_sigs, raise_on_incorrect = true)
        args = args.flatten
        raise_on_incorrect = args.last.is_a?(TrueClass) || args.last.is_a?(FalseClass) ? args.pop : true
        injected = args.inject do |memo, sig|
          memo.nil? ? nil : memo.join(sig, raise_on_incorrect)
        end
        injected
      end

      class IncompatibleTypesException < StandardError
        def initialize(*type_sigs)
          super(type_sigs.last.is_a?(String) ?
            type_sigs.pop :
            "Incompatible types: #{type_sigs.map(&:to_s).join(', ')}"
          )
        end
      end
      
      module HasCardinality
        def cardinality
          @cardinality
        end

        def card_none?
          @cardinality == ObjsetCardinality::ZERO
        end
        
        def card_one?
          @cardinality == ObjsetCardinality::ZERO
        end
      end

      class Common
        include ADSL::Util::PartialOrdered

        def initialize
          raise "This serves to wrap a module, not to be initialized"
        end

        def unknown_sig?
          false
        end
      end

      class UnknownType < Common
        include HasCardinality

        def initialize(card = nil)
          @cardinality = card
        end
  
        def join(other, raise_on_incorrect=true)
          other
        end
      
        def unknown_sig?
          true
        end
  
        def to_s
          "UnknownType"
        end
  
        def compare(other)
          other.unknown_sig? ? 0 : -1
        end
      end
      UNKNOWN = ADSL::DS::TypeSig::UnknownType.new

      class InvalidType < Common
        def initialize; end

        def join(other, raise_on_incorrect=true)
          self
        end

        def invalid_sig?
          true
        end

        def to_s
          "InvalidType"
        end

        def compare(other)
          other.invalid_sig? ? 0 : 1
        end
      end
      INVALID = ADSL::DS::TypeSig::InvalidType.new

      class RandomType < Common
        attr_accessor :seed

        def initialize
          @@seed ||= 0
          @seed = @@seed += 1
        end

        def ==(other)
          return other.is_a?(RandomType) && other.seed == @seed
        end
        alias_method :eql?, :==

        def hash
          @seed.hash
        end

        def join(other, raise_on_incorrect=true)
          return self if other.unknown_sig?
          unless self == other
            raise IncompatibleTypesException.new(self, other) if raise_on_incorrect
            return nil
          end
          self
        end

        def to_s
          "RandomType##{@seed}"
        end
      end

      def self.random
        RandomType.new
      end
  
      class BasicType < Common
        attr_reader :type
  
        def initialize(type)
          raise "Unknown basic type: #{type}" unless [:int, :string, :real, :decimal, :bool].include? type
          @type = type
        end
  
        def to_s
          @type.to_s.camelize
        end
  
        def join(other, raise_on_incorrect=true)
          return self if other.unknown_sig?
          unless self == other
            raise IncompatibleTypesException.new(self, other) if raise_on_incorrect
            return nil
          end
          self
        end
        
        def ==(other)
          other.is_a?(BasicType) && other.type == self.type
        end
        alias_method :eql?, :==

        def hash
          @type.hash
        end

        def compare(other)
          return 1 if other.unknown_sig?
          self == other ? 0 : nil
        end
      end

      class ObjsetCardinality
        # possible values are :zero, :one, :many
        attr_reader :min, :max

        def initialize(min, max = :same)
          @min = ObjsetCardinality.numberize min
          @max = max == :same ? min : ObjsetCardinality.numberize(max)
          validate
        end
        
        def |(other)
          ObjsetCardinality.new([@min, other.min].min, [@max, other.max].max)
        end

        def &(other)
          ObjsetCardinality.new([@min, other.min].max, [@max, other.max].min)
        end

        def +(other)
          ObjsetCardinality.new([@min + other.min, 2].min, [@max + other.max, 2].min)
        end

        def validate
          raise "Invalid cardinality: #{self}" unless @min <= @max
        end

        def ==(other)
          @min == other.min && @max == other.max
        end
        alias_method :eql?, :==

        def hash
          [@min, @max].hash
        end

        def to_s
          return "#{@min}+" if @max == 2
          return "#{@min}" if @min == @max
          return "#{@min}-#{@max}"
        end

        def self.numberize(value)
          return 2 if value == :many
          value
        end

        ZERO      = ObjsetCardinality.new(0)
        ONE       = ObjsetCardinality.new(1)
        ZERO_MANY = ObjsetCardinality.new(0, :many)
        ONE_MANY  = ObjsetCardinality.new(1, :many)
      end

      class ObjsetType < Common
        attr_reader :classes
        include HasCardinality
  
        # optional cardinality first, followed by classes
        def initialize(*args)
          if args.first.is_a? ObjsetCardinality
            @cardinality = args.shift
          elsif args.first.is_a? Fixnum or args.first.is_a? Symbol
            min = args.shift
            max = (args.first.is_a?(Fixnum) || args.first.is_a?(Symbol)) ? args.shift : :same
            @cardinality = ObjsetCardinality.new min, max
          else
            @cardinality = ObjsetCardinality::ZERO_MANY
          end
          @classes = Set[*args.flatten].flatten
          canonize!
        end
        
        def canonize!
          @classes.dup.each do |klass|
            @classes -= klass.all_parents(false)
          end
          self
        end
  
        def compare(other)
          return 1 if other.unknown_sig?
          return nil unless other.is_a? ObjsetType

          my_full_tree    = self.classes.map{ |k| k.all_parents true }.inject(&:+)
          other_full_tree = other.classes.map{ |k| k.all_parents true }.inject(&:+)
          return 0  if my_full_tree == other_full_tree
          return -1 if my_full_tree.superset? other_full_tree
          return 1  if my_full_tree.subset?   other_full_tree
          return nil
        end

        def union(other)
          return self
          
          unless other.is_a? ObjsetType
            raise IncompatibleTypesException(self, other)
          end
          
          new_sig = ObjsetType.new(self.cardinality | other.cardinality, self.all_parents(true) | other.all_parents(true))
          if new_sig.invalid_sig?
            raise IncompatibleTypesException(self, other) if raise_on_incorrect
          end

          new_sig
        end
  
        def join(other, raise_on_incorrect=true)
          return self if other.unknown_sig?
          
          unless other.is_a? ObjsetType
            raise IncompatibleTypesException(self, other) if raise_on_incorrect
            return nil
          end
          
          new_sig = ObjsetType.new(self.cardinality & other.cardinality, self.all_parents(true) & other.all_parents(true))
          if new_sig.invalid_sig?
            raise IncompatibleTypesException(self, other) if raise_on_incorrect
            return nil
          end

          new_sig
        end
  
        def all_parents(include_self = false)
          @classes.map{ |c| c.all_parents include_self }.inject(&:+)
        end
        
        def all_children(include_self = false)
          @classes.map{ |c| c.all_children include_self }.inject(&:+)
        end
  
        def invalid_sig?
          @classes.empty?
        end

        def underscore
          @classes.map(&:to_s).join '_'
        end

        def to_s
          @classes.map(&:to_s).join ', '
        end
  
        def ==(other)
          compare(other) == 0 && cardinality == other.cardinality
        end
        alias_method :eql?, :==
      end
    end
  end
end
