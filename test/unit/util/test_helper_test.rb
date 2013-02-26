require 'test/unit'
require 'util/test_helper'
require 'fol/first_order_logic'

class TestHelperTest < Test::Unit::TestCase
  def test_adsl_assert__plain
    adsl_assert :correct, <<-ADSL
      class Class {}
      action Action() {}
      invariant true
    ADSL
  end

  def test_adsl_assert__custom_conjecture
    adsl_assert :correct, <<-ADSL
      class Class {}
      action Action() {}
      invariant true
    ADSL
    adsl_assert :correct, <<-ADSL, :conjecture => true
      class Class {}
      action Action() {}
    ADSL
    adsl_assert :incorrect, <<-ADSL, :conjecture => false
      class Class {}
      action Action() {}
    ADSL
  end
end
