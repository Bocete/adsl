require 'adsl/util/test_helper'
require 'adsl/fol/first_order_logic'
require 'adsl/prover/z3/fol_extensions'
require 'adsl/ds/data_store_spec'
require 'adsl/ds/fol_translation/ds_extensions'

class ADSL::Prover::Z3FolExtensionsTest < ActiveSupport::TestCase
  include ADSL::FOL
  
  def test_literals
    assert_equal "true", true.to_smt2_string
    assert_equal "false", false.to_smt2_string
    assert_equal "symbol_here", :symbol_here.to_smt2_string
    assert_equal "sometext", "sometext".to_smt2_string
  end

  def test_not
    assert_equal "(not a)", ADSL::FOL::Not.new(:a).to_smt2_string
    assert_equal_nospace "(and (not a) (not b))", ADSL::FOL::Not.new(:a, :b).to_smt2_string
  end

  def test_and
    assert_equal "true", ADSL::FOL::And.new.to_smt2_string
    assert_equal "a", ADSL::FOL::And.new("a").to_smt2_string
    assert_equal "(and a b)", ADSL::FOL::And.new("a", "b").to_smt2_string
  end
  
  def test_or
    assert_equal "false", ADSL::FOL::Or.new.to_smt2_string
    assert_equal "a", ADSL::FOL::Or.new("a").to_smt2_string
    assert_equal "(or a b)", ADSL::FOL::Or.new("a", "b").to_smt2_string
  end
  
  def test_forall
    assert_equal "a", ADSL::FOL::ForAll.new(:a).to_smt2_string
   
    parent           = ADSL::DS::DSClass.new :name => 'parent'
    parent.sort      = Sort.new 'parentSort'
    parent.type_pred = Predicate.new 'parent', parent.sort

    child1           = ADSL::DS::DSClass.new :name => 'child1', :parents => [parent]
    child1.sort      = parent.sort
    child1.type_pred = Predicate.new 'child1', parent.sort
    
    child2           = ADSL::DS::DSClass.new :name => 'child2', :parents => [parent]
    child2.sort      = parent.sort
    child2.type_pred = Predicate.new 'child2', parent.sort
    
    assert_equal_nospace "(forall ((a parentSort)) (=> (parent a) (blah a)))", ForAll.new(parent, :a, "(blah a)").to_smt2_string

    assert_equal_nospace <<-FOL, ForAll.new(parent, :a, child1, :b, "(blah a b)").to_smt2_string
      (forall ((a parentSort) (b parentSort)) (=> (and (parent a) (child1 b)) (blah a b)))
    FOL
    
    both = ADSL::DS::TypeSig::ObjsetType.new(child1, child2)
    assert_equal_nospace <<-FOL, ForAll.new(parent, :a, both, :b, "(blah a b)").to_smt2_string
      (forall ((a parentSort) (b parentSort)) (=> (and (parent a) (child1 b) (child2 b)) (blah a b)))
    FOL
  end
  
  def test_exists
    assert_equal "a", ADSL::FOL::ForAll.new(:a).to_smt2_string
    
    parent = ADSL::DS::DSClass.new(:name => 'parent')
    parent.sort = ADSL::FOL::Sort.new 'parentSort'
    parent.type_pred = Predicate.new 'parent', parent.sort
    
    child1 = ADSL::DS::DSClass.new(:name => 'child1', :parents => [parent])
    child1.sort = parent.sort
    child1.type_pred = ADSL::FOL::Predicate.new 'child1', parent.sort
    
    child2 = ADSL::DS::DSClass.new(:name => 'child2', :parents => [parent])
    child2.sort = parent.sort
    child2.type_pred = ADSL::FOL::Predicate.new 'child2', parent.sort
    
    assert_equal_nospace "(exists ((a parentSort)) (and (parent a) (blah a)))", ADSL::FOL::Exists.new(parent, :a, "(blah a)").to_smt2_string

    assert_equal_nospace <<-FOL, ADSL::FOL::Exists.new(parent, :a, child1, :b, "(blah a b)").to_smt2_string
      (exists ((a parentSort) (b parentSort)) (and
        (parent a)
        (child1 b)
        (blah a b)
      ))
    FOL
    
    both = ADSL::DS::TypeSig::ObjsetType.new(child1, child2)
    assert_equal_nospace <<-FOL, ADSL::FOL::Exists.new(parent, :a, both, :b, "(blah a b)").to_smt2_string
      (exists ((a parentSort) (b parentSort)) (and
        (parent a)
        (child1 b) (child2 b)
        (blah a b)
      ))
    FOL
  end

  def test_equiv
    assert_equal_nospace "(= a b)", ADSL::FOL::Equiv.new(:a, :b).to_smt2_string
    assert_equal_nospace "(= a b c)", ADSL::FOL::Equiv.new(:a, :b, :c).to_smt2_string
  end
  
  def test_implies
    assert_equal_nospace "(=> a b)", ADSL::FOL::Implies.new(:a, :b).to_smt2_string
  end
  
  def test_equal
    assert_equal_nospace "(= a b)", ADSL::FOL::Equal.new(:a, :b).to_smt2_string
    assert_equal_nospace "(= a b c)", ADSL::FOL::Equal.new(:a, :b, :c).to_smt2_string
  end

  def test_xor
    assert_equal         "false", ADSL::FOL::Xor.new.to_smt2_string
    assert_equal_nospace "a", ADSL::FOL::Xor.new(:a).to_smt2_string
    assert_equal_nospace "(xor a b)", ADSL::FOL::Xor.new(:a, :b).to_smt2_string
    assert_equal_nospace "(xor a b c)", ADSL::FOL::Xor.new(:a, :b, :c).to_smt2_string
  end

  def test_if_then_else
    assert_equal_nospace "(and (=> a b) (=> (not a) c))", ADSL::FOL::IfThenElse.new(:a, :b, :c).to_smt2_string
  end

  def test_if_then_else_eq
    assert_equal_nospace "(and (= a b) (= (not a) c))", ADSL::FOL::IfThenElseEq.new(:a, :b, :c).to_smt2_string
  end

  def test_pairwise_equal
    assert_equal_nospace "true", ADSL::FOL::PairwiseEqual.new([], []).to_smt2_string
    assert_equal_nospace "(= a1 b1)", ADSL::FOL::PairwiseEqual.new([:a1], [:b1]).to_smt2_string
    assert_equal_nospace "(and (= a1 b1) (= a2 b2))", ADSL::FOL::PairwiseEqual.new([:a1, :a2], [:b1, :b2]).to_smt2_string
  end
  
  def test_pairwise_equal__implicit_lists
    assert_equal_nospace "true", ADSL::FOL::PairwiseEqual.new.to_smt2_string
    assert_equal_nospace "(= a1 b1)", ADSL::FOL::PairwiseEqual.new(:a1, :b1).to_smt2_string
    assert_equal_nospace "(and (= a1 b1) (= a2 b2))", ADSL::FOL::PairwiseEqual.new(:a1, :a2, :b1, [:b2]).to_smt2_string
  end
  
  def test_symbol__to_smt2_string
    assert_nothing_raised do
      :a.to_smt2_string
    end
    assert_equal "a", :a.to_smt2_string
    assert_equal "kme", :kme.to_smt2_string
  end
  
  def test_string__to_smt2_string
    assert_nothing_raised do
      "a".to_smt2_string
    end
    assert_equal "a", "a".to_smt2_string
    assert_equal "kme", "kme".to_smt2_string
  end
end

