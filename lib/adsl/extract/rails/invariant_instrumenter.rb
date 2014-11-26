require 'adsl/extract/instrumenter'
require 'adsl/extract/formula_generators'
require 'adsl/extract/rails/active_record_metaclass_generator'

module ADSL
  module Extract
    module Rails
      class InvariantInstrumenter < ADSL::Extract::Instrumenter
        
        def instrument_and_execute_source object, source
          instrumented_source = instrument_string source
          exec_within do
            object.instance_eval instrumented_source
          end
        end

        def initialize(ar_class_names, *params)
          super *params

          # if a block is passed to the invariant call, add that block to the last of the parameters instead
          replace :iter do |sexp|
            next sexp unless (
              sexp[1].sexp_type == :call and
              sexp[1][1].nil? and
              sexp[1][2] == :invariant and
              sexp[1].last.sexp_type == :call
            )

            params_for_invariant = sexp[1][3..-1]
            s(:call, nil, :invariant,
              *params_for_invariant[0..-2],
              s(:iter, params_for_invariant.last, *sexp[2..-1])
            )
          end

          # replace and with self.and etc
          [:and, :or].each do |operand|
            replace operand do |sexp|
              s(:if,
                s(:call, nil, :respond_to?, s(:lit, operand)),
                s(:call, s(:self), operand, *sexp.sexp_body),
                s(operand,                  *sexp.sexp_body)
              )
            end
          end

          # replace not with self.not
          replace :call do |sexp|
            next sexp unless sexp[2] == :!
            s(:if,
              s(:call, nil, :respond_to?, s(:lit, :not)),
              s(:call, s(:self), :not, sexp[1].dup),
              sexp
            )
          end
        end

        def should_instrument?(object, method_name)
          return false unless super

          klass = object.class != Class ? object.class : object
          method = object.method method_name
          
          klass.name.match(/^ADSL::.*$/).nil? && !(method.source_location[0] =~ /.*lib\/adsl\/.*/)
        end

      end
    end
  end
end
