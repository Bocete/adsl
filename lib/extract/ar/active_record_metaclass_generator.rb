require 'active_record'
require 'active_support'

class ActiveRecordMetaclassGenerator
  def initialize(ar_class)
    @ar_class = ar_class
  end

  def target_classname
    "ADSLMeta#{@ar_class.name.demodulize}"
  end

  def target_superclass
    return Object if @ar_class.superclass == ActiveRecord::Base
    @ar_class.parent_module.const_get "ADSLMeta#{@ar_class.superclass.name.demodulize}"
  end

  def generate_class
    new_class = Class.new(target_superclass)

    @ar_class.reflections.values.each do |assoc|
      new_class.send :define_method, assoc.name do
        "#{assoc.name}"
      end
    end

    @ar_class.parent_module.const_set target_classname, new_class
    new_class
  end
end
