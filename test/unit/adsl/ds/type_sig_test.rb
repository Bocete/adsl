require 'test/unit'
require 'adsl/ds/type_sig'
require 'pp'

class ADSL::DS::TypeSigTest < Test::Unit::TestCase
  def test_class__superclass_of
    parent = ADSL::DS::DSClass.new :name => 'parent'
    child1 = ADSL::DS::DSClass.new :name => 'child1', :parents => Set[parent]
    child2 = ADSL::DS::DSClass.new :name => 'child2', :parents => Set[parent]
    grandchild = ADSL::DS::DSClass.new :name => 'grandchild', :parents => Set[child1]
    
    assert parent.superclass_of? parent
    assert parent.superclass_of? child1
    assert parent.superclass_of? child2
    assert parent.superclass_of? grandchild

    assert !child1.superclass_of?(parent)
    assert !child2.superclass_of?(parent)
    assert !grandchild.superclass_of?(parent)

    assert child1.superclass_of? child1
    assert child1.superclass_of? grandchild
    assert !child1.superclass_of?(child2)

    assert !child2.superclass_of?(child1)
    assert !child2.superclass_of?(grandchild)
  end

  def test_type_sig__comparisons
    parent = ADSL::DS::DSClass.new :name => 'parent'
    child1 = ADSL::DS::DSClass.new :name => 'child1', :parents => Set[parent]
    child2 = ADSL::DS::DSClass.new :name => 'child2', :parents => Set[parent]

    assert_equal     parent.to_sig, parent.to_sig
    assert_equal     child1.to_sig, child1.to_sig
    assert_not_equal child1.to_sig, child2.to_sig

    assert_equal parent.to_sig, child1.to_sig.join(child2.to_sig)
    assert_equal parent.to_sig, child1.to_sig.join(parent.to_sig)

    assert parent.to_sig >= child1.to_sig
    assert parent.to_sig > child1.to_sig
    assert parent.to_sig > child2.to_sig
    assert_false child1.to_sig >= child2.to_sig
    assert_false child1.to_sig <= child2.to_sig
  end

  def test_type_sig__two_parent_join
    parent1 = ADSL::DS::DSClass.new :name => 'parent1'
    parent2 = ADSL::DS::DSClass.new :name => 'parent2'
    child1 = ADSL::DS::DSClass.new :name => 'child1', :parents => Set[parent1, parent2]
    child2 = ADSL::DS::DSClass.new :name => 'child2', :parents => Set[parent1, parent2]
    subchild = ADSL::DS::DSClass.new :name => 'subchild', :parents => Set[child1, child2]

    join = child1.to_sig.join child2.to_sig

    assert join.classes == Set[parent1, parent2]
  end

  def test_type_sig__randoms
    klass = ADSL::DS::DSClass.new :name => 'klass'
    
    random1 = ADSL::DS::TypeSig.random
    random2 = ADSL::DS::TypeSig.random
    non_random1 = ADSL::DS::TypeSig::ObjsetType.new klass
    non_random2 = ADSL::DS::TypeSig::ObjsetType.new klass

    assert_equal non_random1, non_random2
    assert_not_equal non_random1, random1
    assert_not_equal random1, random2
  end
end
