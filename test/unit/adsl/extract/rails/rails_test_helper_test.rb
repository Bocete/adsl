require 'test/unit'
require 'active_record'
require 'ruby_parser'
require 'ruby2ruby'
require 'adsl/util/test_helper'
require 'adsl/extract/rails/rails_test_helper'
require 'adsl/extract/rails/rails_instrumentation_test_case'

class ADSL::Extract::Rails::RailsTestHelperTest < ADSL::Extract::Rails::RailsInstrumentationTestCase
  def test__ar_classes_exist_and_work
    assert self.class.const_defined? :Asd
    assert self.class.const_defined? :Kme
    assert self.class.const_defined? :Mod
    assert Mod.const_defined? :Blah

    a = Asd.new
    a.blahs.build
    a.save!

    assert_equal 1, Asd.all.length
    a_from_db = Asd.all.first
    assert_equal 1, a_from_db.blahs.length
    assert_equal a_from_db, Mod::Blah.all.first.asd
  end
end
