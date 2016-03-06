require 'adsl/util/test_helper'
require 'adsl/fol/first_order_logic'
require 'adsl/prover/spass/fol_extensions'
require 'adsl/ds/data_store_spec'
require 'adsl/ds/fol_translation/ds_extensions'

class ADSL::Prover::SpassFolExtensionsTest < ActiveSupport::TestCase
  include ADSL::FOL
  
  def test__theorem__spass_wrap
    theorem = ADSL::FOL::Theorem.new
    assert_equal "", theorem.spass_wrap("blah%sblah", "")
    assert_equal "blahasdblah", theorem.spass_wrap("blah%sblah", "asd")
  end

  def test__theorem__spass_list_of
    theorem = ADSL::FOL::Theorem.new
    assert_equal "", theorem.spass_list_of(:symbol, [])
    assert_equal "", theorem.spass_list_of(:symbol, [], [])
    assert_equal_nospace <<-SPASS, theorem.spass_list_of(:symbol, "blah", "kme")
    list_of_symbol.
      blah
      kme
    end_of_list.
    SPASS
  end

  def test__theorem__nullary_predicates
    theorem = Theorem.new
    preds = 2.times.map{ |i| Predicate.new "predname#{i+1}" }
    theorem.predicates += preds
    theorem.axioms << And.new(*preds.map{ |p| p[] })
    string = theorem.to_spass_string
    assert_include_nospace string, "predicates[(predname1, 0), (predname2, 0)]"
    assert_include_nospace string, "formula(and(predname1, predname2))."
  end

  def test__theorem__nullary_functions
    theorem = Theorem.new
    sort = Sort.new 'somename'
    theorem.sorts << sort
    functions = 2.times.map{ |i| Function.new sort, "predname#{i+1}" }
    theorem.functions += functions
    theorem.axioms << Equal.new(*functions.map{ |p| p[] })
    string = theorem.to_spass_string
    assert_include_nospace string, "functions[(predname1, 0), (predname2, 0)]"
    assert_include_nospace string, "formula(equal(predname1, predname2))."
  end

  def test_literals
    assert_equal "true", true.to_spass_string
    assert_equal "false", false.to_spass_string
    assert_equal "symbol_here", :symbol_here.to_spass_string
    assert_equal "sometext", "sometext".to_spass_string
  end

  def test_not
    assert_equal "not(a)", ADSL::FOL::Not.new(:a).to_spass_string
    assert_equal_nospace "and(not(a), not(b))", ADSL::FOL::Not.new(:a, :b).to_spass_string
  end

  def test_and
    assert_equal "true", ADSL::FOL::And.new.to_spass_string
    assert_equal "a", ADSL::FOL::And.new("a").to_spass_string
    assert_equal "and(a, b)", ADSL::FOL::And.new("a", "b").to_spass_string
  end
  
  def test_or
    assert_equal "false", ADSL::FOL::Or.new.to_spass_string
    assert_equal "a", ADSL::FOL::Or.new("a").to_spass_string
    assert_equal "or(a, b)", ADSL::FOL::Or.new("a", "b").to_spass_string
  end
  
  def test_forall
    assert_equal "a", ADSL::FOL::ForAll.new(:a).to_spass_string
   
    parent = ADSL::DS::DSClass.new(:name => 'parent')
    parent.sort = ADSL::FOL::Sort.new 'parentSort'
    parent.type_pred = Predicate.new 'parent', parent.sort

    child1 = ADSL::DS::DSClass.new(:name => 'child1', :parents => [parent])
    child1.sort = parent.sort
    child1.type_pred = ADSL::FOL::Predicate.new 'child1', parent.sort
    
    child2 = ADSL::DS::DSClass.new(:name => 'child2', :parents => [parent])
    child2.sort = parent.sort
    child2.type_pred = ADSL::FOL::Predicate.new 'child2', parent.sort
    
    assert_equal_nospace "forall([parentSort(a)], implies(parent(a), blah(a)))", ADSL::FOL::ForAll.new(parent, :a, "blah(a)").to_spass_string

    assert_equal_nospace <<-FOL, ADSL::FOL::ForAll.new(parent, :a, child1, :b, "blah(a, b)").to_spass_string
      forall( [parentSort(a), parentSort(b)], implies(and(parent(a), child1(b)), blah(a, b)))
    FOL
    
    both = ADSL::DS::TypeSig::ObjsetType.new(child1, child2)
    assert_equal_nospace <<-FOL, ADSL::FOL::ForAll.new(parent, :a, both, :b, "blah(a, b)").to_spass_string
      forall( [parentSort(a), parentSort(b)], implies(and(parent(a), child1(b), child2(b)), blah(a, b)))
    FOL
  end
  
  def test_exists
    assert_equal "a", ADSL::FOL::ForAll.new(:a).to_spass_string
    
    parent = ADSL::DS::DSClass.new(:name => 'parent')
    parent.sort = ADSL::FOL::Sort.new 'parentSort'
    parent.type_pred = Predicate.new 'parent', parent.sort
    
    child1 = ADSL::DS::DSClass.new(:name => 'child1', :parents => [parent])
    child1.sort = parent.sort
    child1.type_pred = ADSL::FOL::Predicate.new 'child1', parent.sort
    
    child2 = ADSL::DS::DSClass.new(:name => 'child2', :parents => [parent])
    child2.sort = parent.sort
    child2.type_pred = ADSL::FOL::Predicate.new 'child2', parent.sort
    
    assert_equal_nospace "exists([parentSort(a)], and(parent(a), blah(a)))", ADSL::FOL::Exists.new(parent, :a, "blah(a)").to_spass_string

    assert_equal_nospace <<-FOL, ADSL::FOL::Exists.new(parent, :a, child1, :b, "blah(a, b)").to_spass_string
      exists( [parentSort(a), parentSort(b)], and(
        parent(a),
        child1(b),
        blah(a, b)
      ))
    FOL
    
    both = ADSL::DS::TypeSig::ObjsetType.new(child1, child2)
    assert_equal_nospace <<-FOL, ADSL::FOL::Exists.new(parent, :a, both, :b, "blah(a, b)").to_spass_string
      exists( [parentSort(a), parentSort(b)], and(
        parent(a),
        child1(b), child2(b),
        blah(a, b)
      ))
    FOL
  end

  def test_equiv
    assert_equal_nospace "equiv(a, b)", ADSL::FOL::Equiv.new(:a, :b).to_spass_string
    assert_equal_nospace "and(equiv(a, b), equiv(b, c))", ADSL::FOL::Equiv.new(:a, :b, :c).to_spass_string
  end
  
  def test_implies
    assert_equal_nospace "implies(a, b)", ADSL::FOL::Implies.new(:a, :b).to_spass_string
  end
  
  def test_equal
    assert_equal_nospace "equal(a, b)", ADSL::FOL::Equal.new(:a, :b).to_spass_string
    assert_equal_nospace "and(equal(a, b), equal(b, c))", ADSL::FOL::Equal.new(:a, :b, :c).to_spass_string
  end

  def test_xor
    assert_equal         "false", ADSL::FOL::Xor.new.to_spass_string
    assert_equal_nospace "a", ADSL::FOL::Xor.new(:a).to_spass_string
    assert_equal_nospace "equiv(not(a), b)", ADSL::FOL::Xor.new(:a, :b).to_spass_string
    assert_equal_nospace <<-FOL, ADSL::FOL::Xor.new(:a, :b, :c).to_spass_string
     and(
       or(a, b, c),
       implies(a, and(not(b), not(c))),
       implies(b, and(not(a), not(c))),
       implies(c, and(not(a), not(b)))
     )
    FOL
  end

  def test_if_then_else
    assert_equal_nospace "and(implies(a, b), implies(not(a), c))", ADSL::FOL::IfThenElse.new(:a, :b, :c).to_spass_string
  end

  def test_if_then_else_eq
    assert_equal_nospace "and(equiv(a, b), equiv(not(a), c))", ADSL::FOL::IfThenElseEq.new(:a, :b, :c).to_spass_string
  end

  def test_pairwise_equal
    assert_equal_nospace "true", ADSL::FOL::PairwiseEqual.new([], []).to_spass_string
    assert_equal_nospace "equal(a1, b1)", ADSL::FOL::PairwiseEqual.new([:a1], [:b1]).to_spass_string
    assert_equal_nospace "and(equal(a1, b1), equal(a2, b2))", ADSL::FOL::PairwiseEqual.new([:a1, :a2], [:b1, :b2]).to_spass_string
  end
  
  def test_pairwise_equal__implicit_lists
    assert_equal_nospace "true", ADSL::FOL::PairwiseEqual.new.to_spass_string
    assert_equal_nospace "equal(a1, b1)", ADSL::FOL::PairwiseEqual.new(:a1, :b1).to_spass_string
    assert_equal_nospace "and(equal(a1, b1), equal(a2, b2))", ADSL::FOL::PairwiseEqual.new(:a1, :a2, :b1, [:b2]).to_spass_string
  end
  
  def test_symbol__to_spass_string
    assert_nothing_raised do
      :a.to_spass_string
    end
    assert_equal "a", :a.to_spass_string
    assert_equal "kme", :kme.to_spass_string
  end
  
  def test_string__to_spass_string
    assert_nothing_raised do
      "a".to_spass_string
    end
    assert_equal "a", "a".to_spass_string
    assert_equal "kme", "kme".to_spass_string
  end
end

