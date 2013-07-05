require 'active_support'

module Extract
  module Rails

    class MetaVariable
      attr_accessor :name, :value

      def initialize(attributes = {})
        @name = attributes[:name]
        @value = attributes[:value]
      end

      def adsl_ast
        ADSLVariable :var_name => @name
      end

      def method_missing(method, *args, &block)
        @value.send method, *args, &block
      rescue Exception => e
        raise e.class, e.message + " with value #{@value}", e.backtrace
      end

      def respond_to?(met, include_all = false)
        super(met, include_all) || @value.respond_to?(met, include_all)
      rescue Exception => e
        raise e.class, e.message + " with value #{@value}", e.backtrace
      end

      def method(met)
        @value.respond_to?(met) ? @value.method(met) : super(met)
      rescue Exception => e
        raise e.class, e.message + " with value #{@value}", e.backtrace
      end
      
      def instance_method(met)
        @value.instance_method(met)
      rescue Exception => e
        raise e.class, e.message + " with value #{@value}", e.backtrace
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
