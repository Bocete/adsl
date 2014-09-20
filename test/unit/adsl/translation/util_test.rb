require 'test/unit'
require 'pp'
require 'adsl/fol/first_order_logic'
require 'adsl/translation/util'

class ADSL::Translation::UtilTest < Test::Unit::TestCase

  def test_translation__gen_unique_arg_formula__integer_args
    sort1 = ADSL::FOL::Sort.new :sort1
    sort2 = ADSL::FOL::Sort.new :sort2
    pred = ADSL::FOL::Predicate.new :name, sort1, sort2

    a1 = ADSL::Translation::TypedString.new sort1, :a1
    b1 = ADSL::Translation::TypedString.new sort1, :b1
    e1 = ADSL::Translation::TypedString.new sort1, :e1
    a2 = ADSL::Translation::TypedString.new sort2, :a2
    b2 = ADSL::Translation::TypedString.new sort2, :b2
    e2 = ADSL::Translation::TypedString.new sort2, :e2
    
    assert_equal ADSL::FOL::ForAll.new(a1, e2, b1, ADSL::FOL::Implies.new(
      ADSL::FOL::And.new(pred[a1, e2], pred[b1, e2]),
      ADSL::FOL::Equal.new(a1, b1)
    )), ADSL::Translation::Util.gen_formula_for_unique_arg(pred, 0).optimize
    
    assert_equal ADSL::FOL::And.new(
      ADSL::FOL::ForAll.new(a1, e2, b1, ADSL::FOL::Implies.new(
        ADSL::FOL::And.new(pred[a1, e2], pred[b1, e2]),
        ADSL::FOL::Equal.new(a1, b1)
      )),
      ADSL::FOL::ForAll.new([e1, a2, b2], ADSL::FOL::Implies.new(
        ADSL::FOL::And.new(pred[e1, a2], pred[e1, b2]),
        ADSL::FOL::Equal.new(a2, b2)
      ))
    ), ADSL::Translation::Util.gen_formula_for_unique_arg(pred, 0, 1)
  end

  def test_translation__gen_unique_arg_formula__range_args
    sort1 = ADSL::FOL::Sort.new :sort1
    sort2 = ADSL::FOL::Sort.new :sort2
    sort3 = ADSL::FOL::Sort.new :sort3
    pred = ADSL::FOL::Predicate.new :name, sort1, sort2, sort3
      
    a1 = ADSL::Translation::TypedString.new sort1, :a1
    b1 = ADSL::Translation::TypedString.new sort1, :b1
    e1 = ADSL::Translation::TypedString.new sort1, :e1
    a2 = ADSL::Translation::TypedString.new sort2, :a2
    b2 = ADSL::Translation::TypedString.new sort2, :b2
    e2 = ADSL::Translation::TypedString.new sort2, :e2
    e3 = ADSL::Translation::TypedString.new sort3, :e3
   
    [[(0..0)], [0, (1..0)]].each do |args|
      assert_equal ADSL::FOL::ForAll.new(a1, e2, e3, b1, ADSL::FOL::Implies.new(
        ADSL::FOL::And.new(pred[a1, e2, e3], pred[b1, e2, e3]),
        ADSL::FOL::Equal.new(a1, b1)
      )), ADSL::Translation::Util.gen_formula_for_unique_arg(pred, *args).optimize
    end
    
    assert_equal ADSL::FOL::And.new(
      ADSL::FOL::ForAll.new([a1, e2, e3, b1], ADSL::FOL::Implies.new(
        ADSL::FOL::And.new(pred[a1, e2, e3], pred[b1, e2, e3]),
        ADSL::FOL::Equal.new(a1, b1)
      )),
      ADSL::FOL::ForAll.new([e1, a2, e3, b2], ADSL::FOL::Implies.new(
        ADSL::FOL::And.new(pred[e1, a2, e3], pred[e1, b2, e3]),
        ADSL::FOL::Equal.new(a2, b2)
      ))
    ), ADSL::Translation::Util.gen_formula_for_unique_arg(pred, 0, (1..1))

    assert_equal ADSL::FOL::ForAll.new([a1, a2, e3, b1, b2], ADSL::FOL::Implies.new(
      ADSL::FOL::And.new(pred[a1, a2, e3], pred[b1, b2, e3]),
      ADSL::FOL::PairwiseEqual.new([a1, a2], [b1, b2])
    )), ADSL::Translation::Util.gen_formula_for_unique_arg(pred, (0..1))

    assert_equal true, ADSL::Translation::Util.gen_formula_for_unique_arg(pred, (1..0))
  end

end

