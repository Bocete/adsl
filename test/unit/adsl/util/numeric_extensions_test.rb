require 'adsl/util/test_helper'
require 'adsl/util/numeric_extensions'

class ADSL::Util::NumericExtensionsTest < ActiveSupport::TestCase
  def test_numeric__round?
    assert 3.respond_to? :round?
    assert 3.round?
    assert 0.round?
    assert -1234.round?
    assert_false 3.14.round?
    assert_false (14/17.0).round?
  end
end
