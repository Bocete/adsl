require 'adsl/spass/spass_translator'
require 'adsl/ds/data_store_spec'
require 'adsl/fol/first_order_logic'
require 'test/unit'
require 'pp'

class ADSL::Spass::SpassTranslatorTest < Test::Unit::TestCase

  def test_predicate__index_to_string
    p = ADSL::Spass::SpassTranslator::Predicate.new :pred_name, 2
    assert_equal 'pred_name(a, b)', p[:a, :b]
    assert_raise ArgumentError do
      p[:a]
    end
  end

  def test_translation__unique_predicate_names
    t = ADSL::Spass::SpassTranslator::Translation.new
    state1 = t.create_state :name
    state2 = t.create_state :name
    assert_equal "name", state1.name
    assert_equal "name_2", state2.name
    function1 = t.create_function :name, 1
    function2 = t.create_function :name, 2
    assert_equal "name_3", function1.name
    assert_equal "name_4", function2.name
    assert_equal "something_with_prefix", t.create_predicate("something_with_prefix", 2).name
    assert_equal "prefix", t.create_predicate("prefix", 2).name
    assert_equal "prefix_2_asd", t.create_predicate("prefix_2_asd", 2).name

    (1..5).each do |i|
      c = t.create_predicate "context_1", 1
      assert_equal "context_#{i}", c.name
    end
  end

  def test_translation__reserve_names
    t = ADSL::Spass::SpassTranslator::Translation.new
    t.reserve_names :o do |o|
      assert_equal :o, o
    end
    t.reserve_names do |*a|
      assert_equal 0, a.length
    end
    t.reserve_names [:a, :b, :c] do |*a|
      assert_equal 1, a.length
      assert_equal 3, a[0].length
    end
    t.reserve_names :o do |o1|
      t.reserve_names :o, :a do |o2, a|
        assert_equal :o, o1
        assert_equal :o_2, o2
        assert_equal :a, a
      end
      t.reserve_names [:o, :o], :o do |os, o4|
        o2 = os[0]
        o3 = os[1]
        assert_equal :o, o1
        assert_equal :o_2, o2
        assert_equal :o_3, o3
        assert_equal :o_4, o4
      end
    end
  end

  def test_translation__gen_unique_arg_formula__integer_args
    t = ADSL::Spass::SpassTranslator::Translation.new
    pred = ADSL::Spass::SpassTranslator::Predicate.new :name, 2
    
    assert_equal ADSL::FOL::ForAll.new(:a1, :e2, :b1, ADSL::FOL::Implies.new(
      ADSL::FOL::And.new(pred[:a1, :e2], pred[:b1, :e2]),
      ADSL::FOL::Equal.new(:a1, :b1)
    )).resolve_spass, t.gen_formula_for_unique_arg(pred, 0).resolve_spass
    
    assert_equal ADSL::FOL::And.new(
      ADSL::FOL::ForAll.new(:a1, :e2, :b1, ADSL::FOL::Implies.new(
        ADSL::FOL::And.new(pred[:a1, :e2], pred[:b1, :e2]),
        ADSL::FOL::Equal.new(:a1, :b1)
      )),
      ADSL::FOL::ForAll.new(:e1, :a2, :b2, ADSL::FOL::Implies.new(
        ADSL::FOL::And.new(pred[:e1, :a2], pred[:e1, :b2]),
        ADSL::FOL::Equal.new(:a2, :b2)
      ))
    ).resolve_spass, t.gen_formula_for_unique_arg(pred, 0, 1).resolve_spass
  end

  def test_translation__gen_unique_arg_formula__range_args
    t = ADSL::Spass::SpassTranslator::Translation.new
    pred = ADSL::Spass::SpassTranslator::Predicate.new :name, 3
   
    [[(0..0)], [0, (1..0)]].each do |args|
      assert_equal ADSL::FOL::ForAll.new(:a1, :e2, :e3, :b1, ADSL::FOL::Implies.new(
        ADSL::FOL::And.new(pred[:a1, :e2, :e3], pred[:b1, :e2, :e3]),
        ADSL::FOL::Equal.new(:a1, :b1)
      )).resolve_spass, t.gen_formula_for_unique_arg(pred, *args).resolve_spass
    end
    
    assert_equal ADSL::FOL::And.new(
      ADSL::FOL::ForAll.new(:a1, :e2, :e3, :b1, ADSL::FOL::Implies.new(
        ADSL::FOL::And.new(pred[:a1, :e2, :e3], pred[:b1, :e2, :e3]),
        ADSL::FOL::Equal.new(:a1, :b1)
      )),
      ADSL::FOL::ForAll.new(:e1, :a2, :e3, :b2, ADSL::FOL::Implies.new(
        ADSL::FOL::And.new(pred[:e1, :a2, :e3], pred[:e1, :b2, :e3]),
        ADSL::FOL::Equal.new(:a2, :b2)
      ))
    ).resolve_spass, t.gen_formula_for_unique_arg(pred, 0, (1..1)).resolve_spass

    assert_equal ADSL::FOL::ForAll.new(:a1, :a2, :e3, :b1, :b2, ADSL::FOL::Implies.new(
      ADSL::FOL::And.new(pred[:a1, :a2, :e3], pred[:b1, :b2, :e3]),
      ADSL::FOL::PairwiseEqual.new([:a1, :a2], [:b1, :b2])
    )).resolve_spass, t.gen_formula_for_unique_arg(pred, (0..1)).resolve_spass

    t.push_formula_frame
    assert_equal 'true', t.gen_formula_for_unique_arg(pred, (1..0)).resolve_spass
    assert t.pop_formula_frame.empty?
  end
  
  def test_context__names_of_context_related_stuff
    t = ADSL::Spass::SpassTranslator::Translation.new
    c1 = ADSL::Spass::SpassTranslator::FlatContext.new t, 'a', t.context
    c1sub = ADSL::Spass::SpassTranslator::ChainedContext.new t, 'a', c1
    c2 = ADSL::Spass::SpassTranslator::FlatContext.new t, 'a', t.context

    assert_equal "true", t.context.type_pred(:a)
    assert_equal "a(a)", c1.type_pred(:a)
    assert_equal "a_2(p, a)", c1sub.type_pred(:p, :a)
    assert_equal "a_3(a)", c2.type_pred(:a)
    assert_equal "a_2_before(p, a, b)", c1sub.before_pred[:p, :a, :b]
  end

  def test_context__p_names
    t = ADSL::Spass::SpassTranslator::Translation.new
    assert_equal [], t.context.p_names

    c = ADSL::Spass::SpassTranslator::FlatContext.new t, 'a', t.context
    assert_equal [:p1], c.p_names

    c2 = ADSL::Spass::SpassTranslator::FlatContext.new t, 'a', c
    assert_equal [:p1, :p2], c2.p_names
    assert_equal [:p1], c2.p_names(1)
    assert_equal [:p1, :p2, :p3], c.p_names(3)
  end

  def test_context_common__get_common_level
    t = ADSL::Spass::SpassTranslator::Translation.new
    root_c = t.context
    c1 = ADSL::Spass::SpassTranslator::FlatContext.new t, 'a', t.context
    c1_sub = ADSL::Spass::SpassTranslator::FlatContext.new t, 'a', c1
    c1_sub2 = ADSL::Spass::SpassTranslator::ChainedContext.new t, 'a', c1
    c2 = ADSL::Spass::SpassTranslator::ChainedContext.new t, 'a', t.context
    
    assert_equal root_c, ADSL::Spass::SpassTranslator::ContextCommon.get_common_context(root_c, root_c)
    assert_equal root_c, ADSL::Spass::SpassTranslator::ContextCommon.get_common_context(root_c, c1)
    assert_equal root_c, ADSL::Spass::SpassTranslator::ContextCommon.get_common_context(root_c, c1_sub)
    assert_equal c1, ADSL::Spass::SpassTranslator::ContextCommon.get_common_context(c1, c1)
    assert_equal c1, ADSL::Spass::SpassTranslator::ContextCommon.get_common_context(c1_sub, c1)
    assert_equal c1, ADSL::Spass::SpassTranslator::ContextCommon.get_common_context(c1_sub, c1_sub2)
    assert_equal root_c, ADSL::Spass::SpassTranslator::ContextCommon.get_common_context(c1, c2)
  end
  
  def test_context__order_in_root_context
    # supposed to emulate two statements in the same for loop
    t = ADSL::Spass::SpassTranslator::Translation.new
    context = t.context

    assert_equal "true", context.before(context, :c, :temp, true).resolve_spass
    assert_equal "false", context.before(context, :c, :temp, false).resolve_spass
  end

  def test_context__order_same_lvl_chained
    # supposed to emulate two statements in the same chained foreach loop
    t = ADSL::Spass::SpassTranslator::Translation.new
    c1 = ADSL::Spass::SpassTranslator::ChainedContext.new t, 'a', t.context

    expected = ADSL::FOL::Implies.new(
      ADSL::FOL::And.new(
        c1.type_pred('a'), c1.type_pred('b')
      ),
      ADSL::FOL::And.new(
        ADSL::FOL::Implies.new(c1.before_pred['a', 'b'], true),
        ADSL::FOL::Implies.new(c1.before_pred['b', 'a'], false),
        ADSL::FOL::Implies.new(
          ADSL::FOL::Not.new(c1.before_pred['a', 'b'], c1.before_pred['b', 'a']),
          false
        )
      )
    )
    assert_equal expected.resolve_spass, c1.before(c1, :a, :b, false).resolve_spass
    
    expected = ADSL::FOL::Implies.new(
      ADSL::FOL::And.new(
        c1.type_pred('a'), c1.type_pred('b')
      ),
      ADSL::FOL::And.new(
        ADSL::FOL::Implies.new(c1.before_pred['a', 'b'], true),
        ADSL::FOL::Implies.new(c1.before_pred['b', 'a'], false),
        ADSL::FOL::Implies.new(
          ADSL::FOL::Not.new(c1.before_pred['a', 'b'], c1.before_pred['b', 'a']),
          true
        )
      )
    )
    assert_equal expected.resolve_spass, c1.before(c1, :a, :b, true).resolve_spass
  end
  
  def test_context__order_same_lvl_flat
    # supposed to emulate two statements in the same chained foreach loop
    t = ADSL::Spass::SpassTranslator::Translation.new
    c1 = ADSL::Spass::SpassTranslator::FlatContext.new t, 'a', t.context

    expected = ADSL::FOL::Implies.new(
      ADSL::FOL::And.new(
        c1.type_pred('a'), c1.type_pred('b')
      ),
      ADSL::FOL::And.new(
        ADSL::FOL::Implies.new(false, true),
        ADSL::FOL::Implies.new(false, false),
        ADSL::FOL::Implies.new(
          ADSL::FOL::Not.new(false, false),
          false
        )
      )
    )
    assert_equal expected.resolve_spass, c1.before(c1, :a, :b, false).resolve_spass
    
    expected = ADSL::FOL::Implies.new(
      ADSL::FOL::And.new(
        c1.type_pred('a'), c1.type_pred('b')
      ),
      ADSL::FOL::And.new(
        ADSL::FOL::Implies.new(false, true),
        ADSL::FOL::Implies.new(false, false),
        ADSL::FOL::Implies.new(
          ADSL::FOL::Not.new(false, false),
          true
        )
      )
    )
    assert_equal expected.resolve_spass, c1.before(c1, :a, :b, true).resolve_spass
  end

  def test_context__order_with_subcontext
    # supposed to emulate a c1 statement followed by a c2 foreach with a stmt inside
    t = ADSL::Spass::SpassTranslator::Translation.new
    c1 = ADSL::Spass::SpassTranslator::FlatContext.new t, 'a', t.context
    c2 = ADSL::Spass::SpassTranslator::ChainedContext.new t, 'a', c1

    expected = ADSL::FOL::ForAll.new('parent_b1', ADSL::FOL::Implies.new(
      ADSL::FOL::And.new(c1.type_pred('a'), c2.type_pred('parent_a1', 'b')),
      true
    ))
    assert_equal expected.resolve_spass, c1.before(c2, :a, :b, true).resolve_spass
    
    expected = ADSL::FOL::ForAll.new('parent_a1', ADSL::FOL::Implies.new(
      ADSL::FOL::And.new(c2.type_pred('parent_a1', 'a'), c1.type_pred('b')),
      false
    ))
    assert_equal expected.resolve_spass, c2.before(c1, :a, :b, false).resolve_spass
  end

  def test_context__listed_in_all_context
    t = ADSL::Spass::SpassTranslator::Translation.new
    c2 = t.create_context 'a', true, t.context
    c3 = t.create_context 'a', true, c2
    c4 = t.create_context 'a', true, c2
    assert_equal 4, t.all_contexts.length
    assert_equal Set[t.root_context, c2, c3, c4], Set[*t.all_contexts]
  end

  def test_context__statements_in_two_nested_fors
    t = ADSL::Spass::SpassTranslator::Translation.new
    outside_for_context = ADSL::Spass::SpassTranslator::ChainedContext.new t, 'a', t.context
    inside_for_context = ADSL::Spass::SpassTranslator::ChainedContext.new t, 'a', outside_for_context
    assert_not_equal inside_for_context.before_pred.name, outside_for_context.before_pred.name

    expected = ADSL::FOL::ForAll.new('parent_a1', 'parent_b1', ADSL::FOL::Implies.new(
      ADSL::FOL::And.new(
        inside_for_context.type_pred('parent_a1', 'a'),
        inside_for_context.type_pred('parent_b1', 'b')
      ),
      ADSL::FOL::And.new(
        ADSL::FOL::Implies.new(outside_for_context.before_pred['parent_a1', 'parent_b1'], true),
        ADSL::FOL::Implies.new(outside_for_context.before_pred['parent_b1', 'parent_a1'], false),
        ADSL::FOL::Implies.new(
          ADSL::FOL::Not.new(
            outside_for_context.before_pred['parent_a1', 'parent_b1'],
            outside_for_context.before_pred['parent_b1', 'parent_a1']
          ),
          ADSL::FOL::And.new(
            ADSL::FOL::Implies.new(inside_for_context.before_pred['parent_a1', 'a', 'b'], true),
            ADSL::FOL::Implies.new(inside_for_context.before_pred['parent_a1', 'b', 'a'], false),
            ADSL::FOL::Implies.new(
              ADSL::FOL::Not.new(
                inside_for_context.before_pred['parent_a1', 'a', 'b'],
                inside_for_context.before_pred['parent_a1', 'b', 'a']
              ),
              true
            )
          )
        )
      )
    )) 
    assert_equal expected.resolve_spass, inside_for_context.before(inside_for_context, :a, :b, true).resolve_spass
  end

  def test_translation__pre_post_create_objs
    translation = ADSL::Spass::SpassTranslator::Translation.new
    a_klass = ADSL::DS::DSClass.new(:name => "a", :parent => nil, :relations => [])
    a_stmt = ADSL::DS::DSCreateObj.new(:klass => a_klass)
    b_klass = ADSL::DS::DSClass.new(:name => "b", :parent => nil, :relations => [])
    b_stmt = ADSL::DS::DSCreateObj.new(:klass => b_klass)
    block = ADSL::DS::DSBlock.new(:statements => [a_stmt, b_stmt])
   
    translation.state = translation.create_state :initial
    block.prepare translation
    
    assert_equal [a_klass, b_klass], translation.create_obj_stmts.keys.sort_by{ |a| a.name }
    assert_equal [a_stmt], translation.create_obj_stmts[a_klass]
    assert_equal [b_stmt], translation.create_obj_stmts[b_klass]
  end

  def test_spass_wrap
    translation = ADSL::Spass::SpassTranslator::Translation.new
    assert_equal "", translation.spass_wrap("blah\sblah", "")
    assert_equal "blahasdblah", translation.spass_wrap("blah%sblah", "asd")
  end

  def test_spass_list_of
    translation = ADSL::Spass::SpassTranslator::Translation.new
    assert_equal "", translation.spass_list_of(:symbol, [])
    assert_equal "", translation.spass_list_of(:symbol, [], [])
    expected = <<-SPASS
    list_of_symbol.
      blah
      kme
    end_of_list.
    SPASS
    assert_equal expected.gsub(/^[ \t]+/, '').strip, translation.spass_list_of(:symbol, "blah", "kme").gsub(/^[ \t]+/, '')
  end
end

