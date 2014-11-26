require 'minitest/unit'

require 'minitest/autorun'
require 'adsl/util/numeric_extensions'
require 'adsl/util/test_helper'

class ADSL::Util::NumericExtensionsTest < MiniTest::Unit::TestCase
  def test_numeric__round?
    assert 3.respond_to? :round?
    assert 3.round?
    assert 0.round?
    assert -1234.round?
    assert_false 3.14.round?
    assert_false (14/17.0).round?
  end
end
