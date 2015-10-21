require 'adsl/util/test_helper'
require 'adsl/translation/typed_string'
require 'adsl/fol/first_order_logic'

class ADSL::Translation::TypedStringTest < ActiveSupport::TestCase

  def test_arg_order
    assert_raises ArgumentError do
      ADSL::Translation::TypedString.new :sort, :name
    end
    sort = ADSL::FOL::Sort.new :sort
    assert_raises ArgumentError do
      ADSL::Translation::TypedString.new :name, sort
    end
  end

  def test_unroll
    sort = ADSL::FOL::Sort.new :sort
    var = ADSL::Translation::TypedString.new sort, :name
    assert_equal [sort, "name"], var.unroll
  end

end

