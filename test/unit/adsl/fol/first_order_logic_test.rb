require 'adsl/util/test_helper'
require 'adsl/fol/first_order_logic'
require 'adsl/ds/fol_translation/typed_string'

class ADSL::FOL::FirstOrderLogicTest < ActiveSupport::TestCase
  include ADSL::FOL

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
    assert_equal And.new(:a, :b), Foo.new.asd

    assert_equal And.new(:a, :b), And[:a, :b]
    assert_equal Or.new(:a, :b),  Or[:a, :b]
  end

  def test_predicate_extensions
    assert_raises ArgumentError do
      Predicate.new :name, :type
    end
    assert_nothing_raised do 
      ADSL::FOL::Predicate.new :pred_name, ADSL::FOL::Sort.new('sort1'), ADSL::FOL::Sort.new('sort2')
    end
  end

  def test_not
    assert_nothing_raised{ Not.new }
    assert_nothing_raised{ Not.new :a }
    assert_nothing_raised{ Not.new :a, :b }
  end

  def test_not__optimize
    assert_equal true, Not.new(false).optimize
    assert_equal false, Not.new(true).optimize
    assert_equal false, Not.new(true, false).optimize
    assert_equal false, Not.new(false, true).optimize
    assert_equal :a, Not.new(Not.new(:a)).optimize
  end

  def test_and
    assert_nothing_raised{ And.new }
    assert_nothing_raised{ And.new(:a) }
    assert_nothing_raised{ And.new(:a, :b) }
    assert_nothing_raised{ And.new(:a, :b, :c) }
  end

  def test_and__optimize
    assert_equal true, And.new(true, true).optimize
    assert_equal false, And.new(:a, false).optimize
    assert_equal :a, And.new(true, :a).optimize
    assert_equal And.new(:a, :b), And.new(:a, :b, :a, :b, :a).optimize
    assert_equal And.new(:a, :b, :c), And.new(And.new(:a, :b), :c).optimize
    assert_equal And.new(:a, :c), And.new(And.new(:a, true), :c).optimize
    assert_equal false, And.new(And.new(:a, false), :c).optimize
  end
  
  def test_or
    assert_nothing_raised{ Or.new }
    assert_nothing_raised{ Or.new(:a) }
    assert_nothing_raised{ Or.new(:a, :b) }
    assert_nothing_raised{ Or.new(:a, :b, :c) }
  end

  def test_or__optimize
    assert_equal false, Or.new(false, false).optimize
    assert_equal true, Or.new(:a, true).optimize
    assert_equal :a, Or.new(false, :a).optimize
    assert_equal Or.new(:a, :b), Or.new(:a, :b, :a, :b, :a).optimize
    assert_equal Or.new(:a, :b, :c), Or.new(Or.new(:a, :b), :c).optimize
    assert_equal Or.new(:a, :c), Or.new(Or.new(:a, false), :c).optimize
    assert_equal true, Or.new(Or.new(:a, true), :c).optimize
  end

  def test_forall
    assert_raises ArgumentError do
      ForAll.new
    end
    assert_raises ArgumentError do
      ForAll.new :a, :b
    end
    assert_nothing_raised{ ForAll.new :a }
    assert_nothing_raised{ ForAll.new :type, :var, :a }
  end

  def test_forall__optimize
    assert_equal :a, ForAll.new(:a).optimize
    assert_equal true, ForAll.new(:type, :var, true).optimize
  end
  
  def test_exists
    assert_raises ArgumentError do
      Exists.new
    end
    assert_nothing_raised{ Exists.new :a }
    assert_nothing_raised{ Exists.new :type, :var }
    assert_equal Exists.new(:type, :var), Exists.new(:type, :var, true)
    assert_nothing_raised{ Exists.new :type, :var, :a }
  end

  def test_exists__optimize
    assert_equal :a, Exists.new(:a).optimize
    # exists is a positive statement about existance
    # and shouldn't be optimized like this
    assert_not_equal true, Exists.new(:type, :var, true).optimize
  end

  def test_quantification__typed_string_support
    sort = Sort.new :sort
    v1 = ADSL::DS::FOLTranslation::TypedString.new sort, :v1
    v2 = ADSL::DS::FOLTranslation::TypedString.new sort, :v2
    v3 = ADSL::DS::FOLTranslation::TypedString.new sort, :v3
    v4 = ADSL::DS::FOLTranslation::TypedString.new sort, :v4
    v5 = ADSL::DS::FOLTranslation::TypedString.new sort, :v5
    [ForAll, Exists].each do |q|
      5.times do |a|
        args = [v1, v2, v3, v4, v5].first(a+1), true
        assert_nothing_raised "Error raised for #{q.name}, arguments #{args}" do
          q.new args
        end
        assert_nothing_raised "Error raised for #{q.name}, splashed arguments #{args}" do
          q.new *args
        end
      end
    end
  end
  

  def test_equiv
    assert_raises ArgumentError do
      Equiv.new
    end
    assert_raises ArgumentError do
      Equiv.new :a
    end
    assert_nothing_raised{ Equiv.new :a, :b }
    assert_nothing_raised{ Equiv.new :a, :b, :c }
  end

  def test_equiv__optimize
    assert_equal :a, Equiv.new(true, :a).optimize
    assert_equal true, Equiv.new(:a, :a).optimize
    assert_equal Equiv.new(:a, :b), Equiv.new(:a, :b, :a, :b).optimize
    assert_equal And.new(:a, :b), Equiv.new(:a, true, :b).optimize
    assert_equal And.new(:a, :b), Equiv.new(:a, true, :b).optimize
    assert_equal Not.new(:a), Equiv.new(:a, false).optimize
    assert_equal Not.new(:a, :b), Equiv.new(:a, false, :b).optimize
    assert_equal false, Equiv.new(:a, false, :b, true).optimize
  end
  
  def test_implies
    assert_raises ArgumentError do
      Implies.new
    end
    assert_raises ArgumentError do
      Implies.new :a
    end
    assert_raises ArgumentError do
      Implies.new :a, :b, :c
    end
    assert_nothing_raised{ Implies.new :a, :b }
  end

  def test_implies__optimize
    assert_equal :a, Implies.new(true, :a).optimize
    assert_equal Not.new(:a), Implies.new(:a, false).optimize
    assert_equal true, Implies.new(:a, true).optimize
    assert_equal true, Implies.new(false, :a).optimize
    assert_equal Implies.new(And.new(:a, :b), :c), Implies.new(:a, Implies.new(:b, :c)).optimize

    assert_equal true,  Implies.new(true, true).optimize
    assert_equal false, Implies.new(true, false).optimize
    assert_equal true,  Implies.new(false, true).optimize
    assert_equal true,  Implies.new(false, false).optimize
  end

  def test_equal
    assert_raises ArgumentError do
      Equal.new
    end
    assert_raises ArgumentError do
      Equal.new :a
    end
    assert_nothing_raised{ Equal.new :a, :b }
    assert_nothing_raised{ Equal.new :a, :b, :c }
  end

  def test_equal_optimize
    assert_equal Equal.new(:a, :b), Equal.new(:a, :b, :a, :b, :a).optimize
    assert_equal true, Equal.new(:a, :a).optimize
  end

  def test_xor
    assert_nothing_raised{ Xor.new }
    assert_nothing_raised{ Xor.new :a }
    assert_nothing_raised{ Xor.new :a, :b }
    assert_nothing_raised{ Xor.new :a, :b, :c }
  end

  def test_xor__optimize
    assert_equal false, Xor.new.optimize
    assert_equal :a, Xor.new(:a).optimize
  end

  def test_if_then_else
    assert_raises ArgumentError do
      IfThenElse.new
    end
    assert_raises ArgumentError do
      IfThenElse.new :a
    end
    assert_raises ArgumentError do
      IfThenElse.new :a, :b
    end
    assert_raises ArgumentError do
      IfThenElse.new :a, :b, :c, :d
    end
  end

  def test_if_then_else__optimize
    assert_equal :b, IfThenElse.new(true, :b, :c).optimize
    assert_equal :c, IfThenElse.new(false, :b, :c).optimize
  end
  
  def test_if_then_else_eq
    assert_raises ArgumentError do
      IfThenElseEq.new
    end
    assert_raises ArgumentError do
      IfThenElseEq.new :a
    end
    assert_raises ArgumentError do
      IfThenElseEq.new :a, :b
    end
    assert_raises ArgumentError do
      IfThenElseEq.new :a, :b, :c, :d
    end
  end

  def test_if_then_else_eq__optimize
    assert_equal :b, IfThenElseEq.new(true, :b, :c).optimize
    assert_equal :c, IfThenElseEq.new(false, :b, :c).optimize
  end

  def test_pairwise_equal__explicit_lists
    assert_raises ArgumentError do
      PairwiseEqual.new [], [:a]
    end
    assert_raises ArgumentError do
      PairwiseEqual.new [:b, :c], [:a]
    end
    assert_nothing_raised{ PairwiseEqual.new([], []) }
    assert_nothing_raised{ PairwiseEqual.new([:a1], [:b1]) }
    assert_nothing_raised{ PairwiseEqual.new([:a1, :a2], [:b1, :b2]) }
  end
  
  def test_pairwise_equal__implicit_lists
    assert_raises ArgumentError do
      PairwiseEqual.new :a
    end
    assert_raises ArgumentError do
      PairwiseEqual.new :b, [[:c]], :a
    end
    assert_nothing_raised{ PairwiseEqual.new }
    assert_nothing_raised{ PairwiseEqual.new(:a1, :b1) }
    assert_nothing_raised{ PairwiseEqual.new(:a1, :a2, :b1, [:b2]) }
  end
end

