require 'adsl/lang/ast_nodes'

module ADSL
  module Extract
    class Invariant
      attr_accessor :description, :formula

      def initialize(options = {})
        @description = options[:description]
        @formula = options[:formula]
        @formula = @formula.adsl_ast if @formula.respond_to?(:adsl_ast)
      end

      def adsl_ast
        ADSL::Lang::ASTInvariant.new :name => ADSL::Lang::ASTIdent[@description], :formula => @formula
      end
    end
  end
end
