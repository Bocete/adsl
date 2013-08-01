require 'adsl/verification/invariant'
require 'adsl/verification/formula_generators'
require 'adsl/extract/rails/invariant_instrumenter'

module ADSL
  module Extract
    module Rails
      class InvariantExtractor

        include ADSL::Verification
        include ADSL::Verification::FormulaGenerators

        attr_reader :invariants

        def initialize(ar_class_names)
          @ar_class_names = ar_class_names
          @invariants = []
          @builder = nil
          @stack_level = 0
        end

        def invariant(name = nil, builder)
          @invariants << Invariant.new(:description => name, :formula => builder.adsl_ast)
        end

        def load_in_context(path)
          file = File.open path, 'r'
          ADSL::Extract::Rails::InvariantInstrumenter.new(@ar_class_names).instrument_and_execute_source self, file.read
        ensure
          file.close
        end

        def extract(param)
          if param.is_a? Array
            param.each do |path|
              load_in_context path
            end
          else
            ADSL::Extract::Rails::InvariantInstrumenter.new(@ar_class_names).instrument_and_execute_source self, param
          end
          @invariants
        end
      end
    end
  end
end
