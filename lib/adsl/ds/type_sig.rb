require 'adsl/util/general'
require 'adsl/util/partial_ordered'
require 'adsl/fol/first_order_logic'
require 'active_support/all'

module ADSL
  module DS
    module TypeSig

      def self.remove_direct_subtypes(sig_set)
        copy_of = sig_set.dup
        sig_set.each do |sig|
          copy_of.delete_if{ |other| other < sig }
        end
        copy_of
      end

      class Common
        include ADSL::Util::PartialOrdered

        self.singleton_class.send :define_method, :set_typesig_flags do |*types|
          [:unknown, :objset, :ambiguous_objset, :basic, :bool, :invalid].each do |m|
            self.send :define_method, "is_#{m}_type?" do
              types.include? m
            end
          end
        end
      end

      class UnknownType < Common
        set_typesig_flags :unknown
  
        def &(other)
          other
        end
      
        def to_s
          "UnknownType"
        end
  
        def compare(other)
          other.class == UnknownType ? 0 : 1
        end
      end
      UNKNOWN = ADSL::DS::TypeSig::UnknownType.new

      class InvalidType < Common
        set_typesig_flags :invalid

        def &(other)
          self
        end

        def to_s
          "InvalidType"
        end

        def compare(other)
          other.is_invalid_type? ? 0 : -1
        end
      end
      INVALID = ADSL::DS::TypeSig::InvalidType.new

      class BasicType < Common
        attr_reader :type, :subtypes
        set_typesig_flags :basic
  
        def initialize(type, *subtypes)
          @type = type
          @subtypes = subtypes
        end
  
        def to_s
          @type.to_s.camelize
        end
  
        def &(other)
          return self if other.is_unknown_type?
          return TypeSig::INVALID unless other.is_basic_type?
          return self if self == other
          return self if self > other
          return other if other > self
          return TypeSig::INVALID
        end

        def is_bool_type?
          @type == :bool
        end
        
        def ==(other)
          other.is_a?(BasicType) && other.type == self.type
        end
        alias_method :eql?, :==

        def hash
          @type.hash
        end

        def compare(other)
          return 1 if other.is_unknown_type?
          return nil unless other.is_basic_type?
          return 0 if self == other
          return 1 if self.subtypes.include? other
          return -1 if other.subtypes.include? self
          return nil
        end

        UNKNOWN = BasicType.new nil
        BOOL    = BasicType.new :bool
        # STRING  = BasicType.new :string
        # INT     = BasicType.new :int
        # DECIMAL = BasicType.new :decimal, BasicType::INT
        # REAL    = BasicType.new :real, BasicType::INT, BasicType::DECIMAL

        def self.for_sym(sym)
          return BasicType::UNKNOWN if sym == :unknown
          BasicType.const_get sym.to_s.upcase if sym == :bool
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

        def *(other)
          ObjsetCardinality.new([@min * other.min, 2].min, [@max * other.max, 2].min)
        end

        def validate
          raise "Invalid cardinality: #{self}" unless @min <= @max
        end

        def ==(other)
          return false unless other.is_a? ObjsetCardinality
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
          return 2 if value == :many || value == Float::INFINITY
          value
        end

        def empty?
          @min == 0 and @max == 0
        end

        def any?
          @min >= 1
        end

        def singleton?
          @min == 1 and @max == 1
        end

        def to_many?
          @max == 2
        end

        def to_one?
          @max == 1
        end

        alias_method :at_least_one?, :any?

        ZERO      = ObjsetCardinality.new(0)
        ONE       = ObjsetCardinality.new(1)
        ZERO_ONE  = ObjsetCardinality.new(0, 1)
        ZERO_MANY = ObjsetCardinality.new(0, :many)
        ONE_MANY  = ObjsetCardinality.new(1, :many)
      end

      class AmbiguousObjsetType < Common
        attr_reader :cardinality
        set_typesig_flags :objset, :ambiguous_objset

        def initialize(cardinality = ObjsetCardinality::ZERO_MANY)
          @cardinality = cardinality
        end

        def compare(other)
          return -1 if other.is_unknown_type?
          return 0 if other.is_ambiguous_objset_type?
          return 1 if other.is_objset_type?
          return nil
        end

        def |(other)
          return other if other.is_unknown_type?
          return TypeSig::INVALID unless other.is_objset_type?
          return self
        end

        def &(other)
          return self if other.is_unknown_type?
          return TypeSig::INVALID unless other.is_objset_type?
          return other
        end
        
        def eql?(other)
          other.is_a?(Common) && other.is_ambiguous_objset_type?
        end
        alias_method :==, :eql?

        def hash
          self.class.hash
        end

        def to_s
          "[AmbiguousObjset]"
        end
      end

      class ObjsetType < Common
        attr_reader :classes, :cardinality
        set_typesig_flags :objset
  
        # optional cardinality first, followed by classes
        def initialize(*args)
          if args.first.is_a? ObjsetCardinality
            @cardinality = args.shift
          elsif args.first.is_a? Numeric or args.first.is_a? Symbol
            min = args.shift
            if args.first.is_a? Numeric or args.first.is_a? Symbol
              @cardinality = ObjsetCardinality.new min, args.shift
            else
              @cardinality = ObjsetCardinality.new min
            end
          else
            @cardinality = ObjsetCardinality::ZERO_MANY
          end
          @classes = Set[*args.flatten].flatten
          canonize!
        end

        def with_cardinality(*args)
          ObjsetType.new *args, *(@classes.dup)
        end
        
        def canonize!
          @classes.dup.each do |klass|
            @classes -= klass.all_parents(false)
          end
          self
        end
  
        def compare(other)
          return nil unless other.is_a? Common
          return -1 if other.is_unknown_type? || other.is_ambiguous_objset_type?
          return nil unless other.is_objset_type?

          my_full_tree    = self.classes.map{ |k| k.all_parents true }.inject(&:+)
          other_full_tree = other.classes.map{ |k| k.all_parents true }.inject(&:+)
          return 0  if my_full_tree == other_full_tree
          return -1 if my_full_tree.superset? other_full_tree
          return 1  if my_full_tree.subset?   other_full_tree
          nil
        end

        def |(other)
          return self if other.is_unknown_type?
          return TypeSig::INVALID unless other.is_objset_type?
          return other if other.is_ambiguous_objset_type?
          
          ObjsetType.new(self.cardinality | other.cardinality, self.all_parents(true) | other.all_parents(true))
        end
  
        def &(other)
          return self if other.is_unknown_type?
          return TypeSig::INVALID unless other.is_objset_type?
          return self if other.is_ambiguous_objset_type?

          a = ObjsetType.new(self.cardinality | other.cardinality, self.all_parents(true) & other.all_parents(true))
          return TypeSig::INVALID if a.classes.empty?
          a
        end
  
        def all_parents(include_self = false)
          @classes.map{ |c| c.all_parents include_self }.inject(&:+) || Set[]
        end
        
        def all_children(include_self = false)
          @classes.map{ |c| c.all_children include_self }.inject(&:+) || Set[]
        end

        def underscore
          @classes.map(&:to_s).join '_'
        end

        def eql?(other)
          return false unless other.is_a?(ObjsetType)
          canonize!
          other.canonize!
          @classes == other.classes
        end
        alias_method :==, :eql?

        def hash
          @classes.hash
        end

        def to_s
          "[#{ @classes.map(&:to_s).join ', ' }]"
        end
      end
      
      def self.join(*args) # *type_sigs, raise_on_incorrect = true)
        args = args.flatten
        raise_on_incorrect = (true == args.last || false == args.last) ? args.pop : true
        injected = args.inject &:&
        if injected.is_invalid_type? && raise_on_incorrect
          raise IncompatibleTypesException.new *args
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
      
    end
  end
end
