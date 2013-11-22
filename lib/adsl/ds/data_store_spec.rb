require 'adsl/util/general'
require 'adsl/util/partial_ordered'

module ADSL
  module DS
    class DSNode
      def list_entity_classes_written_to
        recursively_gather :entity_class_writes
      end

      def list_entity_classes_read
        recursively_gather :entity_class_reads
      end

      def replace(what, with)
        to_inspect = [self]
        inspected = Set.new
        replaced = false
        while not to_inspect.empty?
          elem = to_inspect.pop
          if elem.kind_of? Array
            elem.length.times do |i|
              if elem[i] == what
                elem[i] = with
                replaced = true
              else
                to_inspect << elem[i] unless inspected.include? elem[i]
              end
              inspected << elem[i]
            end
          elsif elem.class.methods.include? 'container_for_fields' or elem.class.methods.include? :container_for_fields
            elem.class.container_for_fields.each do |field_name|
              field_val = elem.send field_name
              if field_val == what
                elem.send "#{field_name}=", with
                replaced = true
              elsif field_val.kind_of?(Array) or field_val.class.methods.include?('container_for_fields')
                to_inspect << field_val unless inspected.include? field_val
              end
              inspected << field_val
            end
          end
        end
        replaced
      end
    end
    
    class DSSpec < DSNode
      container_for :classes, :actions, :invariants
    end

    class DSClass < DSNode
      include ADSL::Util::PartialOrdered

      container_for :name, :parents, :relations do
        @relations = [] if @relations.nil?
        @parents   = [] if @parents.nil?
      end

      def to_s
        @name
      end

      def all_parents(include_self = false)
        p = Set[*@parents]
        p << self if include_self
        until_no_change p do |iter|
          iter + Set[*iter.map(&:parents).flatten].flatten
        end
      end

      def superclass_of?(other_class)
        other_class.all_parents(true).include? self
      end

      def compare(other)
        return nil unless other.is_a? DSClass
        return 0  if self == other
        return 1  if self.superclass_of?(other_class)
        return -1 if other_class.superclass_of?(self)
        return nil
      end

      def to_sig
        DSTypeSig.new self
      end
    end

    class DSTypeSig
      attr_reader :classes
      
      include ADSL::Util::PartialOrdered

      def initialize(*classes)
        @classes = Set[*classes.flatten].flatten
        canonize!
      end
      
      def canonize!
        @classes.dup.each do |klass|
          @classes -= klass.all_parents
        end
      end

      def compare(other)
        return nil unless other.is_a? DSTypeSig
        my_full_tree    = self.classes.map{ |k| k.all_parents true }.inject(&:+)
        other_full_tree = other.classes.map{ |k| k.all_parents true }.inject(&:+)
        return 0  if my_full_tree == other_full_tree
        return -1 if my_full_tree >  other_full_tree
        return 1  if my_full_tree <  other_full_tree
        return nil
      end

      def join(other)
        DSTypeSig.join self, other
      end

      def all_parents(include_self = false)
        @classes.map{ |c| c.all_parents include_self }.inject(&:+)
      end

      def nil_sig?
        @classes.empty?
      end

      def to_s
        @classes.map(&:to_s).join ', '
      end

      def ==(other)
        return false unless other.is_a?(DSTypeSig)
        other_seed = other.send(:instance_variable_get, :@random_seed)
        if @random_seed || other_seed
          return false if @random_seed != other_seed
        end
        @classes == other.classes
      end
      alias_method :eql?, :==

      def hash
        [@classes, @random_seed].hash
      end

      def self.join(*type_sigs)
        type_sigs.flatten.inject do |sig1, sig2|
          new_sig = DSTypeSig.new (sig1.all_parents(true) & sig2.all_parents(true))
          raise "Incompatible type signatures joined: #{type_sigs.map(&:to_s).join}" if new_sig.nil_sig?
          new_sig
        end
      end

      def self.random
        sig = DSTypeSig.new
        @@random_seed ||= 0
        sig.send :instance_variable_set, :@random_seed, (@@random_seed += 1)
        sig
      end
      
      EMPTY = DSTypeSig.new
    end

    class DSRelation < DSNode
      container_for :cardinality, :from_class, :to_class, :name, :inverse_of

      def to_s
        "#{from_class.name}.#{name}"
      end
    end

    class DSAction < DSNode
      container_for :name, :args, :cardinalities, :block

      def statements
        @block.statements
      end
    end

    class DSBlock < DSNode
      container_for :statements
    end

    class DSAssignment < DSNode
      container_for :var, :objset
    end

    class DSCreateObj < DSNode
      container_for :klass
      
      def entity_class_writes
        Set[@klass]
      end
    end
    
    class DSCreateObjset < DSNode
      container_for :createobj

      def type_sig
        @createobj.klass.to_sig
      end
    end

    class DSCreateTup < DSNode
      container_for :objset1, :relation, :objset2
    end

    class DSDeleteObj < DSNode
      container_for :objset
    end

    class DSDeleteTup < DSNode
      container_for :objset1, :relation, :objset2
    end

    class DSEither < DSNode
      container_for :blocks, :lambdas
    end
    
    class DSEitherLambdaObjset < DSNode
      container_for :either, :objsets

      def type_sig
        DSTypeSig.join @objsets.map(&:type_sig)
      end
    end

    class DSIf < DSNode
      container_for :condition, :then_block, :else_block
    end

    class DSIfLambdaObjset < DSNode
      container_for :if, :then_objset, :else_objset

      def type_sig
        DSTypeSig.join @then_objset.type_sig, @else_objset.type_sig
      end
    end

    class DSForEachCommon < DSNode
      container_for :objset, :block
    end

    class DSForEach < DSForEachCommon
    end

    class DSFlatForEach < DSForEachCommon
    end

    class DSForEachIteratorObjset < DSNode
      container_for :for_each

      def typecheck_and_resolve(context)
        self
      end

      def type_sig
        @for_each.objset.type_sig
      end
    end

    class DSForEachPreLambdaObjset < DSNode
      container_for :for_each, :before_var, :inside_var

      def type_sig
        DSTypeSig.join @before_var.type_sig, @inside_var.type_sig
      end
    end
    
    class DSForEachPostLambdaObjset < DSNode
      container_for :for_each, :before_var, :inside_var

      def type_sig
        DSTypeSig.join @before_var.type_sig, @inside_var.type_sig
      end
    end

    class DSVariable < DSNode
      container_for :name, :type_sig
    end

    class DSAllOf < DSNode
      container_for :klass
      
      def type_sig
        @klass.to_sig
      end
    end

    class DSSubset < DSNode
      container_for :objset

      def type_sig
        @objset.type_sig
      end
    end

    class DSUnion < DSNode
      container_for :objsets

      def type_sig
        DSTypeSig.join objsets.map(&:type_sig)
      end
    end

    class DSOneOfObjset < DSNode
      container_for :objsets

      def type_sig
        DSTypeSig.join objsets.map(&:type_sig)
      end
    end

    class DSOneOf < DSNode
      container_for :objset

      def type_sig
        @objset.type_sig
      end
    end
    
    class DSForceOneOf < DSNode
      container_for :objset

      def type_sig
        @objset.type_sig
      end
    end

    class DSDereference < DSNode
      container_for :objset, :relation

      def type_sig
        @relation.to_class.to_sig
      end
    end

    class DSEmptyObjset < DSNode
      container_for

      def type_sig
        DSTypeSig::EMPTY
      end
    end

    class DSInvariant < DSNode
      container_for :name, :formula
    end

    class DSBoolean < DSNode
      container_for :bool_value

      TRUE    = DSBoolean.new :bool_value => true
      FALSE   = DSBoolean.new :bool_value => false
      UNKNOWN = DSBoolean.new :bool_value => nil
    end

    class DSForAll < DSNode
      container_for :vars, :objsets, :subformula
    end
    
    class DSExists < DSNode
      container_for :vars, :objsets, :subformula
    end

    class DSQuantifiedVariable < DSNode
      container_for :name, :type_sig
    end

    class DSIn < DSNode
      container_for :objset1, :objset2
    end
    
    class DSIsEmpty < DSNode
      container_for :objset
    end

    class DSNot < DSNode
      container_for :subformula
    end
    
    class DSAnd < DSNode
      container_for :subformulae
    end
    
    class DSOr < DSNode
      container_for :subformulae
    end

    class DSImplies < DSNode
      container_for :subformula1, :subformula2
    end
    
    class DSEquiv < DSNode
      container_for :subformulae
    end
    
    class DSEqual < DSNode
      container_for :objsets
    end
  end
end
