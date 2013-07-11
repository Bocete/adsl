require 'test/unit'
require 'adsl/util/test_helper'
require 'adsl/extract/rails/active_record_metaclass_generator'

class ADSL::Extract::Rails::RailsInstrumentationTestCase < Test::Unit::TestCase
  def setup
    assert_false class_defined? :ADSLMetaAsd, :ADSLMetaKme, 'Mod::ADSLMetaBlah'
    
    initialize_test_context
  end

  def teardown
    unload_class :ADSLMetaAsd, :ADSLMetaKme, 'Mod::ADSLMetaBlah'

    assert_false self.class.const_defined?(:ADSLMetaBlah) 
    assert_false Mod.const_defined?(:ADSLMetaBlah)

    Asd.delete_all
    Kme.delete_all
    Mod::Blah.delete_all
  end
  
  def ar_class_names
    ['Asd', 'Kme', 'Mod::Blah']
  end

  def ar_classes
    ar_class_names.map(&:constantize)
  end
end
