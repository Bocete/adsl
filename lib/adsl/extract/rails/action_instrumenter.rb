require 'active_support'
require 'active_record'
require 'adsl/extract/instrumenter'
require 'adsl/extract/sexp_utils'
require 'adsl/parser/ast_nodes'

module Kernel
  def ins_stmt(expr)
    adsl_ast = expr
    adsl_ast = expr.adsl_ast if adsl_ast.respond_to? :adsl_ast
    if adsl_ast.is_a? ::ADSL::Parser::ASTNode
      adsl_ast = ADSL::Parser::ASTObjsetStmt.new :objset => adsl_ast unless adsl_ast.class.is_statement?
      ::ADSL::Extract::Instrumenter.get_instance.action_block.push adsl_ast
    end
    expr
  end

  def ins_assignment(outer_binding, name, value)
    if value.is_a? ActiveRecord::Base
      assignment = ::ADSL::Parser::ASTAssignment.new(
        :var_name => ::ADSL::Parser::ASTIdent.new(:text => name),
        :objset => value.adsl_ast
      )
      variable = value.class.new(:adsl_ast =>
        ::ADSL::Parser::ASTVariable.new(:var_name => ::ADSL::Parser::ASTIdent.new(:text => name))
      )
      outer_binding.eval "#{name} = ObjectSpace._id2ref(#{variable.object_id})"
      assignment
    else
      outer_binding.eval "#{name} = ObjectSpace._id2ref(#{value.object_id})"
      value
    end
  end
end

module ADSL
  module Extract
    module Rails
      class ActionInstrumenter < ::ADSL::Extract::Instrumenter

        attr_accessor :action_block

        def initialize(ar_class_names, instrument_domain = Dir.pwd)
          super instrument_domain

          ar_class_names = ar_class_names.map{ |n| n.split('::').last }

          # replace all ActiveRecord classes with their meta-variants
          replace :const do |sexp|
            if ar_class_names.include? sexp[1].to_s
              sexp[1] = ActiveRecordMetaclassGenerator.target_classname(sexp[1].to_s).to_sym
            end
            sexp
          end
          replace :colon2 do |sexp|
            if ar_class_names.include? sexp[2].to_s
              sexp[2] = ActiveRecordMetaclassGenerator.target_classname(sexp[2].to_s).to_sym
            end
            sexp
          end

          # remove respond_to
          replace :call do |sexp|
            sexp == s(:call, nil, :respond_to) ? s(:nil) : sexp
          end
          replace :iter do |sexp|
            sexp[1] == s(:call, nil, :respond_to) ? s(:nil) : sexp
          end
          
          # prepend ins_stmt to every non-return statement
          # include return on the root block (where @stack_depth is 1)
          replace :defn, :defs, :block do |sexp|
            first_stmt_index = case sexp.sexp_type
            when :defn; 3
            when :defs; 4
            when :block; 1
            end
            last_stmt_to_instrument = sexp.length + (@stack_depth == 0 ? -1 : -2)
            (first_stmt_index..last_stmt_to_instrument).each do |index|
              sexp[index] = s(:call, nil, :ins_stmt, sexp[index])
            end
            sexp
          end

          # add explicit returns to the method definition
          replace :defn, :defs do |sexp|
            sexp.last = s(:return, sexp) unless sexp.sexp_type == :return
            sexp
          end
          
          # instrument assignments
          replace :lasgn do |sexp|
            [
              s(:lasgn, sexp[1], s(:nil)),
              s(:call, nil, :ins_assignment, s(:call, nil, :binding), s(:str, sexp[1].to_s), sexp[2])
            ]
          end
        end

        def should_instrument?(object, method_name)
          klass = object.class != Class ? object.class : object
          method = object.method method_name
          
          klass.name.match(/^ADSL::.*$/).nil? &&
            !method.owner.respond_to?(:adsl_ast_class_name) &&
            !method.owner.method_defined?(:adsl_ast_class_name) &&
            method.owner != Kernel &&
            super
        end
      end
    end
  end
end
