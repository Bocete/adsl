require 'active_support'
require 'parser/adsl_ast'

module Extract
  module Rails

    class MetaVariable
      attr_accessor :name, :value

      def initialize(attributes = {})
        @name = attributes[:name]
        @value = attributes[:value]
        ::Extract::Instrumenter.get_instance.action_block.push(ADSL::ADSLAssignment.new(
          :var_name => ADSL::ADSLIdent.new(:text => @name),
          :objset => @value.adsl_ast
        )) if @value.respond_to? :adsl_ast
      end

      def adsl_ast
        ::ADSL::ADSLVariable.new :var_name => @name
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
