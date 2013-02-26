require 'util/util'

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
      inspected = Set[]
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
        elsif elem.class.methods.include? 'container_for_fields'
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
    container_for :name, :parent, :relations, :inverse_relations do
      @relations = [] if @relations.nil?
      @inverse_relations = [] if @inverse_relations.nil?
    end

    def to_s
      @name
    end

    def superclass_of?(other_class)
      until other_class.nil?
        return true if other_class == self
        other_class = other_class.parent
      end
      return false
    end
  end

  class DSRelation < DSNode
    container_for :cardinality, :from_class, :to_class, :name, :inverse_of

    def to_s
      "#{from}.#{name}"
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
  end

  class DSCreateTup < DSNode
    container_for :objset1, :relation, :objset2
  end

  class DSDeleteObj < DSNode
    container_for :objset
    
    def entity_class_writes
      Set[@objset.type]
    end
  end

  class DSDeleteTup < DSNode
    container_for :objset1, :relation, :objset2
  end

  class DSEither < DSNode
    container_for :blocks, :lambdas
  end
  
  class DSEitherLambdaObjset < DSNode
    container_for :either, :vars
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

    def type
      @for_each.objset.type
    end
  end

  class DSForEachPreLambdaObjset < DSNode
    container_for :for_each, :before_var, :inside_var
  end
  
  class DSForEachPostLambdaObjset < DSNode
    container_for :for_each, :before_var, :inside_var
  end

  class DSVariable < DSNode
    container_for :name, :type
  end

  class DSAllOf < DSNode
    container_for :klass
    
    def type
      @klass
    end

    def entity_class_reads
      @klass
    end
  end

  class DSSubset < DSNode
    container_for :objset

    def type
      @objset.type
    end
  end

  class DSOneOf < DSNode
    container_for :objset
    def type
      @objset.type
    end
  end

  class DSDereference < DSNode
    container_for :objset, :relation

    def type
      @relation.to_class
    end
  end

  class DSInvariant < DSNode
    container_for :name, :formula
  end

  class DSBoolean < DSNode
    container_for :bool_value

    TRUE = DSBoolean.new :bool_value => true
    FALSE = DSBoolean.new :bool_value => false

    def type
      :formula
    end
  end

  class DSForAll < DSNode
    container_for :vars, :objsets, :subformula

    def type
      :formula
    end
  end
  
  class DSExists < DSNode
    container_for :vars, :objsets, :subformula

    def type
      :formula
    end
  end

  class DSIn < DSNode
    container_for :objset1, :objset2
    
    def type
      :formula
    end
  end
  
  class DSEmpty < DSNode
    container_for :objset
    
    def type
      :formula
    end
  end

  class DSNot < DSNode
    container_for :subformula

    def type
      :formula
    end
  end
  
  class DSAnd < DSNode
    container_for :subformulae

    def type
      :formula
    end
  end
  
  class DSOr < DSNode
    container_for :subformulae

    def type
      :formula
    end
  end

  class DSImplies < DSNode
    container_for :subformula1, :subformula2

    def type
      :formula
    end
  end
  
  class DSEquiv < DSNode
    container_for :subformulae

    def type
      :formula
    end
  end
  
  class DSEqual < DSNode
    container_for :objsets

    def type
      :formula
    end
  end
end
