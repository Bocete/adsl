require 'adsl/parser/ast_nodes'

module ADSL
  module Verification
    module Utils

      def t(text)
        ADSL::Parser::ASTIdent.new :text => text.to_s
      end
      
      def infer_classname_from_varname(varname)
        varname.to_s.match(/^(\w+?)(?:_*\d+)?$/)[1].camelize
      end
        
      def classname_for_classname(klass)
        klass.is_a?(Module) ? klass.name : klass.to_s.camelize
      end
    end
  end
end
