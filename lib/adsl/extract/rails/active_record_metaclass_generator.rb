require 'active_record'
require 'active_support'
require 'adsl/parser/ast_nodes'
require 'adsl/extract/rails/other_meta'

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

        def parent_classname
          if @ar_class.superclass == ActiveRecord::Base
            nil
          else
            ASTIdent.new :text => @ar_class.superclass.instrumented_counterpart.adsl_ast_class_name
          end
        end

        def reflection_to_adsl_ast(reflection)
          assoc_name = reflection.name
          target_class = reflection.class_name
          cardinality = reflection.collection? ? [0, 1.0/0.0] : [0, 1]
          inverse_of = case reflection.macro
          when :belongs_to; nil
          when :has_one, :has_many
            reflection.has_inverse? ? reflection.inverse_of : reflection.foreign_key[0..-4]
          when :has_and_belongs_to_many
            foreign_name = reflection.has_inverse? ? reflection.inverse_of : reflection.foreign_key[0..-4]
            assoc_name < foreign_name ? nil : foreign_name
          else
            raise "Unknown association macro `#{reflection.macro}' on #{reflection}"
          end

          ASTRelation.new(
            :cardinality => cardinality,
            :to_class_name => ASTIdent.new(:text => target_class.sub('::', '_')),
            :name => ASTIdent.new(:text => assoc_name.to_s),
            :inverse_of_name => (inverse_of.nil? ? nil : ASTIdent.new(:text => inverse_of.sub('::', '_')))
          )
        end

        def reflections(options = {})
          # true => include only
          # false => exclude
          # nil => ignore filter
          options = {
            :this_class => true,
            :polymorphic => false,
            :through => nil,
          }.merge options

          refs = @ar_class.reflections.values.dup

          case options[:this_class]
          when true;  refs.select!{ |ref| ref.active_record == @ar_class }
          when false; refs.select!{ |ref| ref.active_record != @ar_class}
          end
          
          case options[:polymorphic]
          when true;  refs.select!{ |ref| ref.options[:as] or ref.options[:polymorphic] }
          when false; refs.select!{ |ref| !ref.options[:as] and !ref.options[:polymorphic] }
          end

          case options[:through]
          when true;  refs.select!{ |ref| ref.through_reflection }
          when false; refs.select!{ |ref| ref.through_reflection.nil? }
          end

          refs
        end

        def create_destroys(new_class)
          refls = reflections :this_class => nil
          new_class.send :define_method, :destroy do
            stmts = []
            
            refls.each do |refl|
              next unless [:delete, :delete_all, :destroy, :destroy_all].include? refl.options[:dependent]
                
              if refl.options[:dependent] == :destroy or refl.options[:dependent] == :destroy_all
                if refl.through_reflection.nil?
                  stmts += self.send(refl.name).destroy
                else
                  stmts += self.send(refl.through_reflection.name).destroy
                end
              else
                if refl.through_reflection.nil?
                  stmts += self.send(refl.name).delete
                else
                  stmts += self.send(refl.through_reflection.name).delete
                end
              end
            end

            stmts << ASTDeleteObj.new(:objset => self.adsl_ast)
            stmts
          end
          new_class.send :alias_method, :destroy!, :destroy

          new_class.send :define_method, :delete do
            [ASTDeleteObj.new(:objset => self.adsl_ast)]
          end
          new_class.send :alias_method, :delete!, :delete
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

            def take
              self.new :adsl_ast => ASTOneOf.new(:objset => self.adsl_ast)
            end
            alias_method :take!, :take

            def empty?
              ASTEmpty.new :objset => self.adsl_ast
            end

            def <(other)
              if other.is_a? ASTNode and other.class.is_formula?
                ASTSubset.new :objset1 => self.adsl_ast, :objset2 => other.adsl_ast
              else
                super
              end
            end

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

          create_destroys new_class

          reflections(:polymorphic => false, :through => false).each do |assoc|
            new_class.send :define_method, assoc.name do
              target_class = self.class.parent_module.const_get(ActiveRecordMetaclassGenerator.target_classname assoc.class_name)
              result = target_class.new :adsl_ast => ASTDereference.new(
                :objset => self.adsl_ast,
                :rel_name => ASTIdent.new(:text => assoc.name.to_s)
              )
              assoc.options[:conditions].nil? ? result : ASTSubset.new(:objset => result)
            end
          end
          reflections(:polymorphic => false, :through => true).each do |assoc|
            new_class.send :define_method, assoc.name do
              through_assoc = assoc.through_reflection
              source_assoc = assoc.source_reflection

              first_step = self.send through_assoc.name
              result = first_step.send source_assoc.name

              assoc.options[:conditions].nil? ? result : ASTSubset.new(:objset => result)
            end
          end
          reflections(:polymorphic => true).each do |assoc|
            new_class.send :define_method, assoc.name do
              ADSL::Extract::Rails::MetaUnknown.new
            end
          end

          adsl_ast_parent_name = parent_classname
          adsl_ast_relations = reflections(:polymorphic => false, :through => false).map{ |ref| reflection_to_adsl_ast ref }

          new_class.singleton_class.send :define_method, :adsl_ast do
            ASTClass.new(
              :name => ASTIdent.new(:text => adsl_ast_class_name),
              :parent_name => adsl_ast_parent_name,
              :relations => adsl_ast_relations
            )
          end

          @ar_class.parent_module.const_set target_classname.split('::').last, new_class
          new_class
        end

      end

    end
  end
end
