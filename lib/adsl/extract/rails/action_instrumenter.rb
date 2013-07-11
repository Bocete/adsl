require 'active_support'
require 'adsl/extract/instrumenter'
require 'adsl/extract/sexp_utils'

module Kernel
  def ins_stmt(expr)
    ::ADSL::Extract::Instrumenter.get_instance.action_block.push(expr.adsl_ast) if expr.respond_to?(:adsl_ast)
    expr
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

          # all assignments should assign metavariables
          replace :lasgn do |sexp|
            metavariable_class = ADSL::Extract::Rails::MetaVariable.to_sexp
            sexp[2] = s(:call, metavariable_class, :new, s(:hash, s(:lit, :name), s(:str, sexp[1].to_s), s(:lit, :value), sexp[2]))
            sexp
          end

          # remove respond_to
          replace :call do |sexp|
            sexp[0] == :call && sexp[1].nil? && sexp[2] == :respond_to ? s(:nil) : sexp
          end
          
          # prepend ins_stmt to every statement
          replace :defn do |sexp|
            (3..sexp.length-1).each do |index|
              sexp[index] = s(:call, nil, :ins_stmt, sexp[index])
            end
            sexp
          end
          replace :block do |sexp|
            (1..sexp.length-1).each do |index|
              sexp[index] = s(:call, nil, :ins_stmt, sexp[index])
            end
            sexp
          end
        end

        def should_instrument?(object, method_name)
          object.class.parent_module != ADSL::Extract::Rails && 
            !(method_name.to_sym == :ins_stmt && object.method(method_name).owner == Kernel) && 
            !(method_name.to_sym == :ins_call && object.method(method_name).owner == Kernel) && 
            super
        end
      end
    end
  end
end
