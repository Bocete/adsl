require 'active_record'
require 'active_support'

module Extract
  module Rails
    
    class ActiveRecordMetaclassGenerator

      def initialize(ar_class)
        @ar_class = ar_class
      end

      def self.target_classname(classname)
        module_split = classname.split '::'
        (module_split[0..-2] + ["ADSLMeta#{module_split[-1]}"]).join '::'
      end

      def target_classname
        ActiveRecordMetaclassGenerator.target_classname(@ar_class.name.demodulize)
      end

      def target_superclass
        return @ar_class if @ar_class.superclass == ActiveRecord::Base
        self.class.const_get ActiveRecordMetaclassGenerator.target_classname(@ar_class.superclass.name)
      end

      def generate_class
        new_class = Class.new(target_superclass) do

          attr_accessor :adsl_ast

          def self.active_record_class_name
            name[7..-1]
          end

          def self.all
            self.new :adsl_ast => ADSL::ADSLAllOf.new(:class_name => @active_record_class_name)
          end
        end
    
        @ar_class.reflections.values.each do |assoc|
          new_class.send :define_method, assoc.name do
            target_class = self.class.parent_module.const_get(ActiveRecordMetaclassGenerator.target_classname assoc.class_name)
            target_class.new :adsl_ast => ADSL::ADSLDereference.new(:objset => self.adsl_ast, :rel_name => assoc.name)
          end
        end

        @ar_class.parent_module.const_set target_classname, new_class
        new_class
      end

    end

  end
end
