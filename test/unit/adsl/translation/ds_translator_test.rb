require 'adsl/util/test_helper'
require 'adsl/translation/ds_translator'
require 'adsl/translation/typed_string'
require 'adsl/translation/ds_extensions'
require 'adsl/ds/data_store_spec'
require 'adsl/fol/first_order_logic'

class ADSL::Translation::DSTranslatorTest < ActiveSupport::TestCase

  include ADSL::FOL

  def test_translation__unique_predicate_names
    t = ADSL::Translation::DSTranslator.new(ADSL::DS::DSSpec.new)
    sort1 = t.create_sort :sort
    sort2 = t.create_sort :sort
    assert_equal "sort",   sort1.name
    assert_equal "sort_2", sort2.name

    var_a = ADSL::Translation::TypedString.new sort1, :a
    var_a2 = ADSL::Translation::TypedString.new sort2, :a2
    state1 = t.create_state :state
    state2 = t.create_state :state

    assert_equal "state_sort",  state1[var_a].predicate.name
    assert_equal "state_sort_2", state1[var_a2].predicate.name
    assert_equal "state_2_sort",  state2[var_a].predicate.name
    assert_equal "state_2_sort_2", state2[var_a2].predicate.name

    function1 = t.create_function sort1, :name, sort1
    function2 = t.create_function sort2, :name, sort1, sort2
    assert_equal "name", function1.name
    assert_equal "name_2", function2.name
    assert_equal "something_with_prefix", t.create_predicate("something_with_prefix", sort1).name
    assert_equal "prefix", t.create_predicate("prefix", sort1).name
    assert_equal "prefix_2_asd", t.create_predicate("prefix_2_asd", sort1).name

    (1..5).each do |i|
      c = t.create_predicate "context_1", sort1
      assert_equal "context_#{i}", c.name
    end
  end

  def test_translation__reserve
    t = ADSL::Translation::DSTranslator.new(ADSL::DS::DSSpec.new)
    sort1 = t.create_sort :sort1
    sort2 = t.create_sort :sort2
    t.reserve sort1, :o do |o|
      assert_equal "o", o.to_s
      assert_equal sort1, o.to_sort
    end
    t.reserve do |*a|
      assert_equal 0, a.length
    end
    t.reserve [sort1, :a, sort2, :b, sort1, :c] do |*a|
      assert_equal 1, a.length
      assert_equal 3, a[0].length
      assert_equal "a", a[0][0].to_s
      assert_equal "b", a[0][1].to_s
      assert_equal "c", a[0][2].to_s
      assert_equal sort1, a[0][0].to_sort
      assert_equal sort2, a[0][1].to_sort
      assert_equal sort1, a[0][2].to_sort
    end
    t.reserve sort1, :o do |o1|
      t.reserve sort2, :o, sort1, :a do |o2, a|
        assert_equal "o", o1.to_s
        assert_equal "o_2", o2.to_s
        assert_equal "a", a.to_s
	assert_equal sort1, o1.to_sort
	assert_equal sort2, o2.to_sort
	assert_equal sort1, a.to_sort
      end
      t.reserve [sort1, :o, sort2, :o], sort2, :o do |os, o4|
        assert_equal 2, os.length
        o2 = os[0]
        o3 = os[1]
        assert_equal "o", o1.to_s
	assert_equal "o_2", o2.to_s
	assert_equal "o_3", o3.to_s
	assert_equal "o_4", o4.to_s
	assert_equal sort1, o1.to_sort
	assert_equal sort1, o2.to_sort
	assert_equal sort2, o3.to_sort
	assert_equal sort2, o4.to_sort
      end
    end
  end

  def test_translation__quantification
    t = ADSL::Translation::DSTranslator.new(ADSL::DS::DSSpec.new)
    
    sort1 = ADSL::FOL::Sort.new 'sort1'
    sort2 = ADSL::FOL::Sort.new 'sort2'
    pred1 = ADSL::FOL::Predicate.new 'pred1', sort1
    pred2 = ADSL::FOL::Predicate.new 'pred2', sort2
    predboth = ADSL::FOL::Predicate.new 'both', sort1, sort2

    [:for_all, :exists].each do |q|
      assert_raises ArgumentError do
        t.send q, :a, :b do |a, b|
          true
        end
      end
      
      assert_raises ArgumentError do
        t.send q, sort1, :a, :b do |a, b|
          true
        end
      end

      assert_nothing_raised do
        f = t.send q, sort1, :a do |*args|
          assert_equal 1, args.length
          a = args.first

          assert_equal ADSL::Translation::TypedString, a.class
          assert_equal 'a', a.name
          assert_equal sort1, a.sort
          pred1[a]
        end
        assert_equal pred1, f.formula.predicate
      end
      
      assert_nothing_raised do
        f = t.send q, sort1, :a, sort2, :b do |*args|
          assert_equal 2, args.length
          a = args.first
          b = args.last

          assert a.is_a?(ADSL::Translation::TypedString)
          assert_equal 'a', a.name
          assert_equal sort1, a.sort
          
          assert b.is_a?(ADSL::Translation::TypedString)
          assert_equal 'b', b.name
          assert_equal sort2, b.sort
          
          predboth[a, b]
        end
        assert_equal predboth, f.formula.predicate
      end
      
      assert_nothing_raised do
        f = t.send q, [sort1, :a, sort2, :a] do |*args|
          assert_equal 1, args.length
          vars = args.first

          assert_equal 2, vars.length
          a1 = vars[0]
          a2 = vars[1]

          assert a1.is_a?(ADSL::Translation::TypedString)
          assert_equal 'a', a1.name
          assert_equal sort1, a1.sort
          
          assert a2.is_a?(ADSL::Translation::TypedString)
          assert_equal 'a_2', a2.name
          assert_equal sort2, a2.sort
          
          predboth[a1, a2]
        end
        assert_equal predboth, f.formula.predicate
      end
      
      assert_nothing_raised do
        f = t.send q, [sort1, :a, sort2, :a] do |*args|
          assert_equal 1, args.length
          vars = args.first

          assert_equal 2, vars.length
          a1 = vars[0]
          a2 = vars[1]

          assert a1.is_a?(ADSL::Translation::TypedString)
          assert_equal 'a', a1.name
          assert_equal sort1, a1.sort
          
          assert a2.is_a?(ADSL::Translation::TypedString)
          assert_equal 'a_2', a2.name
          assert_equal sort2, a2.sort
          
          predboth[a1, a2]
        end
        assert_equal predboth, f.formula.predicate
      end
    end
  end

  def test_translation__prepare_sorts
    translation = ADSL::Translation::DSTranslator.new(ADSL::DS::DSSpec.new)
    klass1 = ADSL::DS::DSClass.new :name => 'name', :parents => [], :members => []
    klass2 = ADSL::DS::DSClass.new :name => 'name', :parents => [], :members => []

    klass1.translate translation
    klass2.translate translation

    assert_equal 'nameSort', klass1.to_sort.name
    assert_equal 'nameSort_2', klass2.to_sort.name
  end

  def test_translation__pre_post_create_objs
    translation = ADSL::Translation::DSTranslator.new(ADSL::DS::DSSpec.new)
    a_klass = ADSL::DS::DSClass.new(:name => "a", :parents => [], :members => [])
    a_stmt = ADSL::DS::DSCreateObj.new(:klass => a_klass)
    b_klass = ADSL::DS::DSClass.new(:name => "b", :parents => [], :members => [])
    b_stmt = ADSL::DS::DSCreateObj.new(:klass => b_klass)
    block = ADSL::DS::DSBlock.new(:statements => [a_stmt, b_stmt])
   
    a_klass.translate translation
    b_klass.translate translation
    translation.state = translation.create_state :initial
    block.prepare translation
    
    assert_equal [a_klass, b_klass], translation.create_obj_stmts.keys.sort_by{ |a| a.name }
    assert_equal [a_stmt], translation.create_obj_stmts[a_klass]
    assert_equal [b_stmt], translation.create_obj_stmts[b_klass]
  end

  def test__sort_setup
    t = ADSL::Translation::DSTranslator.new(ADSL::DS::DSSpec.new)
    parent = ADSL::DS::DSClass.new :name => 'parent'
    child1 = ADSL::DS::DSClass.new :name => 'child1', :parents => [parent]
    child2 = ADSL::DS::DSClass.new :name => 'child2', :parents => [parent]
    diamond = ADSL::DS::DSClass.new :name => 'diamond', :parents => [child1, child2]
    parent2 = ADSL::DS::DSClass.new :name => 'parent2'
    subparent2 = ADSL::DS::DSClass.new :name => 'subparent2', :parents => [parent2]
    [parent, child1, child2, diamond, parent2, subparent2].each do |klass|
      klass.translate t
    end

    parent_sort = parent.to_sort
    [parent, child1, child2, diamond].each do |klass|
      assert_equal parent_sort, klass.to_sort
    end

    assert_equal 4, [parent, child1, child2, diamond].map(&:type_pred).uniq.length
  end

  def test__type_sig
    t = ADSL::Translation::DSTranslator.new(ADSL::DS::DSSpec.new)
    parent = ADSL::DS::DSClass.new :name => 'parent'
    child1 = ADSL::DS::DSClass.new :name => 'child1', :parents => [parent]
    child2 = ADSL::DS::DSClass.new :name => 'child2', :parents => [parent]
    diamond = ADSL::DS::DSClass.new :name => 'diamond', :parents => [child1, child2]
    [parent, child1, child2, diamond].each do |klass|
      klass.translate t
    end

    assert_equal ADSL::FOL::PredicateCall.new(parent.type_pred, :a), parent[:a]
    assert_equal ADSL::FOL::PredicateCall.new(diamond.type_pred, :a), diamond[:a]
    both_sig = ADSL::DS::TypeSig::ObjsetType.new child1, child2
    assert_equal(
      ADSL::FOL::And.new(
        ADSL::FOL::PredicateCall.new(child1.type_pred, :a),
        ADSL::FOL::PredicateCall.new(child2.type_pred, :a)
      ),
      both_sig[:a]
    )
  end
end

