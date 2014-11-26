module ADSL
  module Extract
    class InstrumentationFilter
      
      def initialize(options = {})
        options.keys.each do |key|
          options[key] = options[key].to_s if options[key].is_a? Symbol
        end
        @options = options
      end

      def applies_to?(object, method_name)
        unless @options[:method_name].nil?
          return false unless @options[:method_name] === method_name.to_s
        end
        unless @options[:method_owner].nil?
          return false if object.is_a?(Numeric) or object.is_a?(Symbol)
          method = object.singleton_class.instance_method method_name
          return false unless method.owner == @options[:method_owner]
        end
        unless @options[:if].nil?
          subcondition = InstrumentationFilter.new(@options[:if])
          return false if subcondition.applies_to? object, method_name
        end
        unless @options[:unless].nil?
          subcondition = InstrumentationFilter.new(@options[:unless])
          return false unless subcondition.applies_to? object, method_name
        end
        true
      end

      def allow_instrumentation?(object, method_name)
        !applies_to? object, method_name
      end

    end

    module InstrumentationFilterGenerators
      def blacklist(method_name = nil, options = {})
        options[:method_name] = method_name unless method_name.nil?
        @instrumentation_filters ||= []
        @instrumentation_filters << InstrumentationFilter.new(options)
      end

      def instrumentation_filters
        @instrumentation_filters || []
      end
    end
  end
end
