require 'adsl/verification/invariant'
require 'adsl/verification/formula_generators'

module ADSL
  module Extract
    module Rails
      class InvariantExtractor

        include ADSL::Verification

        attr_reader :invariants

        def initialize
          @invariants = []
        end

        def description(string)
          @description = string
        end
        alias_method :invariant, :description

        def method_missing(method, *args, &block)
          if FormulaBuilder.method_defined? :method
            fb = FormulaBuilder.new
            fb.send method, *args, &block
            invariant = Invariant.new :description => @description, :adsl_ast => fb.adsl_ast
            invariants << invariant
            @description = nil
          else
            super
          end
        end

        def load_in_context(path)
          file = File.open path, 'r'
          self.instance_eval file.read
        ensure
          file.close
        end
      end
    end
  end
end
