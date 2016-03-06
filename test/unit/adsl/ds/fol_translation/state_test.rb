require 'adsl/util/test_helper'
require 'adsl/ds/fol_translation/state/state'
require 'adsl/ds/fol_translation/ds_translator'
require 'adsl/ds/fol_translation/typed_string'

module ADSL::DS::FOLTranslation
  class StateTest < ActiveSupport::TestCase
    def test_sort_difference__plain
      translator = DSTranslator.new(ADSL::DS::DSSpec.new)
  
      state1 = translator.create_state 's1'
      state2 = translator.create_state 's2'
      assert state1.sort_difference(state2).empty?
  
      sort1 = translator.create_sort 'sort1'
      sort2 = translator.create_sort 'sort2'
      typed_string1 = TypedString.new sort1, 'str1'
      typed_string2 = TypedString.new sort2, 'str2'
  
      state1[typed_string1]
      assert_set_equal [sort1], state1.sort_difference(state2)
      assert_set_equal [sort1], state2.sort_difference(state1)
      
      state2[typed_string2]
      assert_set_equal [sort1, sort2], state1.sort_difference(state2)
      assert_set_equal [sort1, sort2], state2.sort_difference(state1)
    end
  
    def test_sort_difference__linked
      translator = DSTranslator.new(ADSL::DS::DSSpec.new)
  
      state1 = translator.create_state 's1'
      state2 = translator.create_state 's2'
      assert state1.sort_difference(state2).empty?
  
      sort1 = translator.create_sort 'sort1'
      sort2 = translator.create_sort 'sort2'
      typed_string1 = TypedString.new sort1, 'str1'
      typed_string2 = TypedString.new sort2, 'str2'
  
      state1[typed_string1]
      state2[typed_string2]
  
      state2.link_to_previous_state state1
      
      assert_set_equal [sort2], state1.sort_difference(state2)
      assert_set_equal [sort2], state2.sort_difference(state1)
    end
  end
end

