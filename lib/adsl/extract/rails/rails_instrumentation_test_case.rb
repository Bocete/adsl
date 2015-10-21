require 'adsl/util/test_helper'
require 'adsl/extract/rails/active_record_metaclass_generator'
require 'adsl/extract/rails/rails_test_helper'

class ADSL::Extract::Rails::RailsInstrumentationTestCase < ActiveSupport::TestCase
  def setup
    [:Asd, :Kme, 'Mod::Blah', :Ability].each do |k|
      raise "#{k} was loaded" if class_defined?(k)
    end
    initialize_test_context
  end

  def teardown
    teardown_test_context
  end

  def initialize_metaclasses
    ADSL::Extract::Rails::ActiveRecordMetaclassGenerator.new(Asd).generate_class
    ADSL::Extract::Rails::ActiveRecordMetaclassGenerator.new(Kme).generate_class
    ADSL::Extract::Rails::ActiveRecordMetaclassGenerator.new(Mod::Blah).generate_class
  end

  def create_rails_extractor(invariant_string = '')
    ADSL::Extract::Rails::RailsExtractor.new :ar_classes => ar_classes, :invariants => invariant_string
  end
  
  def ar_class_names
    default_class_names = ['Asd', 'Kme', 'Mod::Blah']
    default_class_names << 'User' if Object.lookup_const('User')
    default_class_names
  end

  def ar_classes
    ar_class_names.map(&:constantize)
  end
end
