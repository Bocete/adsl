require 'active_support'

module Extract
  module Rails
    class ActionInstrumenter < Extract::Instrumenter

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
          metavariable = s(:colon2, s(:colon2, s(:const, :Extract), :Rails), :MetaVariable)
          sexp[2] = s(:call, metavariable, :new, s(:hash, s(:lit, :name), s(:str, sexp[1].to_s), s(:lit, :value), sexp[2]))
          sexp
        end

        # remove respond_to
        replace :call do |sexp|
          sexp[0] == :call && sexp[1].nil? && sexp[2] == :respond_to ? s(:nil) : sexp
        end
      end
    end
  end
end
