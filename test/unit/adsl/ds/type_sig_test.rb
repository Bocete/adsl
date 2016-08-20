require 'adsl/util/test_helper'
require 'adsl/ds/data_store_spec'
require 'adsl/ds/type_sig'

class ADSL::DS::TypeSigTest < ActiveSupport::TestCase
  include ADSL::DS::TypeSig
  
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

    assert_equal parent.to_sig, child1.to_sig & child2.to_sig
    assert_equal parent.to_sig, child1.to_sig & parent.to_sig

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

    join = child1.to_sig & child2.to_sig

    assert join.classes == Set[parent1, parent2]
  end

  def test_type_sig__is_unknown_type?
    klass = ADSL::DS::DSClass.new :name => 'klass'
    assert_false ADSL::DS::TypeSig::ObjsetType.new(klass).is_unknown_type?

    assert ADSL::DS::TypeSig::UNKNOWN.is_unknown_type?

#    assert_false ADSL::DS::TypeSig::BasicType::INT.is_unknown_type?
    assert_false ADSL::DS::TypeSig::BasicType::BOOL.is_unknown_type?
  end

  def test_type_sig__is_bool_type?
    klass = ADSL::DS::DSClass.new :name => 'klass'
    assert_false ADSL::DS::TypeSig::ObjsetType.new(klass).is_bool_type?

    assert_false ADSL::DS::TypeSig::UNKNOWN.is_bool_type?

#    assert_false ADSL::DS::TypeSig::BasicType::INT.is_bool_type?
    assert       ADSL::DS::TypeSig::BasicType::BOOL.is_bool_type?
  end

  def test_type_sig__is_objset_type?
    klass = ADSL::DS::DSClass.new :name => 'klass'
    assert ADSL::DS::TypeSig::ObjsetType.new(klass).is_objset_type?

    assert ADSL::DS::DSEmptyObjset.new.type_sig.is_objset_type?

    assert_false ADSL::DS::TypeSig::UNKNOWN.is_objset_type?

#    assert_false ADSL::DS::TypeSig::BasicType::INT.is_objset_type?
    assert_false ADSL::DS::TypeSig::BasicType::BOOL.is_objset_type?
  end
end
