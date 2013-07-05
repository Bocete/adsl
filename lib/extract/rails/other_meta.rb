require 'active_support'

module Extract
  module Rails

    class MetaVariable
      attr_accessor :name, :value

      def initialize(attributes = {})
        name = attributes[:name]
        value = attributes[:value]
      end

      def adsl_ast
        ADSLVariable :var_name => @name
      end

      def method_missing(method, *args, &block)
        value.call method, *args, &block
      end

      def respond_to?(met)
        super(met) || value.respond_to?(met)
      end

      def method(met)
        super(met) || value.method(met)
      end
    end

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
