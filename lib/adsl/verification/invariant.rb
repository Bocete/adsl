require 'adsl/parser/ast_nodes'

module ADSL
  module Verification
    class Invariant
      attr_accessor :description, :formula

      def initialize(options = {})
        @description = options[:description]
        @formula = options[:formula]
        @formula = @formula.adsl_ast if @formula.respond_to?(:adsl_ast)
      end

      def adsl_ast
        ADSL::Parser::ASTInvariant.new :name => ADSL::Parser::ASTIdent.new(:text => @description), :formula => @formula
      end
    end
  end
end
