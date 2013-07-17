require 'active_support'
require 'adsl/parser/ast_nodes'

module ADSL
  module Extract
    module Rails

      class MetaUnknown
        def method_missing(method, *args, &block)
          self
        end

        def adsl_ast
          nil
        end
      end

    end
  end
end
