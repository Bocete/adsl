require 'fol/first_order_logic'
require 'test/unit'
require 'pp'

class FirstOrderLogicTest < Test::Unit::TestCase
  def teardown
    if Object.constants.include?(:Foo)
      Object.send(:remove_const, :Foo)
    end
  end
  
  def test_fol_class_integration
    eval <<-ruby
      class Foo
        include FOL
      end
    ruby
    foo = Foo.new
    assert foo.methods.include?("_and") || foo.methods.include?(:_and)

    eval <<-ruby
      class Foo
        def asd
          _and(:a, :b)
        end
      end
    ruby
    assert_equal "and(a, b)", Foo.new.asd.resolve_spass
  end

  def test_literals
    assert_equal "true", true.resolve_spass
    assert_equal "false", false.resolve_spass
    assert_equal "symbol_here", :symbol_here.resolve_spass
    assert_equal "sometext", "sometext".resolve_spass
  end

  def test_split_by_zero_level_comma
    assert_equal [""], "".split_by_zero_level_comma
    assert_equal ["asd"], "asd".split_by_zero_level_comma
    assert_equal ["asd", "kme"], "asd,kme".split_by_zero_level_comma
    assert_equal ["asd", ""], "asd,".split_by_zero_level_comma
    assert_equal ["", ""], ",".split_by_zero_level_comma
    assert_equal ["(asd, asd)"], "(asd, asd)".split_by_zero_level_comma
    assert_equal ["(a,a,a,()((()())))", ""], "(a,a,a,()((()()))),".split_by_zero_level_comma
    assert_raise do
      ")(".split_by_zero_level_comma
    end
  end

  def test_not
    assert_raise ArgumentError do
      FOL::Not.new
    end
    assert_equal "not(a)", FOL::Not.new(:a).resolve_spass
    assert_equal "and(not(a), not(b))".gsub(/\s+/, ''), \
        FOL::Not.new(:a, :b).resolve_spass.gsub(/\s+/, '')
    assert_equal "true", FOL::Not.new(false).resolve_spass
    assert_equal "false", FOL::Not.new(true).resolve_spass
    assert_equal "false", FOL::Not.new(true, false).resolve_spass
    assert_equal "a", FOL::Not.new(FOL::Not.new(:a)).resolve_spass
    assert_equal "and(a, not(b))", FOL::Not.new(FOL::Not.new(:a), FOL::Not.new(FOL::Not.new(:b))).resolve_spass
  end

  def test_and
    assert_equal "true", FOL::And.new.resolve_spass

    assert_equal "a", FOL::And.new("a").resolve_spass
    assert_equal "and(a, b)", FOL::And.new("a", "b").resolve_spass
    
    assert_equal "a", FOL::And.new(true, 'a').resolve_spass
    assert_equal "and(a, b)", FOL::And.new(true, "a", "b").resolve_spass
    assert_equal "false", FOL::And.new(true, false).resolve_spass
    assert_equal "true", FOL::And.new(true).resolve_spass

    assert_equal "and(a, b, c)", FOL::And.new(FOL::And.new(:a, :b), :c).resolve_spass
  end
  
  def test_or
    assert_equal "false", FOL::Or.new.resolve_spass

    assert_equal "a", FOL::Or.new("a").resolve_spass
    assert_equal "or(a, b)", FOL::Or.new("a", "b").resolve_spass
    
    assert_equal "a", FOL::Or.new(false, 'a').resolve_spass
    assert_equal "or(a, b)", FOL::Or.new(false, "a", "b").resolve_spass
    assert_equal "true", FOL::Or.new(true, false).resolve_spass
    assert_equal "false", FOL::Or.new(false).resolve_spass
    
    assert_equal "or(a, b, c)", FOL::Or.new(FOL::Or.new(:a, :b), :c).resolve_spass
  end
  
  def test_forall
    assert_raise ArgumentError do
      FOL::ForAll.new
    end

    assert_equal "a", FOL::ForAll.new(:a).resolve_spass
    assert_equal "true", FOL::ForAll.new(:a, :b, true).resolve_spass
    assert_equal "false", FOL::ForAll.new(:a, :b, false).resolve_spass
    assert_equal "forall([a], blah(a))".gsub(/\s+/, ''), \
        FOL::ForAll.new(:a, "blah(a)").resolve_spass.gsub(/\s+/, '')
    assert_equal "forall([a, b], blah(a))".gsub(/\s+/, ''), \
        FOL::ForAll.new(:a, :b, "blah(a)").resolve_spass.gsub(/\s+/, '')
  end
  
  def test_exists
    assert_raise ArgumentError do
      FOL::Exists.new
    end

    assert_equal "a", FOL::Exists.new(:a).resolve_spass
    assert_equal "true", FOL::ForAll.new(:a, :b, true).resolve_spass
    assert_equal "false", FOL::ForAll.new(:a, :b, false).resolve_spass
    assert_equal "exists([a], true(a))".gsub(/\s+/, ''), \
        FOL::Exists.new(:a, "true(a)").resolve_spass.gsub(/\s+/, '')
    assert_equal "exists([a, b], true(a))".gsub(/\s+/, ''), \
        FOL::Exists.new(:a, :b, "true(a)").resolve_spass.gsub(/\s+/, '')
  end

  def test_equiv
    assert_raise ArgumentError do
      FOL::Equiv.new
    end
    assert_raise ArgumentError do
      FOL::Equiv.new :a
    end

    assert_equal 'a', FOL::Equiv.new(true, :a).resolve_spass
    assert_equal 'and(a, b)', FOL::Equiv.new(:a, true, :b).resolve_spass
    assert_equal 'and(not(a), not(b))', FOL::Equiv.new(:a, false, :b).resolve_spass
    assert_equal 'false', FOL::Equiv.new(:a, false, :b, true).resolve_spass
    assert_equal "equiv(a, b)".gsub(/\s+/, ''), \
        FOL::Equiv.new(:a, :b).resolve_spass.gsub(/\s+/, '')
    assert_equal "and(equiv(a, b), equiv(b, c))".gsub(/\s+/, ''), \
        FOL::Equiv.new(:a, :b, :c).resolve_spass.gsub(/\s+/, '')
  end
  
  def test_implies
    assert_raise ArgumentError do
      FOL::Implies.new
    end
    assert_raise ArgumentError do
      FOL::Implies.new :a
    end
    assert_raise ArgumentError do
      FOL::Implies.new :a, :b, :c
    end

    assert_equal "implies(a, b)".gsub(/\s+/, ''), \
        FOL::Implies.new(:a, :b).resolve_spass.gsub(/\s+/, '')
    assert_equal "a".gsub(/\s+/, ''), \
        FOL::Implies.new(true, :a).resolve_spass.gsub(/\s+/, '')
    assert_equal "true".gsub(/\s+/, ''), \
        FOL::Implies.new(:a, true).resolve_spass.gsub(/\s+/, '')
    assert_equal "true".gsub(/\s+/, ''), \
        FOL::Implies.new(false, :a).resolve_spass.gsub(/\s+/, '')
    assert_equal "not(a)".gsub(/\s+/, ''), \
        FOL::Implies.new(:a, false).resolve_spass.gsub(/\s+/, '')

    assert_equal 'true', FOL::Implies.new(true, true).resolve_spass
    assert_equal 'false', FOL::Implies.new(true, false).resolve_spass
    assert_equal 'true', FOL::Implies.new(false, true).resolve_spass
    assert_equal 'true', FOL::Implies.new(false, false).resolve_spass
  end
  
  def test_equal
    assert_raise ArgumentError do
      FOL::Equal.new
    end
    assert_raise ArgumentError do
      FOL::Equal.new :a
    end

    assert_equal "equal(a, b)".gsub(/\s+/, ''), \
        FOL::Equal.new(:a, :b).resolve_spass.gsub(/\s+/, '')
    assert_equal "and(equal(a, b), equal(b, c))".gsub(/\s+/, ''), \
        FOL::Equal.new(:a, :b, :c).resolve_spass.gsub(/\s+/, '')
  end

  def test_one_of
    assert_equal 'false', FOL::OneOf.new.resolve_spass
    assert_equal "a".gsub(/\s+/, ''), \
        FOL::OneOf.new(:a).resolve_spass.gsub(/\s+/, '')
    assert_equal "equiv(not(a), b)".gsub(/\s+/, ''), \
        FOL::OneOf.new(:a, :b).resolve_spass.gsub(/\s+/, '')
    assert_equal "and(or(a, b, c), implies(a, and(not(b), not(c))), implies(b, and(not(a), not(c))), implies(c, and(not(a), not(b))))".gsub(/\s+/, ''), \
        FOL::OneOf.new(:a, :b, :c).resolve_spass.gsub(/\s+/, '')
  end

  def test_if_then_else
    assert_equal "and(implies(a, b), implies(not(a), c))".gsub(/\s+/, ''), \
        FOL::IfThenElse.new(:a, :b, :c).resolve_spass.gsub(/\s+/, '')
  end

  def test_if_then_else_eq
    assert_equal "and(equiv(a, b), equiv(not(a), c))".gsub(/\s+/, ''), \
        FOL::IfThenElseEq.new(:a, :b, :c).resolve_spass.gsub(/\s+/, '')
  end

  def test_pairwise_equal__explicit_lists
    assert_raise ArgumentError do
      FOL::PairwiseEqual.new [], [:a]
    end
    assert_raise ArgumentError do
      FOL::PairwiseEqual.new [:b, :c], [:a]
    end

    assert_equal "true", FOL::PairwiseEqual.new([], []).resolve_spass
    assert_equal "equal(a1, b1)", FOL::PairwiseEqual.new([:a1], [:b1]).resolve_spass
    assert_equal "and(equal(a1, b1), equal(a2, b2))", FOL::PairwiseEqual.new([:a1, :a2], [:b1, :b2]).resolve_spass
  end
  
  def test_pairwise_equal__implicit_lists
    assert_raise ArgumentError do
      FOL::PairwiseEqual.new :a
    end
    assert_raise ArgumentError do
      FOL::PairwiseEqual.new :b, [[:c]], :a
    end

    assert_equal "true", FOL::PairwiseEqual.new().resolve_spass
    assert_equal "equal(a1, b1)", FOL::PairwiseEqual.new(:a1, :b1).resolve_spass
    assert_equal "and(equal(a1, b1), equal(a2, b2))", FOL::PairwiseEqual.new(:a1, :a2, :b1, [:b2]).resolve_spass
  end
end

