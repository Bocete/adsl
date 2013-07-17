require 'active_record'
require 'active_support'
require 'adsl/parser/ast_nodes'

module ADSL
  module Extract
    module Rails
      
      class ActiveRecordMetaclassGenerator
        include ADSL::Parser

        def initialize(ar_class)
          @ar_class = ar_class
        end

        def self.target_classname(classname)
          module_split = classname.split '::'
          (module_split[0..-2] + ["ADSLMeta#{module_split.last}"]).join '::'
        end

        def target_classname
          ActiveRecordMetaclassGenerator.target_classname(@ar_class.name)
        end

        def generate_class
          new_class = Class.new(@ar_class) do

            include ADSL::Parser
            
            attr_accessor :adsl_ast

            def instrumenter
              self.class.instrumenter
            end

            def initialize(attributes = {}, options = {})
              attributes = {
                :adsl_ast => ASTCreateObjset.new(:class_name => ASTIdent.new(:text => self.class.adsl_ast_class_name))
              }.merge attributes
              super
            end

            # no-ops
            def save; end
            def save!; end

            def destroy
              ASTDeleteObj.new :objset => self.adsl_ast
            end
            alias_method :destroy!, :destroy

            def take
              self.new :adsl_ast => ASTOneOf.new(:objset => self.adsl_ast)
            end
            alias_method :take!, :take

            class << self
              include ADSL::Parser

              def instrumenter
                ADSL::Extract::Instrumenter.get_instance
              end
            
              def ar_class
                superclass
              end

              def adsl_ast_class_name
                ar_class.name.sub('::', '_')
              end

              def all
                new :adsl_ast => ASTAllOf.new(:class_name => ASTIdent.new(:text => (adsl_ast_class_name)))
              end

              def find(*args)
                new :adsl_ast => ASTOneOf.new(:objset => self.all.adsl_ast)
              end

              def where(*args)
                new :adsl_ast => ASTSubset.new(:objset => self.all.adsl_ast)
              end

              def build(*args)
                new(*args)
              end

              def method_missing(method, *args, &block)
                if method.to_s =~ /^find_.*$/
                  self.find
                else
                  super
                end
              end
            end
          end

          @ar_class.singleton_class.send :define_method, :instrumented_counterpart do
            new_class
          end

          @ar_class.reflections.values.each do |assoc|
            new_class.send :define_method, assoc.name do
              target_class = self.class.parent_module.const_get(ActiveRecordMetaclassGenerator.target_classname assoc.class_name)
              target_class.new :adsl_ast => ASTDereference.new(
                :objset => self.adsl_ast,
                :rel_name => ASTIdent.new(:text => assoc.name)
              )
            end
          end

          new_class.singleton_class.send :define_method, :adsl_ast do
            ASTClass.new(
              :name => ASTIdent.new(:text => adsl_ast_class_name),
              :parent_name => (ar_class.superclass == ActiveRecord::Base ? nil : ASTIdent.new(:text => ar_class.superclass.instrumented_counterpart.adsl_ast_class_name)),
              :relations => []
            )
          end

          @ar_class.parent_module.const_set target_classname.split('::').last, new_class
          new_class
        end

      end

    end
  end
end
