require 'adsl/util/test_helper'
require 'adsl/ds/fol_translation/loop_context/loop_context'
require 'adsl/ds/fol_translation/typed_string'
require 'adsl/ds/fol_translation/ds_extensions'
require 'adsl/ds/data_store_spec'
require 'adsl/fol/first_order_logic'

module ADSL::DS
  module FOLTranslation
    module LoopContext
      class ContextTest < ActiveSupport::TestCase
  
        include ADSL::FOL
      
        def test_context__names_of_context_related_stuff
          t = DSTranslator.new(DSSpec.new)
          sort = t.create_sort :sort
          c1 = FlatLoopContext.new t, 'a', t.current_loop_context, sort
          c1sub = ChainedLoopContext.new t, 'a', c1, sort
          c2 = FlatLoopContext.new t, 'a', t.current_loop_context, sort
      
          assert_equal true, t.current_loop_context.type_pred(:a)
          assert_equal PredicateCall.new(Predicate.new(:a, sort), :name), c1.type_pred(:name)
          assert_equal PredicateCall.new(Predicate.new(:a_2, sort, sort), :p, :name), c1sub.type_pred(:p, :name)
          assert_equal PredicateCall.new(Predicate.new(:a_3, sort), :name), c2.type_pred(:name)
          assert_equal PredicateCall.new(Predicate.new(:a_2_before, sort, sort, sort), :p, :a, :b), c1sub.before_pred[:p, :a, :b]
        end
      
        def test_context__make_ps
          t = DSTranslator.new(DSSpec.new)
          sort = t.create_sort :sort
          sort2 = t.create_sort :sort2
          assert_equal [], t.current_loop_context.make_ps
      
          c = FlatLoopContext.new t, 'a', t.current_loop_context, sort
          assert_equal [TypedString.new(sort, :p1)], c.make_ps
      
          c2 = FlatLoopContext.new t, 'a', c, sort2
          assert_equal [TypedString.new(sort, :p1), TypedString.new(sort2, :p2)], c2.make_ps
          expected = [TypedString.new(sort, :prefix1), TypedString.new(sort2, :prefix2)]
          assert_equal expected, c2.make_ps(:prefix)
        end
      
        def test_context_common__get_common_level
          t = DSTranslator.new(DSSpec.new)
          sort = t.create_sort :sort
          root_c = t.current_loop_context
          c1 = FlatLoopContext.new t, 'a', t.current_loop_context, sort
          c1_sub = FlatLoopContext.new t, 'a', c1, sort
          c1_sub2 = ChainedLoopContext.new t, 'a', c1, sort
          c2 = ChainedLoopContext.new t, 'a', t.current_loop_context, sort
          
          assert_equal root_c, LoopContextCommon.get_common_context(root_c, root_c)
          assert_equal root_c, LoopContextCommon.get_common_context(root_c, c1)
          assert_equal root_c, LoopContextCommon.get_common_context(root_c, c1_sub)
          assert_equal c1, LoopContextCommon.get_common_context(c1, c1)
          assert_equal c1, LoopContextCommon.get_common_context(c1_sub, c1)
          assert_equal c1, LoopContextCommon.get_common_context(c1_sub, c1_sub2)
          assert_equal root_c, LoopContextCommon.get_common_context(c1, c2)
        end
        
        def test_context__order_in_root_context
          # supposed to emulate two statements in the same for loop
          t = DSTranslator.new(DSSpec.new)
          context = t.current_loop_context
      
          assert_equal true, context.before(context, :c, :temp, true)
          assert_equal false, context.before(context, :c, :temp, false)
          assert_equal :asd, context.before(context, :c, :temp, :asd)
        end
      
        def test_context__order_same_lvl_chained
          # supposed to emulate two statements in the same chained foreach loop
          t = DSTranslator.new(DSSpec.new)
          sort = t.create_sort :sort
          c1 = ChainedLoopContext.new t, 'a', t.current_loop_context, sort
      
          a = TypedString.new sort, :a
          b = TypedString.new sort, :b
      
          expected = Or.new(
            c1.before_pred[a, b],
            And[Equal[a, b], :asd]
          )
          assert_equal expected, c1.before(c1, a, b, :asd)
        end
        
        def test_context__order_same_lvl_flat
          # supposed to emulate two statements in the same flat foreach loop
          t = DSTranslator.new(DSSpec.new)
          sort = t.create_sort :sort
          c1 = FlatLoopContext.new t, 'a', t.current_loop_context, sort
      
          expected = And.new(Equal.new(:a, :b), :asd)
          assert_equal expected, c1.before(c1, :a, :b, :asd)
        end
      
        def test_context__order_with_subcontext
          # supposed to emulate a c1 statement followed by a c2 foreach with a stmt inside
          t = DSTranslator.new(DSSpec.new)
          sort = t.create_sort :sort
          c1 = FlatLoopContext.new t, 'a', t.current_loop_context, sort
          c2 = ChainedLoopContext.new t, 'a', c1, sort
      
          a = TypedString.new sort, :a
          b = TypedString.new sort, :b
          parent_a1 = TypedString.new sort, :parent_a1
          parent_b1 = TypedString.new sort, :parent_b1
      
          expected = ForAll.new(parent_b1, Implies.new(
            c2.type_pred(parent_b1, b),
            Or.new(
              false, # c1.before_pred[a, parent_b1],
              And.new(Equal.new(a, parent_b1), :asd)
            )
          )).optimize
          actual = c1.before(c2, a, b, :asd)
          assert_equal expected, actual
          
          expected = ForAll.new(parent_a1, Implies.new(
            c2.type_pred(parent_a1, b),
            Or.new(
              false, # c2.before_pred[parent_a1, b],
              And.new(Equal.new(parent_a1, a), :asd)
            )
          )).optimize
          actual = c2.before(c1, b, a, :asd)
          assert_equal expected, actual
        end
      
        def test_context__listed_in_all_context
          t = DSTranslator.new(DSSpec.new)
          sort = t.create_sort :sort
          c2 = t.create_loop_context 'a', true, t.current_loop_context, sort
          c3 = t.create_loop_context 'a', true, c2, sort
          c4 = t.create_loop_context 'a', true, c2, sort
          assert_equal 4, t.all_loop_contexts.length
          assert_equal Set[t.root_loop_context, c2, c3, c4], Set[*t.all_loop_contexts]
        end
      
        def test_context__statements_in_two_nested_fors
          t = DSTranslator.new(DSSpec.new)
          sort = t.create_sort :sort
          outside_for_context = ChainedLoopContext.new t, 'a', t.current_loop_context, sort
          inside_for_context = ChainedLoopContext.new t, 'a', outside_for_context, sort
          assert_not_equal inside_for_context.before_pred.name, outside_for_context.before_pred.name
      
          parent_a1 = TypedString.new sort, :parent_a1
          parent_b1 = TypedString.new sort, :parent_b1
          a         = TypedString.new sort, :a
          b         = TypedString.new sort, :b
      
          expected = ForAll.new(parent_a1, parent_b1, Implies.new(
            And.new(
              inside_for_context.type_pred(parent_a1, a),
              inside_for_context.type_pred(parent_b1, b)
            ),
            Or.new(
              outside_for_context.before_pred[parent_a1, parent_b1],
              And.new(Equal.new(parent_a1, parent_b1), inside_for_context.before_pred[parent_a1, a, b]),
              And.new(Equal.new(a, b), :asd)
            )
          )).optimize
          actual = inside_for_context.before(inside_for_context, a, b, :asd)
          assert_equal expected, actual
        end
      
      end
    end
  end
end

