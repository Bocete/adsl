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

        def parent_classname
          if @ar_class.superclass == ActiveRecord::Base
            nil
          else
            ASTIdent.new :text => @ar_class.superclass.adsl_ast_class_name
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
          @ar_class.class_exec do

            include ADSL::Parser

            attr_accessor :adsl_ast
            attr_accessible :adsl_ast

            def initialize(attributes = {}, options = {})
              super({
                :adsl_ast => ASTCreateObjset.new(:class_name => ASTIdent.new(:text => self.class.adsl_ast_class_name))
              }.merge(attributes), options)
            end

            # no-ops
            def save;  end
            def save!; end
            def reorder(*params);  self; end
            def order(*params);    self; end
            def includes(*params); self; end
            def all(*params);      self; end
            def scope_for_create;  self; end

            def take
              self.class.new :adsl_ast => ASTOneOf.new(:objset => self.adsl_ast)
            end
            alias_method :take!, :take
            alias_method :first, :take
            alias_method :last,  :take

            def where(*args)
              self.class.new :adsl_ast => ASTSubset.new(:objset => self.adsl_ast)
            end
            alias_method :only,   :where
            alias_method :except, :where
            def merge(other)
              if other.adsl_ast.is_a? ASTAllOf
                self
              elsif self.adsl_ast.is_a? ASTAllOf
                other
              elsif other.is_a? ActiveRecord::Base
                # the scope is on the right hand side; so we can just replace all AllOfs in the right
                # with the left hand side
                other.adsl_ast.block_replace do |node|
                  self if node.is_a? ASTAllOf
                end
              else
                self
              end
            end

            def apply_finder_options(options)
              options.include?(:conditions) ? self.class.new(:adsl_ast => ASTSubset.new(:objset => self.adsl_ast)) : self
            end

            def empty?
              ASTEmpty.new :objset => self.adsl_ast
            end

            def +(other)
              self.class.new :adsl_ast => ASTUnion.new(:objsets => [self.adsl_ast, other.adsl_ast])
            end

            def size
              MetaUnknown.new
            end

            def include?(other)
              other = other.adsl_ast if other.respond_to? :adsl_ast
              if other.is_a? ASTNode and other.class.is_objset?
                ASTIn.new :objset1 => other, :objset2 => self.adsl_ast
              else
                super
              end
            end
            def <=(other); other.include? self; end
            alias_method :>=, :include?

            def method_missing(method, *args, &block)
              # maybe this is a scope invocation?
              if self.class.respond_to? method
                begin
                  prev_scoped = self.class.scoped
                  self.class.scoped = self
                  return self.class.send method, *args, &block
                ensure
                  self.class.scoped = prev_scoped
                end
              else
                super
              end
            end

            def respond_to?(method, include_all = false)
              # maybe this is a scope invocation? hard to say
              super || self.class.respond_to?(method)
            end

            class << self
              include ADSL::Parser
            
              def ar_class
                superclass
              end

              def adsl_ast_class_name
                name.sub('::', '_')
              end

              def all(*params)
                new :adsl_ast => ASTAllOf.new(:class_name => ASTIdent.new(:text => adsl_ast_class_name))
              end
              def scope_for_create;  self; end
              def scope_attributes?; false; end
              def scoped; @scoped || all; end
              def scoped=(scoped); @scoped = scoped; end
              alias_method :order,  :all

              def find(*args)
                self.all.take
              end

              def where(*args)
                self.all.where
              end
              alias_method :only,   :where
              alias_method :except, :where

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

              def respond_to?(method, include_all = false)
                return true if method.to_s =~ /^find_.*$/
                super
              end
            end
          end

          create_destroys @ar_class

          @ar_class.send :default_scope, @ar_class.all

          reflections(:polymorphic => false, :through => false).each do |assoc|
            @ar_class.new.replace_method assoc.name do
              target_class = assoc.class_name.constantize
              result = target_class.new :adsl_ast => ASTDereference.new(
                :objset => self.adsl_ast,
                :rel_name => ASTIdent.new(:text => assoc.name.to_s)
              )
              result.adsl_ast = ASTSubset.new(:objset => result.adsl_ast) if assoc.options.include? :conditions
              result
            end
          end
          reflections(:polymorphic => false, :through => true).each do |assoc|
            @ar_class.new.replace_method assoc.name do
              through_assoc = assoc.through_reflection
              source_assoc = assoc.source_reflection

              first_step = self.send through_assoc.name
              result = first_step.send source_assoc.name

              result.adsl_ast = ASTSubset.new(:objset => result.adsl_ast) if assoc.options.include? :conditions
              result
            end
          end
          reflections(:polymorphic => true).each do |assoc|
            @ar_class.new.replace_method assoc.name do
              ADSL::Extract::Rails::MetaUnknown.new
            end
          end

          adsl_ast_parent_name = parent_classname
          adsl_ast_relations = reflections(:polymorphic => false, :through => false).map{ |ref| reflection_to_adsl_ast ref }

          @ar_class.singleton_class.send :define_method, :adsl_ast do
            ASTClass.new(
              :name => ASTIdent.new(:text => adsl_ast_class_name),
              :parent_name => adsl_ast_parent_name,
              :relations => adsl_ast_relations
            )
          end
        end

      end

    end
  end
end
