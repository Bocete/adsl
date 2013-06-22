require 'extract/ar/active_record_metaclass'
require 'parser/adsl_ast'
require 'util/util'

class ActiveRecordMetaset
  def metatype
    raise 'No type set'
  end

  def to_ast_node
    raise 'Not implemented'
  end
end

class ARMSAllOf < ActiveRecordMetset
  container_for :metaclass

  def metatype
    metaclass
  end

  def to_ast_node
    ADSL::ADSLAllOf.new :class_name => metaclass.name
  end
end
