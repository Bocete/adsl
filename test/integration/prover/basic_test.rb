require 'adsl/util/test_helper'

class BasicTest < ActiveSupport::TestCase
  include ADSL::FOL

  def test_blank_data_store
    adsl_assert :correct, <<-ADSL
      action blah {}
    ADSL
  end

  def test_asterisk_nondeterministic
    adsl_assert :incorrect, <<-ADSL
      action blah {}
      invariant *
    ADSL
  end

  def test_not_creation__nothing_exists
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {}
      invariant not exists(Class o)
    ADSL
  end
  
  def test_not_creation__something_exists
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {}
      invariant exists(Class o)
    ADSL
  end

  def test_creating_objects__something_exists
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {
        create(Class)
      }
      invariant exists(Class o)
    ADSL
  end
  
  def test_creating_objects__nothing_exists
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah {
        create(Class)
      }
      invariant not exists(Class o)
    ADSL
  end

  def test_creating_objects__of_exact_class
    adsl_assert :correct, <<-ADSL
      class Parent {}
      class Child extends Parent {}
      action blah {
        create(Parent)
      }
      invariant not exists(Child o)
    ADSL
  end

  def test_classtypes_polymorphism__no_contradictions
    sort = Sort.new :ParentSort
    sort2 = Sort.new :Parent2Sort
    
    preds = {}
    [:Child1, :Child2, :Parent, :SubChild].each{ |s| preds[s] = Predicate.new s, sort }
    preds[:Parent2] = Predicate.new 'Parent2', sort2
    
    conjecture = Or.new(
      Not.new(Exists.new(sort, :o, preds[:Parent][:o])),
      Not.new(Exists.new(sort, :o, preds[:Child1][:o])),
      Not.new(Exists.new(sort, :o, preds[:Child2][:o])),
      Not.new(Exists.new(sort, :o, preds[:SubChild][:o])),
      Not.new(Exists.new(sort2, :o, preds[:Parent2][:o]))
    )
    adsl_assert :incorrect, <<-ADSL, :conjecture => conjecture
      class Parent {}
      class Child1 extends Parent {}
      class Child2 extends Parent {}
      class SubChild extends Child1 {}
      class Parent2 {}
      action blah {}
    ADSL
  end

  def test_classtypes_polymorphism
    type_spec = <<-ADSL
      class Parent {}
      class Child1 extends Parent {}
      class Child2 extends Parent {}
      class SubChild extends Child1 {}
      class Parent2 {}
      action blah {}
    ADSL

    sort = Sort.new :ParentSort
    sort2 = Sort.new :Parent2Sort
    preds = {}
    [:Child1, :Child2, :Parent, :SubChild].each{ |s| preds[s] = Predicate.new s, sort }
    preds[:Parent2] = Predicate.new 'Parent2', sort2
    conjecture = ForAll.new(sort, :o, Implies.new(preds[:Child1][:o], preds[:Parent][:o]))
    adsl_assert :correct, type_spec, :conjecture => conjecture

    conjecture = ForAll.new(sort, :o, Implies.new(Not.new(preds[:Child1][:o]), preds[:Parent][:o]))
    adsl_assert :incorrect, type_spec, :conjecture => conjecture
    
    conjecture = ForAll.new(sort, :o, Implies.new(Not.new(preds[:Parent][:o]), And.new(
      Not.new(preds[:Child1][:o]),
      Not.new(preds[:Child2][:o])
    )))
    adsl_assert :correct, type_spec, :conjecture => conjecture

    conjecture = ForAll.new(sort, :o, Implies.new(preds[:SubChild][:o], preds[:Child1][:o]))
    adsl_assert :correct, type_spec, :conjecture => conjecture
  end

  def test_multiple_invariants
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {
        create(Class)
      }
      invariant true
      invariant true
      invariant exists(Class o)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah {
        create(Class)
      }
      invariant true
      invariant not exists(Class o)
      invariant true
    ADSL
  end

  def test_variables__any_cardinality
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah {
        var = subset(allof(Class))
        delete var
      }
      invariant exists(Class o)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {
        var = subset(allof(Class))
        delete var
      }
      invariant not exists(Class o)
    ADSL
  end

  def test_variables__cardinality_constraint
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {
        var = subset(allof(Class))
        create(Class)
        delete var
      }
      invariant exists(Class o)
    ADSL
  end

  def test_no_creation_objects__forall_does_not_imply_exists
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {}
      invariant forall(Class o1, Class o2: o1 == o2)
      invariant not exists(Class o)
    ADSL
  end
  
  def test_creation__add_objects_to_max_one_object
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah {
        create(Class)
      }
      invariant forall(Class o1, Class o2: o1 == o2)
    ADSL
  end
  
  def test_creation__add_two_objects_adds_two_objects
    adsl_assert :incorrect, <<-ADSL
      class Class { 0+ Class relation }
      action blah {
        create(Class).relation += create(Class)
        delete oneof(allof(Class))
      }
      invariant forall(Class o1, Class o2: o1 == o2)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class { 0+ Class relation }
      action blah {
        create(Class).relation += create(Class)
        delete oneof(allof(Class))
        delete oneof(allof(Class))
      }
      invariant forall(Class o1, Class o2: o1 == o2)
    ADSL
  end

  def test_creation__class_specific
    adsl_assert :correct, <<-ADSL
      class Class {}
      class Class2 {}
      action blah {
        create(Class2)
      }
      invariant forall(Class o1, Class o2: o1 == o2)
    ADSL
  end

  def test_deletion__empty_data_store
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {
        delete allof(Class)
      }
      invariant not exists(Class c)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah {
        delete allof(Class)
      }
      invariant exists(Class c)
    ADSL
  end

  def test_deletion__create_delete_data_store
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {
        create(Class)
        delete allof(Class)
      }
      invariant not exists(Class c)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah {
        create(Class)
        delete allof(Class)
      }
      invariant exists(Class c)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah {
        delete allof(Class)
        create(Class)
      }
      invariant not exists(Class c)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {
        delete allof(Class)
        create(Class)
      }
      invariant exists(Class c)
    ADSL
  end

  def test_subset__invariant
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {}
      invariant (subset allof(Class)) in allof(Class)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah {}
      invariant (subset allof(Class)) in subset(allof(Class))
    ADSL
  end

  def test_variable__basic
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah {
        a = allof(Class)
        delete a
      }
      invariant exists(Class c)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {
        a = allof(Class)
        delete a
      }
      invariant not exists(Class c)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah {
        a = subset(allof(Class))
        delete a
      }
      invariant exists(Class c)
    ADSL
  end

  def test_create__assignment
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {
        a = create(Class)
        delete a
      }
      invariant not exists(Class c)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah {
        a = create(Class)
        b = create(Class)
        delete a
      }
      invariant not exists(Class c)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class1 {
        0..1 Class2 rel
      }
      class Class2 {
        0..1 Class1 rel inverseof rel
      }
      action blah {
        o = oneof(allof(Class1))
        o.rel = create(Class2)
      }
      invariant exists(Class1 o: not isempty(o.rel))
    ADSL
  end

  def test_assignment__reassign
    adsl_assert :correct, <<-ADSL
      class Class1 {
        0..1 Class2 rel
      }
      class Class2 {
        0..1 Class1 rel inverseof rel
      }
      action blah {
        o = oneof(allof(Class1))
        o.rel = create(Class2)
        o.rel = create(Class2)
        o.rel = create(Class2)
      }
      invariant exists(Class1 o: not isempty(o.rel))
    ADSL
    adsl_assert :incorrect, <<-ADSL, :conjecture => 'false'
      class Class1 {
        0..1 Class2 rel
      }
      class Class2 {
        0..1 Class1 rel inverseof rel
      }
      action blah {
        o = oneof(allof(Class1))
        o.rel = create(Class2)
        o.rel = create(Class2)
        o.rel = create(Class2)
      }
      invariant exists(Class1 o: not isempty(o.rel))
    ADSL
  end

  def test_assignment__as_objset
    adsl_assert :correct, <<-ADSL
      class Class {
        0+ Class rel
      }
      action blah {
        create(Class)
        create(Class)
        create(Class)
        a = b = c = allof(Class)
        delete a
        b.rel += c
      }
      invariant not exists(Class o)
    ADSL
  end

  def test_oneof__is_one_object
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {
        create(Class)
        delete oneof(allof(Class))
      }
      invariant exists(Class c)
    ADSL
  end

  def test_forced_one_of__is_forced
    # the following action should be contradictory
    adsl_assert :correct, <<-ADSL, :conjecture => false
      class Class {}
      action blah {
        delete allof(Class)
        a = oneof(allof(Class))
      }
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class {
        0+ Class2 rel
      }
      class Class2 {}
      action blah {
        o1 = oneof(allof(Class))
        o2 = oneof(allof(Class2))
        o1.rel += o2
      }
      invariant exists(Class o)
    ADSL
  end
  
  def test_is_empty
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {
        delete allof(Class)
      }
      invariant isempty(allof(Class))
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {}
      invariant isempty(allof(Class))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah {
        create(Class)
      }
      invariant isempty(allof(Class))
    ADSL
  end

  def test_deref
    adsl_assert :correct, <<-ADSL
      class Class { 0+ Class2 rel }
      class Class2 {}
      action blah {
        delete allof(Class).rel
      }
      invariant forall(Class o: isempty(o.rel))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class { 0+ Class2 rel }
      class Class2 {}
      action blah {
        delete allof(Class).rel
      }
      invariant not forall(Class o: isempty(o.rel))
    ADSL
  end

  def test_deref_polymorphic
    adsl_assert :incorrect, <<-ADSL
      class Parent { 0+ Parent rel }
      class Child extends Parent {}
      action blah {
        delete allof(Parent).rel
      }
      invariant exists(Child o: not isempty(o.rel))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Parent { 0+ Parent rel }
      class Child extends Parent {}
      action blah {
        delete allof(Child).rel
      }
      invariant exists(Child o: not isempty(o.rel))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Parent { 0+ Parent rel }
      class Child extends Parent {}
      action blah {
        delete allof(Child).rel
      }
      invariant exists(Parent o: not isempty(o.rel))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Parent { 0+ Parent rel }
      class Child extends Parent {}
      action blah {
        delete allof(Child).rel
      }
      invariant exists(Parent o: not isempty(o.rel))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Parent { 0+ Parent rel }
      class Child extends Parent {}
      action blah {
        delete allof(Child).rel
      }
      invariant exists(Child o: not isempty(o.rel))
    ADSL
  end
  
  def test__create_ref
    adsl_assert :correct, <<-ADSL
      class Class{ 0+ Class rel }
      action blah {
        v1 = oneof(allof(Class))
        v2 = oneof(allof(Class))
        v1.rel += v2
      }
      invariant exists(Class o: not isempty(o.rel))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class{ 0+ Class rel }
      action blah {
        v1 = oneof(allof(Class))
        v2 = oneof(allof(Class))
        v1.rel += v2
      }
      invariant forall(Class o: isempty(o.rel))
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class1 {
        0+ Class2 rel
      }
      class Class2 {}
      action blah {
        o1 = create(Class1)
        o2 = create(Class2)
        o1.rel += o2
      }
      invariant forall(Class1 o: not isempty(o.rel))
    ADSL
  end

  def test__create_ref_clique
    adsl_assert :correct, <<-ADSL
      class Class{ 0+ Class rel }
      action blah {
        allof(Class).rel += allof(Class)
      }
      invariant forall(Class v: v.rel == allof(Class))
    ADSL
    
    adsl_assert :correct, <<-ADSL
      class Class{ 0+ Class rel }
      action blah {
        allof(Class).rel -= allof(Class)
      }
      invariant !forall(Class v: v.rel == allof(Class))
    ADSL
  end

  def test__no_refs_on_new_object
    adsl_assert :correct, <<-ADSL
      class Class { 0+ Class rel }
      action blah {
        create(Class)
      }
      invariant exists(Class o: isempty(o.rel))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class { 0+ Class rel }
      action blah {
        create(Class)
      }
      invariant forall(Class o: not isempty(o.rel))
    ADSL
  end

  def test__delete_removes_all_refs
    # adsl_assert :correct, <<-ADSL
    #   class Class { 0+ Class rel }
    #   action blah {
    #     delete allof(Class)
    #     a = create(Class)
    #     b = create(Class)
    #     a.rel += b
    #     delete a
    #   }
    #   invariant forall(Class a: isempty(a.rel))
    # ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class { 0+ Class rel }
      action blah {
        delete Class
        a = create Class
        b = create Class
        a.rel += b
        delete a
      }
      invariant !forall(Class a: isempty(a.rel))
    ADSL
  end

  def test__delete_ref
    adsl_assert :correct, <<-ADSL
      class Class { 0+ Class rel }
      action blah {
        allof(Class).rel -= allof(Class)
      }
      invariant forall(Class a: isempty(a.rel))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class { 0+ Class rel }
      action blah {
        allof(Class).rel -= allof(Class)
      }
      invariant exists(Class a: not isempty(a.rel))
    ADSL
  end

  def test_ref_cardinality__at_least_one
    adsl_assert :correct, <<-ADSL, :conjecture => false
      class Class { 1+ Class rel }
      action blah {
        create(Class)
      }
    ADSL
  end

  def test_ref_cardinality__at_most_one
    adsl_assert :correct, <<-ADSL, :conjecture => false
      class Class { 0..1 Class rel }
      action blah {
        o = oneof(allof(Class))
        o.rel += create(Class)
        o.rel += create(Class)
      }
    ADSL
  end

  def test__inverse_relations
    adsl_assert :correct, <<-ADSL
      class Class1 { 1 Class2 rel }
      class Class2 { 1 Class1 rel inverseof rel }
      action blah {}
      invariant forall(Class1 a: a == a.rel.rel)
    ADSL
  end

  def test__rule_booleans
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah {
        delete allof(Class)
      }
      invariant exists(Class c)
      rule true
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {
        delete allof(Class)
      }
      invariant exists(Class c)
      rule false
    ADSL
  end

  def test__delete_subset
    adsl_assert :correct, <<-ADSL
      class Class {
        0+ Class2 ref
      }
      class Class2 {}
      action blah {
        delete(subset(Class))
      }
      invariant forall(Class c: not isempty(c.ref))
    ADSL
  end
end
