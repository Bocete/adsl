require 'adsl/verification/invariant'
require 'adsl/verification/formula_generators'

module ADSL
  module Extract
    module Rails
      class InvariantExtractor

        include ADSL::Verification
        include FormulaGenerators

        attr_reader :invariants

        def initialize
          @invariants = []
          @builder = nil
          @stack_level = 0
        end

        def invariant(name = nil, builder)
          @invariants << Invariant.new(:description => name, :formula => builder.adsl_ast)
        end

        def load_in_context(path)
          file = File.open path, 'r'
          self.instance_eval file.read
        ensure
          file.close
        end

        def extract(param)
          if param.is_a? Array
            param.each do |path|
              load_in_context path
            end
          else
            self.instance_eval param
          end
          @invariants
        end
      end
    end
  end
end
