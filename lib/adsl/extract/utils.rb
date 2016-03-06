require 'adsl/lang/ast_nodes'

module ADSL
  module Extract
    module Utils
      
      def infer_classname_from_varname(varname)
        varname.to_s.match(/^(\w+?)(?:_*\d+)?$/)[1].camelize
      end
        
      def classname_for_classname(klass)
        klass.is_a?(Module) ? klass.name : klass.to_s.camelize
      end
    end
  end
end
