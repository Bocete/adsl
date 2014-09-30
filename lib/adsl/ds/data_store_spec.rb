require 'adsl/ds/type_sig'
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

      container_for :name, :sort, :parents, :children, :members do
        @members  ||= []
        @parents  ||= []
        @children ||= []
      end

      def to_s
        @name
      end
      
      def all_children(include_self = false)
        c = Set[*@children]
        c << self if include_self
        until_no_change c do |iter|
          iter + Set[*iter.map(&:children).flatten].flatten
        end
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
        return 1  if self.superclass_of?(other)
        return -1 if other.superclass_of?(self)
        return nil
      end

      def to_sig
        ADSL::DS::TypeSig::ObjsetType.new self
      end

      def relations
        @members.select{ |m| m.is_a? DSRelation }
      end

      def fields
        @members.select{ |m| m.is_a? DSField }
      end
    end

    class DSRelation < DSNode
      container_for :cardinality, :from_class, :to_class, :name, :inverse_of

      def type_sig
        @to_class.to_sig
      end

      def to_s
        "#{from_class.name}.#{name}"
      end
    end

    class DSField < DSNode
      container_for :from_class, :name, :type

      alias_method :type_sig, :type

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
      container_for :var, :expr
    end

    class DSCreateObj < DSNode
      container_for :klass
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

    class DSFieldSet < DSNode
      container_for :objset, :field, :expr
    end

    class DSEither < DSNode
      container_for :blocks, :lambdas
    end
    
    class DSEitherLambdaExpr < DSNode
      container_for :either, :exprs

      def type_sig
        ADSL::DS::TypeSig.join @exprs.map(&:type_sig)
      end
    end

    class DSIf < DSNode
      container_for :condition, :then_block, :else_block
    end

    class DSIfLambdaExpr < DSNode
      container_for :if, :then_expr, :else_expr

      def type_sig
        ADSL::DS::TypeSig.join @then_expr.type_sig, @else_expr.type_sig
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

    class DSForEachPreLambdaExpr < DSNode
      container_for :for_each, :before_var, :inside_var

      def type_sig
        DSTypeSig.join @before_var.type_sig, @inside_var.type_sig
      end
    end
    
    class DSForEachPostLambdaExpr < DSNode
      container_for :for_each, :before_var, :inside_var

      def type_sig
        DSTypeSig.join @before_var.type_sig, @inside_var.type_sig
      end
    end

    class DSVariable < DSNode
      container_for :name, :type_sig
    end

    class DSAnythingExpr < DSNode
      container_for
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

    class DSPickOneObjset < DSNode
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
    
    class DSTryOneOf < DSNode
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
    
    class DSFieldRead < DSNode
      container_for :objset, :field

      def type_sig
        @relation.to_class.to_sig
      end
    end

    class DSEmptyObjset < DSNode
      container_for

      SIG = ADSL::DS::TypeSig::UnknownType.new(ADSL::DS::TypeSig::ObjsetCardinality::ZERO)

      def type_sig
        SIG
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
      container_for :exprs
    end
  end
end
