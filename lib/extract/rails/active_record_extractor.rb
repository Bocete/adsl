require 'util/util'
require 'ruby_parser'
require 'ruby2ruby'
require 'extract/rails/active_record_metaclass_generator'
require 'active_record'
require 'active_support'
require 'set'

module Extract
  module Rails

    class ActiveRecordExtractor
      def initialize 
        @parser = RUBY_VERSION >= '2' ? Ruby19Parser.new : RubyParser.for_current_ruby
        @ruby2ruby = Ruby2Ruby.new
      end

      def extract_static(models_dir)
        classes = Dir["#{models_dir}/**/*.rb"].map{ |path| /^#{Regexp.escape models_dir}\/(.*)\.rb$/.match(path)[1].camelize.constantize }
        extract_static_from_classes classes 
      end

      def extract_static_from_classes(classes)
        defined_classes = Set[ActiveRecord::Base]
        mapping = {}
        classes.dup.worklist_each do |ar_klass|
          if defined_classes.include? ar_klass.superclass
            metaclass = extract_class ar_klass
            defined_classes << ar_klass
            mapping[ar_klass] = metaclass
            next nil
          else
            next ar_klass
          end
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
