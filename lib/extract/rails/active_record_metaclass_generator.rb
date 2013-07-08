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

          def self.instrumenter
            Extract::Instrumenter.get_instance
          end

          def instrumenter
            self.class.instrumenter
          end

          def self.t(string)
            ADSL::ADSLIdent.new :text => string
          end

          def t(string)
            self.class.t string
          end

          def self.active_record_class_name
            name.match(/^.*ADSLMeta(\w+)$/)[1]
          end

          def self.all
            self.new :adsl_ast => ADSL::ADSLAllOf.new(:class_name => t(active_record_class_name))
          end

          def self.build(*args)
            self.new(*args)
          end

          def initialize(attributes = {}, options = {})
            super
            unless attributes.include? :adsl_ast
              @adsl_ast = ADSL::ADSLCreateObj.new(:class_name => t(self.class.active_record_class_name))
            end
          end

          # no-ops
          def save; end
          def save!; end
        end

        @ar_class.reflections.values.each do |assoc|
          new_class.send :define_method, assoc.name do
            target_class = self.class.parent_module.const_get(ActiveRecordMetaclassGenerator.target_classname assoc.class_name)
            target_class.new :adsl_ast => ADSL::ADSLDereference.new(:objset => self.adsl_ast, :rel_name => t(assoc.name))
          end
        end

        @ar_class.parent_module.const_set target_classname, new_class
        new_class
      end

    end

  end
end
