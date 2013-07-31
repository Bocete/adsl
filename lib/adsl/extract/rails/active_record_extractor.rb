require 'ruby_parser'
require 'ruby2ruby'
require 'active_record'
require 'active_support'
require 'set'
require 'adsl/util/general'
require 'adsl/extract/rails/active_record_metaclass_generator'

module ADSL
  module Extract
    module Rails

      class ActiveRecordExtractor
        def initialize 
          @parser = RUBY_VERSION >= '2' ? Ruby19Parser.new : RubyParser.for_current_ruby
          @ruby2ruby = Ruby2Ruby.new
        end

        def extract_static(classes)
          mapping = {}
          classes.each do |ar_klass|
            mapping[ar_klass] = extract_class ar_klass
          end
          mapping
        end

        def extract_class(ar_class)
          generator = ActiveRecordMetaclassGenerator.new ar_class
          generator.generate_class
        end
      end

    end
  end
end
