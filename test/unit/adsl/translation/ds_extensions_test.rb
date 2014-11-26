require 'adsl/translation/ds_extensions'
require 'adsl/translation/ds_translator'
require 'adsl/ds/data_store_spec'
require 'adsl/ds/type_sig'
require 'adsl/fol/first_order_logic'
require 'minitest/unit'

require 'minitest/autorun'
require 'pp'

class ADSL::Translation::TranslationDSExtensionsTest < MiniTest::Unit::TestCase
  include ADSL::FOL

  def setup
    @t = ADSL::Translation::DSTranslator.new
    @parent  = ADSL::DS::DSClass.new :name => 'Parent'
    @child1  = ADSL::DS::DSClass.new :name => 'Child1', :parents => [@parent]
    @child2  = ADSL::DS::DSClass.new :name => 'Child2', :parents => [@parent]
    @diamond = ADSL::DS::DSClass.new :name => 'Diamond', :parents => [@child1, @child2]

    [@parent, @child1, @diamond, @child2].each do |c|
      c.translate @t
    end
  end
  
  def test_class__predicates_set
    assert_equal 'ParentSort', @parent.to_sort.name
    assert_equal @parent.to_sort, @child1.to_sort
    assert_equal @parent.to_sort, @child2.to_sort
    assert_equal @parent.to_sort, @diamond.to_sort

    assert_equal PredicateCall.new(@parent.type_pred, :a), @parent[:a]
    assert_not_equal @parent_type_pred, @parent.to_sort
    assert_equal PredicateCall.new(@child1.type_pred, :a), @child1[:a]
    assert_equal PredicateCall.new(@child2.type_pred, :a), @child2[:a]
    assert_equal PredicateCall.new(@diamond.type_pred, :a), @diamond[:a]
  end

  def test_type_sig__bracket_operator
    assert_equal PredicateCall.new(@parent.type_pred, :a), @parent.to_sig[:a]
    assert_equal PredicateCall.new(@child1.type_pred, :a), @child1.to_sig[:a]
    assert_equal PredicateCall.new(@child2.type_pred, :a), @child2.to_sig[:a]
    assert_equal PredicateCall.new(@diamond.type_pred, :a), @diamond.to_sig[:a]
    
    p_c = ADSL::DS::TypeSig::ObjsetType.new(@parent, @child1)
    assert_equal PredicateCall.new(@child1.type_pred, :a), p_c[:a]
  
    c1_c2 = ADSL::DS::TypeSig::ObjsetType.new(@child1, @child2)
    assert_equal(
      And[PredicateCall[@child1.type_pred, :a], PredicateCall[@child2.type_pred, :a]],
      c1_c2[:a]
    )
  end

end

