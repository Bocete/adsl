require 'adsl/fol/first_order_logic'
require 'test/unit'
require 'pp'

class ADSL::FOL::FirstOrderLogicTest < Test::Unit::TestCase
  def teardown
    if Object.constants.include?(:Foo)
      Object.send(:remove_const, :Foo)
    end
  end
  
  def test_fol_class_integration
    eval <<-ruby
      class Foo
        include ADSL::FOL
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
      ADSL::FOL::Not.new
    end
    assert_equal "not(a)", ADSL::FOL::Not.new(:a).resolve_spass
    assert_equal "and(not(a), not(b))".gsub(/\s+/, ''), \
        ADSL::FOL::Not.new(:a, :b).resolve_spass.gsub(/\s+/, '')
    assert_equal "true", ADSL::FOL::Not.new(false).resolve_spass
    assert_equal "false", ADSL::FOL::Not.new(true).resolve_spass
    assert_equal "false", ADSL::FOL::Not.new(true, false).resolve_spass
    assert_equal "a", ADSL::FOL::Not.new(ADSL::FOL::Not.new(:a)).resolve_spass
    assert_equal "and(a, not(b))", ADSL::FOL::Not.new(ADSL::FOL::Not.new(:a), ADSL::FOL::Not.new(ADSL::FOL::Not.new(:b))).resolve_spass
  end

  def test_and
    assert_equal "true", ADSL::FOL::And.new.resolve_spass

    assert_equal "a", ADSL::FOL::And.new("a").resolve_spass
    assert_equal "and(a, b)", ADSL::FOL::And.new("a", "b").resolve_spass
    
    assert_equal "a", ADSL::FOL::And.new(true, 'a').resolve_spass
    assert_equal "and(a, b)", ADSL::FOL::And.new(true, "a", "b").resolve_spass
    assert_equal "false", ADSL::FOL::And.new(true, false).resolve_spass
    assert_equal "true", ADSL::FOL::And.new(true).resolve_spass

    assert_equal "and(a, b, c)", ADSL::FOL::And.new(ADSL::FOL::And.new(:a, :b), :c).resolve_spass
  end
  
  def test_or
    assert_equal "false", ADSL::FOL::Or.new.resolve_spass

    assert_equal "a", ADSL::FOL::Or.new("a").resolve_spass
    assert_equal "or(a, b)", ADSL::FOL::Or.new("a", "b").resolve_spass
    
    assert_equal "a", ADSL::FOL::Or.new(false, 'a').resolve_spass
    assert_equal "or(a, b)", ADSL::FOL::Or.new(false, "a", "b").resolve_spass
    assert_equal "true", ADSL::FOL::Or.new(true, false).resolve_spass
    assert_equal "false", ADSL::FOL::Or.new(false).resolve_spass
    
    assert_equal "or(a, b, c)", ADSL::FOL::Or.new(ADSL::FOL::Or.new(:a, :b), :c).resolve_spass
  end
  
  def test_forall
    assert_raise ArgumentError do
      ADSL::FOL::ForAll.new
    end

    assert_equal "a", ADSL::FOL::ForAll.new(:a).resolve_spass
    assert_equal "true", ADSL::FOL::ForAll.new(:a, :b, true).resolve_spass
    assert_equal "false", ADSL::FOL::ForAll.new(:a, :b, false).resolve_spass
    assert_equal "forall([a], blah(a))".gsub(/\s+/, ''), \
        ADSL::FOL::ForAll.new(:a, "blah(a)").resolve_spass.gsub(/\s+/, '')
    assert_equal "forall([a, b], blah(a))".gsub(/\s+/, ''), \
        ADSL::FOL::ForAll.new(:a, :b, "blah(a)").resolve_spass.gsub(/\s+/, '')
  end
  
  def test_exists
    assert_raise ArgumentError do
      ADSL::FOL::Exists.new
    end

    assert_equal "a", ADSL::FOL::Exists.new(:a).resolve_spass
    assert_equal "true", ADSL::FOL::ForAll.new(:a, :b, true).resolve_spass
    assert_equal "false", ADSL::FOL::ForAll.new(:a, :b, false).resolve_spass
    assert_equal "exists([a], true(a))".gsub(/\s+/, ''), \
        ADSL::FOL::Exists.new(:a, "true(a)").resolve_spass.gsub(/\s+/, '')
    assert_equal "exists([a, b], true(a))".gsub(/\s+/, ''), \
        ADSL::FOL::Exists.new(:a, :b, "true(a)").resolve_spass.gsub(/\s+/, '')
  end

  def test_equiv
    assert_raise ArgumentError do
      ADSL::FOL::Equiv.new
    end
    assert_raise ArgumentError do
      ADSL::FOL::Equiv.new :a
    end

    assert_equal 'a', ADSL::FOL::Equiv.new(true, :a).resolve_spass
    assert_equal 'and(a, b)', ADSL::FOL::Equiv.new(:a, true, :b).resolve_spass
    assert_equal 'and(not(a), not(b))', ADSL::FOL::Equiv.new(:a, false, :b).resolve_spass
    assert_equal 'false', ADSL::FOL::Equiv.new(:a, false, :b, true).resolve_spass
    assert_equal "equiv(a, b)".gsub(/\s+/, ''), \
        ADSL::FOL::Equiv.new(:a, :b).resolve_spass.gsub(/\s+/, '')
    assert_equal "and(equiv(a, b), equiv(b, c))".gsub(/\s+/, ''), \
        ADSL::FOL::Equiv.new(:a, :b, :c).resolve_spass.gsub(/\s+/, '')
  end
  
  def test_implies
    assert_raise ArgumentError do
      ADSL::FOL::Implies.new
    end
    assert_raise ArgumentError do
      ADSL::FOL::Implies.new :a
    end
    assert_raise ArgumentError do
      ADSL::FOL::Implies.new :a, :b, :c
    end

    assert_equal "implies(a, b)".gsub(/\s+/, ''), \
        ADSL::FOL::Implies.new(:a, :b).resolve_spass.gsub(/\s+/, '')
    assert_equal "a".gsub(/\s+/, ''), \
        ADSL::FOL::Implies.new(true, :a).resolve_spass.gsub(/\s+/, '')
    assert_equal "true".gsub(/\s+/, ''), \
        ADSL::FOL::Implies.new(:a, true).resolve_spass.gsub(/\s+/, '')
    assert_equal "true".gsub(/\s+/, ''), \
        ADSL::FOL::Implies.new(false, :a).resolve_spass.gsub(/\s+/, '')
    assert_equal "not(a)".gsub(/\s+/, ''), \
        ADSL::FOL::Implies.new(:a, false).resolve_spass.gsub(/\s+/, '')

    assert_equal 'true', ADSL::FOL::Implies.new(true, true).resolve_spass
    assert_equal 'false', ADSL::FOL::Implies.new(true, false).resolve_spass
    assert_equal 'true', ADSL::FOL::Implies.new(false, true).resolve_spass
    assert_equal 'true', ADSL::FOL::Implies.new(false, false).resolve_spass
  end
  
  def test_equal
    assert_raise ArgumentError do
      ADSL::FOL::Equal.new
    end
    assert_raise ArgumentError do
      ADSL::FOL::Equal.new :a
    end

    assert_equal "equal(a, b)".gsub(/\s+/, ''), \
        ADSL::FOL::Equal.new(:a, :b).resolve_spass.gsub(/\s+/, '')
    assert_equal "and(equal(a, b), equal(b, c))".gsub(/\s+/, ''), \
        ADSL::FOL::Equal.new(:a, :b, :c).resolve_spass.gsub(/\s+/, '')
  end

  def test_one_of
    assert_equal 'false', ADSL::FOL::OneOf.new.resolve_spass
    assert_equal "a".gsub(/\s+/, ''), \
        ADSL::FOL::OneOf.new(:a).resolve_spass.gsub(/\s+/, '')
    assert_equal "equiv(not(a), b)".gsub(/\s+/, ''), \
        ADSL::FOL::OneOf.new(:a, :b).resolve_spass.gsub(/\s+/, '')
    assert_equal "and(or(a, b, c), implies(a, and(not(b), not(c))), implies(b, and(not(a), not(c))), implies(c, and(not(a), not(b))))".gsub(/\s+/, ''), \
        ADSL::FOL::OneOf.new(:a, :b, :c).resolve_spass.gsub(/\s+/, '')
  end

  def test_if_then_else
    assert_equal "and(implies(a, b), implies(not(a), c))".gsub(/\s+/, ''), \
        ADSL::FOL::IfThenElse.new(:a, :b, :c).resolve_spass.gsub(/\s+/, '')
  end

  def test_if_then_else_eq
    assert_equal "and(equiv(a, b), equiv(not(a), c))".gsub(/\s+/, ''), \
        ADSL::FOL::IfThenElseEq.new(:a, :b, :c).resolve_spass.gsub(/\s+/, '')
  end

  def test_pairwise_equal__explicit_lists
    assert_raise ArgumentError do
      ADSL::FOL::PairwiseEqual.new [], [:a]
    end
    assert_raise ArgumentError do
      ADSL::FOL::PairwiseEqual.new [:b, :c], [:a]
    end

    assert_equal "true", ADSL::FOL::PairwiseEqual.new([], []).resolve_spass
    assert_equal "equal(a1, b1)", ADSL::FOL::PairwiseEqual.new([:a1], [:b1]).resolve_spass
    assert_equal "and(equal(a1, b1), equal(a2, b2))", ADSL::FOL::PairwiseEqual.new([:a1, :a2], [:b1, :b2]).resolve_spass
  end
  
  def test_pairwise_equal__implicit_lists
    assert_raise ArgumentError do
      ADSL::FOL::PairwiseEqual.new :a
    end
    assert_raise ArgumentError do
      ADSL::FOL::PairwiseEqual.new :b, [[:c]], :a
    end

    assert_equal "true", ADSL::FOL::PairwiseEqual.new().resolve_spass
    assert_equal "equal(a1, b1)", ADSL::FOL::PairwiseEqual.new(:a1, :b1).resolve_spass
    assert_equal "and(equal(a1, b1), equal(a2, b2))", ADSL::FOL::PairwiseEqual.new(:a1, :a2, :b1, [:b2]).resolve_spass
  end
end

