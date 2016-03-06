require 'adsl/util/test_helper'
require 'adsl/fol/first_order_logic'
require 'adsl/ds/fol_translation/util'

module ADSL::DS::FOLTranslation
  class UtilTest < ActiveSupport::TestCase
    include ADSL::FOL
  
    def test_translation__gen_unique_arg_formula__integer_args
      sort1 = Sort.new :sort1
      sort2 = Sort.new :sort2
      pred = Predicate.new :name, sort1, sort2
  
      a1 = TypedString.new sort1, :a1
      b1 = TypedString.new sort1, :b1
      e1 = TypedString.new sort1, :e1
      a2 = TypedString.new sort2, :a2
      b2 = TypedString.new sort2, :b2
      e2 = TypedString.new sort2, :e2
      
      assert_equal ForAll.new(a1, e2, b1, Implies.new(
        And.new(pred[a1, e2], pred[b1, e2]),
        Equal.new(a1, b1)
      )), Util.gen_formula_for_unique_arg(pred, 0).optimize
      
      assert_equal And.new(
        ForAll.new(a1, e2, b1, Implies.new(
          And.new(pred[a1, e2], pred[b1, e2]),
          Equal.new(a1, b1)
        )),
        ForAll.new([e1, a2, b2], Implies.new(
          And.new(pred[e1, a2], pred[e1, b2]),
          Equal.new(a2, b2)
        ))
      ), Util.gen_formula_for_unique_arg(pred, 0, 1)
    end
  
    def test_translation__gen_unique_arg_formula__range_args
      sort1 = Sort.new :sort1
      sort2 = Sort.new :sort2
      sort3 = Sort.new :sort3
      pred = Predicate.new :name, sort1, sort2, sort3
        
      a1 = TypedString.new sort1, :a1
      b1 = TypedString.new sort1, :b1
      e1 = TypedString.new sort1, :e1
      a2 = TypedString.new sort2, :a2
      b2 = TypedString.new sort2, :b2
      e2 = TypedString.new sort2, :e2
      e3 = TypedString.new sort3, :e3
     
      [[(0..0)], [0, (1..0)]].each do |args|
        assert_equal ForAll.new(a1, e2, e3, b1, Implies.new(
          And.new(pred[a1, e2, e3], pred[b1, e2, e3]),
          Equal.new(a1, b1)
        )), Util.gen_formula_for_unique_arg(pred, *args).optimize
      end
      
      assert_equal And.new(
        ForAll.new([a1, e2, e3, b1], Implies.new(
          And.new(pred[a1, e2, e3], pred[b1, e2, e3]),
          Equal.new(a1, b1)
        )),
        ForAll.new([e1, a2, e3, b2], Implies.new(
          And.new(pred[e1, a2, e3], pred[e1, b2, e3]),
          Equal.new(a2, b2)
        ))
      ), Util.gen_formula_for_unique_arg(pred, 0, (1..1))
  
      assert_equal ForAll.new([a1, a2, e3, b1, b2], Implies.new(
        And.new(pred[a1, a2, e3], pred[b1, b2, e3]),
        PairwiseEqual.new([a1, a2], [b1, b2])
      )), Util.gen_formula_for_unique_arg(pred, (0..1))
  
      assert_equal true, Util.gen_formula_for_unique_arg(pred, (1..0))
    end
  
  end
end
