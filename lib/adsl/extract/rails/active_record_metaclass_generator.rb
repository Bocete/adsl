require 'active_record'
require 'active_support'
require 'adsl/parser/ast_nodes'
require 'adsl/extract/rails/other_meta'
require 'adsl/util/test_helper'

module ADSL
  module Extract
    module Rails

      class ActiveRecordMetaclassGenerator
        include ADSL::Parser

        def initialize(ar_class)
          @ar_class = ar_class
          raise "Cyclic destroy dependency detected on class #{@ar_class}. Translation aborted" if cyclic_destroy_dependency?
        end

        def destroy_deps(origin_class)
          Set[*origin_class.reflections.values.select{ |reflection|
            [:destroy, :destroy_all].include? reflection.options[:dependent]
          }.map{ |refl| refl.through_reflection || refl }.map(&:class_name).map(&:constantize)]
        end

        def cyclic_destroy_dependency?
          will_destroy = until_no_change destroy_deps(@ar_class) do |so_far|
            next so_far if so_far.empty?
            so_far.union so_far.map{ |target| destroy_deps(target) }.inject(:union)
          end
          will_destroy.include? @ar_class
        end

        def parent_classname
          if @ar_class.superclass == ActiveRecord::Base
            nil
          else
            ASTIdent.new :text => ActiveRecordMetaclassGenerator.adsl_ast_class_name(@ar_class.superclass)
          end
        end

        def self.adsl_ast_class_name(klass)
          klass.name.sub('::', '_')
        end

        def self.remove_by_from_method(method)
          method.to_s.match(/^([^_]+)_.*/)[1].to_sym if /^[^_]+_by_.*$/ =~ method.to_s
        end

        def reflection_to_adsl_ast(reflection)
          assoc_name = reflection.name.to_s
          target_class = reflection.class_name
          cardinality = reflection.collection? ? [0, 1.0/0.0] : [0, 1]
          inverse_of = case reflection.macro
          when :belongs_to; nil
          when :has_one, :has_many
            inverse_of_col_name = reflection.has_inverse? ? reflection.inverse_of : reflection.foreign_key
            candidates = target_class.constantize.reflections.values.select do |r|
              r.macro == :belongs_to && r.foreign_key.to_sym == inverse_of_col_name.to_sym
            end
            if candidates.empty?
              # just dont treat it as an inverse
              nil
            else
              raise "Multiple opposite relations found for #{reflection}: #{canditates}" if candidates.length > 1
              candidates.first.name.to_s
            end
          when :has_and_belongs_to_many
            join_table = reflection.options[:join_table]
            candidates = target_class.constantize.reflections.values.select do |r|
              r.macro == :has_and_belongs_to_many && r.options[:join_table] == join_table
            end
            raise "No inverse relations found for #{reflection}" if candidates.empty?
            raise "Multiple opposite relations found for #{reflection}: #{canditates}" if candidates.length > 1
            foreign_name = candidates.first.name.to_s
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
          new_class.send :define_method, :destroy do |*args|
            stmts = []
            object = if self.adsl_ast.expr_has_side_effects?
              var_name = ASTIdent.new(:text => "__delete_#{ self.class.adsl_ast_class_name }_temp_var")
              stmts << ASTExprStmt.new(:expr => ASTAssignment.new(:var_name => var_name.dup, :expr => self.adsl_ast))
              self.class.new :adsl_ast => ASTVariable.new(:var_name => var_name.dup)
            else
              self
            end
            
            refls.each do |refl|
              next unless [:delete, :delete_all, :destroy, :destroy_all].include? refl.options[:dependent]
                
              if refl.options[:dependent] == :destroy or refl.options[:dependent] == :destroy_all
                if refl.through_reflection.nil?
                  stmts += object.send(refl.name).destroy
                else
                  stmts += object.send(refl.through_reflection.name).destroy
                end
              else
                if refl.through_reflection.nil?
                  stmts += object.send(refl.name).delete
                else
                  stmts += object.send(refl.through_reflection.name).delete
                end
              end
            end

            stmts << ASTDeleteObj.new(:objset => object.adsl_ast)

            stmts
          end
          new_class.send(:define_method, :destroy!    ){ |*args| destroy *args }
          new_class.send(:define_method, :destroy_all ){ |*args| destroy *args }

          new_class.send :define_method, :delete do |*args|
            [ASTDeleteObj.new(:objset => adsl_ast)]
          end
          new_class.send(:define_method, :delete!   ){ |*args| delete *args }
          new_class.send(:define_method, :delete_all){ |*args| delete *args }
          new_class.send(:define_method, :clear     ){ |*args| delete *args }
        end

        def generate_class
          @ar_class.class_exec do

            include ADSL::Parser

            attr_accessor :adsl_ast
            attr_accessible :adsl_ast

            def initialize(attributes = {}, options = {})
              attributes = {} if attributes.is_a?(MetaUnknown)
              super({
                :adsl_ast => ASTCreateObjset.new(:class_name => ASTIdent.new(:text => self.class.adsl_ast_class_name))
              }.merge(attributes), options)
            end

            # no-ops
            def save(*args);  end
            def save!(*args); end
            def reorder(*args);   self; end
            def order(*args);     self; end
            def reorder(*args);   self; end
            def includes(*args);  self; end
            def all(*args);       self; end
            def scope_for_create; self; end
            def id;               self; end   # used to allow foreign key assignment

            def count_by_group(*args); MetaUnknown.new; end
            def size;                  MetaUnknown.new; end
            def length;                MetaUnknown.new; end
            def count;                 MetaUnknown.new; end
            def map;                   MetaUnknown.new; end
            def valid?(*args);         MetaUnknown.new; end

            def hash
              @adsl_ast.hash
            end

            def take(*params)
              self.class.new :adsl_ast => ASTOneOf.new(:objset => self.adsl_ast)
            end
            alias_method :take!, :take
            alias_method :first, :take
            alias_method :last,  :take
            alias_method :find,  :take

            def where(*args)
              self.class.new :adsl_ast => ASTSubset.new(:objset => self.adsl_ast)
            end
            alias_method :only,     :where
            alias_method :except,   :where
            alias_method :my,       :where
            alias_method :paginate, :where    # will_paginate
            def merge(other)
              if other.adsl_ast.is_a? ASTAllOf
                self
              elsif self.adsl_ast.is_a? ASTAllOf
                other
              elsif other.is_a? ActiveRecord::Base
                # the scope is on the right hand side; so we can just replace all AllOfs in the right
                # with the left hand side
                self.class.new(:adsl_ast => other.adsl_ast.block_replace{ |node|
                  self.adsl_ast.dup if node.is_a? ASTAllOf
                })
              else
                self
              end
            end

            def apply_finder_options(options)
              options.include?(:conditions) ? self.class.new(:adsl_ast => ASTSubset.new(:objset => self.adsl_ast)) : self
            end

            def empty?
              ASTIsEmpty.new :objset => self.adsl_ast
            end

            def +(other)
              self.class.new :adsl_ast => ASTUnion.new(:objsets => [self.adsl_ast, other.adsl_ast])
            end

            def each(&block)
              instrumenter = ::ADSL::Extract::Instrumenter.get_instance
              var_name = ASTIdent.new(:text => block.parameters.first[1].to_s)
              var = self.class.new(:adsl_ast => ADSL::Parser::ASTVariable.new(:var_name => var_name))

              substmts = instrumenter.abb.in_stmt_frame var, &block

              ASTForEach.new(
                :objset => self.adsl_ast,
                :var_name => var_name.dup,
                :block => ASTBlock.new(:statements => substmts)
              )
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

            def ==(other)
              other = other.adsl_ast if other.respond_to? :adsl_ast
              if other.is_a? ASTNode and other.class.is_objset?
                ASTEqual.new :objsets => [self.adsl_ast, other]
              else
                super
              end
            end

            def !=(other)
              other = other.adsl_ast if other.respond_to? :adsl_ast
              if other.is_a? ASTNode and other.class.is_objset?
                ASTNot.new(:subformula => ASTEqual.new(:objsets => [self.adsl_ast, other]))
              else
                super
              end
            end

            def method_missing(method, *args, &block)
              if without_by = ActiveRecordMetaclassGenerator.remove_by_from_method(method)
                self.send(without_by)
              # maybe this is a scope invocation?
              elsif self.class.respond_to? method
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
              super || ActiveRecordMetaclassGenerator.remove_by_from_method(method) || self.class.respond_to?(method)
            end

            # note that this build method does not apply to objsets
            # acquired using :through associations
            def build(*params)
              return self unless self.adsl_ast.is_a?(ASTMemberAccess)
              self.class.new(:adsl_ast => ASTDereferenceCreate.new(
                :objset => self.adsl_ast.objset,
                :rel_name => self.adsl_ast.member_name
              ))
            end
            alias_method :create, :build
            alias_method :create!, :build
            
            # note that this method does not apply to objsets
            # acquired using :through associations
            # assume that 
            def <<(param)
              return self unless self.adsl_ast.is_a?(ASTMemberAccess)
              return super unless param.respond_to? :adsl_ast
              raise "Invalid type added on dereference: #{param.class.name} to #{self.class.name}" unless param.class <= self.class
              ASTCreateTup.new(
                :objset1 => self.adsl_ast.objset.dup,
                :rel_name => self.adsl_ast.member_name.dup,
                :objset2 => param.adsl_ast.dup
              )
            end
            alias_method :add, :<<


            class << self
              include ADSL::Parser
            
              def ar_class
                superclass
              end

              def adsl_ast_class_name
                ActiveRecordMetaclassGenerator.adsl_ast_class_name(self)
              end

              def all(*params)
                self.new :adsl_ast => ASTAllOf.new(:class_name => ASTIdent.new(:text => adsl_ast_class_name))
              end
              def scope_for_create;  self; end
              def scope_attributes?; false; end
              def scoped; @scoped || all; end
              def scoped=(scoped); @scoped = scoped; end
              alias_method :order,  :all

              # calculations
              def calculate(*args); ::ADSL::Extract::Rails::MetaUnknown.new; end
              alias_method :count,   :calculate
              alias_method :average, :calculate
              alias_method :minimum, :calculate
              alias_method :maximum, :calculate
              alias_method :sum,     :calculate
              alias_method :pluck,   :calculate

              def find(*args)
                self.all.take
              end

              def where(*args)
                self.all.where
              end
              alias_method :only,   :where
              alias_method :except, :where
              alias_method :my,     :where

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
              self_adsl_ast = self.adsl_ast
              target_class = assoc.class_name.constantize
              result = target_class.new :adsl_ast => ASTMemberAccess.new(
                :objset => self_adsl_ast.dup,
                :member_name => ASTIdent.new(:text => assoc.name.to_s)
              )

              if assoc.macro == :has_many
                result.singleton_class.send :define_method, :delete do |*args|
                  # has_many association.delete(ids)
                  object = if args.empty?
                    self
                  elsif args.length == 1
                    self.find
                  else
                    self.where
                  end
                  if [:delete, :delete_all].include? assoc.options[:dependent]
                    object == self ? super() : object.delete
                  elsif [:destroy, :destroy_all].include? assoc.options[:dependent]
                    object.destroy
                  else
                    [ASTDeleteTup.new(
                      :objset1 => self_adsl_ast.dup,
                      :rel_name => ASTIdent.new(:text => assoc.name.to_s),
                      :objset2 => object.adsl_ast
                    )]
                  end
                end
              elsif assoc.macro == :has_and_belongs_to_many
                result.singleton_class.send :define_method, :delete do |*args|
                  object = if args.empty?
                    self
                  elsif args.length == 1
                    self.find
                  else
                    self.where
                  end
                  [ASTDeleteTup.new(
                    :objset1 => self_adsl_ast.dup,
                    :rel_name => ASTIdent.new(:text => assoc.name.to_s),
                    :objset2 => object.adsl_ast
                  )]
                end
              end

              result
            end

            @ar_class.new.replace_method "#{assoc.name}=" do |other|
              ASTMemberSet.new(
                :objset => self.adsl_ast,
                :member_name => ASTIdent.new(:text => assoc.name.to_s),
                :expr => other.adsl_ast
              )
            end

            if assoc.macro == :belongs_to
              @ar_class.class_eval <<-ruby
                alias_method :#{assoc.foreign_key},  :#{assoc.name}
                alias_method :#{assoc.foreign_key}=, :#{assoc.name}=
              ruby
            end
          end
          reflections(:polymorphic => false, :through => true).each do |assoc|
            @ar_class.new.replace_method assoc.name do
              through_assoc = assoc.through_reflection
              source_assoc = assoc.source_reflection

              first_step = self.send through_assoc.name
              result = first_step.send source_assoc.name

              result.singleton_class.class_exec do
                def build(*args)
                  # does not support composite :through associations
                  self.class.new(:adsl_ast => ASTDereferenceCreate.new(
                    :rel_name => self.adsl_ast.member_name,
                    :objset => ASTDereferenceCreate.new(
                      :objset => self.adsl_ast.objset.objset,
                      :rel_name => self.adsl_ast.objset.member_name
                    )
                  ))
                end

                def <<(param)
                  target = param.adsl_ast
                  intermed_deref = self.adsl_ast
                  source_deref = self.adsl_ast.objset
                  ASTCreateTup.new(
                    :objset1 => ASTDereferenceCreate.new(
                      :objset => source_deref.objset,
                      :rel_name => source_deref.member_name,
                    ),
                    :rel_name => intermed_deref.member_name,
                    :objset2 => target.dup
                  )
                end
                alias_method :add, :<<
              end
              result
            end

            @ar_class.new.replace_method "#{assoc.name}=" do |other|
              # delete the join objects originating from this, not invoking callbacks
              # create new ones
              # connect this with all the join objects, and each join object with a corresponding other
              through_assoc = assoc.through_reflection
              source_assoc = assoc.source_reflection
              join_class_name = through_assoc.class_name.constantize.adsl_ast_class_name
              origin_name = ASTIdent.new :text => "#{self.class.name.underscore}__#{through_assoc.name}__origin"
              target_name = ASTIdent.new :text => "#{self.class.name.underscore}__#{through_assoc.name}__target"
              iter_name   = ASTIdent.new :text => "#{self.class.name.underscore}__#{through_assoc.name}__iterator"
              join_name   = ASTIdent.new :text => "#{self.class.name.underscore}__#{through_assoc.name}__join_object"
              [
                ASTExprStmt.new(:expr => ASTAssignment.new(:var_name => origin_name.dup, :expr => self.adsl_ast)),
                ASTExprStmt.new(:expr => ASTAssignment.new(:var_name => target_name.dup, :expr => other.adsl_ast)),
                ASTDeleteObj.new(:objset => ASTMemberAccess.new(
                  :objset => ASTVariable.new(:var_name => origin_name.dup),
                  :member_name => ASTIdent.new(:text => through_assoc.name.to_s)
                )),
                ASTForEach.new(
                  :var_name => iter_name,
                  :objset => ASTVariable.new(:var_name => target_name.dup),
                  :block => ASTBlock.new(:statements => [
                    ASTExprStmt.new(:expr => ASTAssignment.new(
                      :var_name => join_name,
                      :expr => ASTCreateObjset.new(:class_name => ASTIdent.new(:text => join_class_name))
                    )),
                    ASTCreateTup.new(
                      :objset1  => ASTVariable.new(:var_name => origin_name.dup),
                      :rel_name => ASTIdent.new(:text => through_assoc.name.to_s),
                      :objset2  => ASTVariable.new(:var_name => join_name.dup)
                    ),
                    ASTCreateTup.new(
                      :objset1  => ASTVariable.new(:var_name => join_name.dup),
                      :rel_name => ASTIdent.new(:text => source_assoc.name.to_s),
                      :objset2  => ASTVariable.new(:var_name => iter_name.dup)
                    )
                  ])
                )
              ]
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
              :parent_names => adsl_ast_parent_name.nil? ? [] : [adsl_ast_parent_name],
              :members => adsl_ast_relations
            )
          end

          @ar_class
        end

      end

    end
  end
end
