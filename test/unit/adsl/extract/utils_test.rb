require 'adsl/util/test_helper'
require 'adsl/extract/meta'
require 'adsl/extract/utils'

class ADSL::Extract::UtilsTest < ActiveSupport::TestCase
  include ADSL::Extract::Utils

  def setup
    eval <<-ruby
      class ::User; end
      class ::UserAddress; end
    ruby
  end

  def teardown
    unload_class :User, :UserAddress
  end

  def test_infer_classname_from_varname
    assert_equal 'User', infer_classname_from_varname('user')
    assert_equal 'User', infer_classname_from_varname(:user)
    assert_equal 'UserAddress', infer_classname_from_varname('user_address')
    assert_equal 'UserAddress', infer_classname_from_varname(:user_address)

    assert_equal 'User', infer_classname_from_varname('user1')
    assert_equal 'User', infer_classname_from_varname('user_12')
    assert_equal 'UserAddress', infer_classname_from_varname('user_address1')
  end

  def test_classname_for_classname
    assert_equal 'User', classname_for_classname(User)
    assert_equal 'User', classname_for_classname(:user)
    assert_equal 'User', classname_for_classname('user')
    assert_equal 'UserAddress', classname_for_classname('user_address')
    assert_equal 'UserAddress', classname_for_classname(:user_address)
  end
end
