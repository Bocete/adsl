require 'adsl/translation/state'
require 'adsl/translation/ds_translator'
require 'adsl/translation/typed_string'
require 'minitest/unit'

require 'minitest/autorun'
require 'adsl/util/test_helper'

class ADSL::Translation::StateTest < MiniTest::Unit::TestCase
  def test_sort_difference__plain
    translator = ADSL::Translation::DSTranslator.new

    state1 = translator.create_state 's1'
    state2 = translator.create_state 's2'
    assert state1.sort_difference(state2).empty?

    sort1 = translator.create_sort 'sort1'
    sort2 = translator.create_sort 'sort2'
    typed_string1 = ADSL::Translation::TypedString.new sort1, 'str1'
    typed_string2 = ADSL::Translation::TypedString.new sort2, 'str2'

    state1[typed_string1]
    assert_set_equal [sort1], state1.sort_difference(state2)
    assert_set_equal [sort1], state2.sort_difference(state1)
    
    state2[typed_string2]
    assert_set_equal [sort1, sort2], state1.sort_difference(state2)
    assert_set_equal [sort1, sort2], state2.sort_difference(state1)
  end

  def test_sort_difference__linked
    translator = ADSL::Translation::DSTranslator.new

    state1 = translator.create_state 's1'
    state2 = translator.create_state 's2'
    assert state1.sort_difference(state2).empty?

    sort1 = translator.create_sort 'sort1'
    sort2 = translator.create_sort 'sort2'
    typed_string1 = ADSL::Translation::TypedString.new sort1, 'str1'
    typed_string2 = ADSL::Translation::TypedString.new sort2, 'str2'

    state1[typed_string1]
    state2[typed_string2]

    state2.link_to_previous_state state1
    
    assert_set_equal [sort2], state1.sort_difference(state2)
    assert_set_equal [sort2], state2.sort_difference(state1)
  end
end
