require 'active_support'
require 'adsl/parser/ast_nodes'

class NilClass
  def adsl_ast
    ::ADSL::Parser::ASTEmptyObjset.new
  end
end

module ADSL
  module Extract
    module Rails

      class MetaUnknown
        attr_reader :label

        def initialize(label = nil)
          @label = label
        end

        def method_missing(method, *args, &block)
          self
        end

        def respond_to?(method_name, *args, &block)
          return true unless method_name == :adsl_ast
        end

        def to_s
          self.class.name
        end

        def present?
          true
        end

        def adsl_ast
          nil
        end
      end

      class PartiallyUnknownHash < MetaUnknown
        def initialize(options = {})
          @options = options
        end

        def [](arg)
          @options[arg] || MetaUnknown.new(arg)
        end

        def []=(key, val)
          @options[key] = val
        end

        def method_missing(method, *args, &block)
          return @options[method] if @options.include? method
          if method.to_s =~ /^.*=$/
            short_method = method.to_s[0..-2].to_sym
            return @options[short_method] if @options.include? short_method
          end
          super
        end
      end

    end
  end
end
