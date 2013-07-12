module ADSL
  module Verification
    class Invariant
      attr_accessor :description, :adsl_ast

      def initialize(options = {})
        @description = options[:description]
        @adsl_ast = options[:adsl_ast]
        @adsl_ast = @adsl_ast.adsl_ast if @adsl_ast.respond_to?(:adsl_ast)
      end
    end
  end
end
