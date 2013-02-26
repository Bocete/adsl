require 'util/test_helper'
require 'test/unit'

class BasicTranslationTest < Test::Unit::TestCase
  def test_blank_data_store
    adsl_assert :correct, <<-ADSL
      action blah() {}
    ADSL
  end

  def test_not_creation__nothing_exists
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {}
      invariant not exists(Class o)
    ADSL
  end
  
  def test_not_creation__something_exists
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {}
      invariant exists(Class o)
    ADSL
  end

  def test_creating_objects__something_exists
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {
        create Class
      }
      invariant exists(Class o)
    ADSL
  end
  
  def test_creating_objects__nothing_exists
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah() {
        create Class
      }
      invariant not exists(Class o)
    ADSL
  end

  def test_creating_objects__of_exact_class
    adsl_assert :correct, <<-ADSL
      class Parent {}
      class Child extends Parent {}
      action blah() {
        create Parent
      }
      invariant not exists(Child o)
    ADSL
  end

  def test_classtypes
    conjecture = FOL::ForAll.new(:o, FOL::Not.new(FOL::And.new('of_Class1_type(o)', 'of_Class2_type(o)')))
    adsl_assert :correct, <<-ADSL, :conjecture => conjecture
      class Class1 {}
      class Class2 {}
      action blah() {}
    ADSL
  end

  def test_classtypes_polymorphism__no_contradictions
    conjecture = FOL::Or.new(
      FOL::Not.new(FOL::Exists.new(:o, 'of_Parent_type(o)')),
      FOL::Not.new(FOL::Exists.new(:o, 'of_Child1_type(o)')),
      FOL::Not.new(FOL::Exists.new(:o, 'of_Child2_type(o)')),
      FOL::Not.new(FOL::Exists.new(:o, 'of_SubChild_type(o)')),
      FOL::Not.new(FOL::Exists.new(:o, 'of_Parent2_type(o)'))
    )
    adsl_assert :incorrect, <<-ADSL, :conjecture => conjecture
      class Parent {}
      class Child1 extends Parent {}
      class Child2 extends Parent {}
      class SubChild extends Child1 {}
      class Parent2 {}
      action blah() {}
    ADSL
  end

  def test_classtypes_polymorphism
    type_spec = <<-ADSL
      class Parent {}
      class Child1 extends Parent {}
      class Child2 extends Parent {}
      class SubChild extends Child1 {}
      class Parent2 {}
      action blah() {}
    ADSL

    conjecture = FOL::ForAll.new(:o, FOL::Implies.new('of_Child1_type(o)', 'of_Parent_type(o)'))
    adsl_assert :correct, type_spec, :conjecture => conjecture

    conjecture = FOL::ForAll.new(:o, FOL::Implies.new(FOL::Not.new('of_Child1_type(o)'), 'of_Parent_type(o)'))
    adsl_assert :incorrect, type_spec, :conjecture => conjecture
    
    conjecture = FOL::ForAll.new(:o, FOL::Implies.new(FOL::Not.new('of_Parent_type(o)'), FOL::And.new(
      FOL::Not.new('of_Child1_type(o)'),
      FOL::Not.new('of_Child2_type(o)')
    )))
    adsl_assert :correct, type_spec, :conjecture => conjecture

    conjecture = FOL::ForAll.new(:o, FOL::Not.new(FOL::And.new('of_Child1_type(o)', 'of_Parent2_type(o)')))
    adsl_assert :correct, type_spec, :conjecture => conjecture
    
    conjecture = FOL::ForAll.new(:o, FOL::Implies.new('of_SubChild_type(o)', 'of_Child1_type(o)'))
    adsl_assert :correct, type_spec, :conjecture => conjecture
  end

  def test_multiple_invariants
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {
        create Class
      }
      invariant true
      invariant true
      invariant exists(Class o)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah() {
        create Class
      }
      invariant true
      invariant not exists(Class o)
      invariant true
    ADSL
  end

  def test_variables__any_cardinality
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah(0+ Class var) {
        delete var
      }
      invariant exists(Class o)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah(0+ Class var) {
        delete var
      }
      invariant not exists(Class o)
    ADSL
  end

  def test_variables__cardinality_constraint
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah(0..1 Class var) {
        create Class
        delete var
      }
      invariant exists(Class o)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah(1 Class var) {
        create Class
        delete var
      }
      invariant exists(Class o)
      invariant forall(Class o1, Class o2: o1 == o2)
    ADSL
  end

  def test_no_creation_objects__forall_does_not_imply_exists
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {}
      invariant forall(Class o1, Class o2: o1 == o2)
      invariant not exists(Class o)
    ADSL
  end
  
  def test_creation__add_objects_to_max_one_object
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah() {
        create Class
      }
      invariant forall(Class o1, Class o2: o1 == o2)
    ADSL
  end

  def test_creation__class_specific
    adsl_assert :correct, <<-ADSL
      class Class {}
      class Class2 {}
      action blah() {
        create Class2
      }
      invariant forall(Class o1, Class o2: o1 == o2)
    ADSL
  end

  def test_deletion__empty_data_store
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {
        delete Class.all
      }
      invariant not exists(Class c)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah() {
        delete Class.all
      }
      invariant exists(Class c)
    ADSL
  end

  def test_deletion__create_delete_data_store
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {
        create Class
        delete Class.all
      }
      invariant not exists(Class c)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah() {
        create Class
        delete Class.all
      }
      invariant exists(Class c)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah() {
        delete Class.all
        create Class
      }
      invariant not exists(Class c)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {
        delete Class.all
        create Class
      }
      invariant exists(Class c)
    ADSL
  end

  def test_subset__invariant
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {}
      invariant subset(Class.all) in Class.all
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah() {}
      invariant subset(Class.all) in subset(Class.all)
    ADSL
  end

  def test_variable__basic
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah() {
        a = Class.all
        delete a
      }
      invariant exists(Class c)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {
        a = Class.all
        delete a
      }
      invariant not exists(Class c)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah() {
        a = subset(Class.all)
        delete a
      }
      invariant exists(Class c)
    ADSL
  end

  def test_create__assignment
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {
        a = create Class
        delete a
      }
      invariant not exists(Class c)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah() {
        a = create Class
        b = create Class
        delete a
      }
      invariant not exists(Class c)
    ADSL
  end

  def test_oneof__is_one_object
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {
        create Class
        delete oneof(Class.all)
      }
      invariant exists(Class c)
    ADSL
  end
  
  def test_is_empty
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {
        delete Class.all
      }
      invariant empty(Class.all)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {}
      invariant empty(Class.all)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah() {
        create Class
      }
      invariant empty(Class.all)
    ADSL
  end

  def test_deref
    adsl_assert :correct, <<-ADSL
      class Class { 0+ Class2 rel }
      class Class2 {}
      action blah() {
        delete Class.all.rel
      }
      invariant forall(Class o: empty(o.rel))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class { 0+ Class2 rel }
      class Class2 {}
      action blah() {
        delete Class.all.rel
      }
      invariant not forall(Class o: empty(o.rel))
    ADSL
  end

  def test_deref_polymorphic
    adsl_assert :incorrect, <<-ADSL
      class Parent { 0+ Parent rel }
      class Child extends Parent {}
      action blah() {
        delete Parent.all.rel
      }
      invariant exists(Child o: not empty(o.rel))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Parent { 0+ Parent rel }
      class Child extends Parent {}
      action blah() {
        delete Child.all.rel
      }
      invariant exists(Child o: not empty(o.rel))
    ADSL
    adsl_assert :correct, <<-ADSL
      class Parent { 0+ Parent rel }
      class Child extends Parent {}
      action blah() {
        delete Child.all.rel
      }
      invariant exists(Parent o: not empty(o.rel)) and not exists(Child o: not empty(o.rel))
    ADSL
  end
  
  def test__create_ref
    adsl_assert :correct, <<-ADSL
      class Class{ 0+ Class rel }
      action blah() {
        v1 = oneof (Class.all)
        v2 = oneof (Class.all)
        v1.rel += v2
      }
      invariant exists(Class o: not empty(o.rel))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class{ 0+ Class rel }
      action blah() {
        v1 = oneof (Class.all)
        v2 = oneof (Class.all)
        v1.rel += v2
      }
      invariant forall(Class o: empty(o.rel))
    ADSL
  end

  def test__create_ref_clique
    adsl_assert :correct, <<-adsl
      class Class{ 0+ Class rel }
      action blah() {
        Class.all.rel += Class.all
      }
      invariant forall(Class v: v.rel == Class.all)
    adsl

    conjecture = <<-SPASS
      forall( [o1, o2], implies(
        and(exists_finally(o1), exists_finally(o2), is_object(o1), is_object(o2)),
        exists( [r], and(left_link_Class_rel(r, o1), right_link_Class_rel(r, o2)))
      ))
    SPASS
    adsl_assert(:correct, <<-adsl, :conjecture => conjecture)
      class Class{ 0+ Class rel }
      action blah() {
        Class.all.rel += Class.all
      }
      invariant forall(Class v: v.rel == Class.all)
    adsl
    
    adsl_assert :incorrect, <<-ADSL
      class Class{ 0+ Class rel }
      action blah() {
        Class.all.rel += Class.all
      }
      invariant !forall(Class v: v.rel == Class.all)
    ADSL
  end

  def test__no_refs_on_new_object
    adsl_assert :correct, <<-ADSL
      class Class { 0+ Class rel }
      action blah() {
        create Class
      }
      invariant exists(Class o: empty(o.rel))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class { 0+ Class rel }
      action blah() {
        create Class
      }
      invariant forall(Class o: not empty(o.rel))
    ADSL
  end

  def test__delete_removes_all_refs
    adsl_assert :correct, <<-ADSL
      class Class { 0+ Class rel }
      action blah() {
        delete Class.all
        a = create Class
        b = create Class
        a.rel += b
        delete a
      }
      invariant forall(Class a: empty(a.rel))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class { 0+ Class rel }
      action blah() {
        delete Class.all
        a = create Class
        b = create Class
        a.rel += b
        delete a
      }
      invariant !forall(Class a: empty(a.rel))
    ADSL
  end

  def test__delete_ref
    adsl_assert :correct, <<-ADSL
      class Class { 0+ Class rel }
      action blah() {
        Class.all.rel -= Class.all
      }
      invariant forall(Class a: empty(a.rel))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class { 0+ Class rel }
      action blah() {
        Class.all.rel -= Class.all
      }
      invariant exists(Class a: not empty(a.rel))
    ADSL
  end

  def test_ref_cardinality__at_least_one
    conjecture = <<-SPASS
      forall( [o], implies(of_Class_type(o), exists([r], left_link_Class_rel(r, o))))
    SPASS
    adsl_assert :correct, <<-ADSL, :conjecture => conjecture
      class Class { 1+ Class rel }
      action blah() {}
    ADSL
    adsl_assert :incorrect, <<-ADSL, :conjecture => "not(#{conjecture})"
      class Class { 1+ Class rel }
      action blah() {}
    ADSL
  end

  def test_ref_cardinality__at_most_one
    conjecture = <<-SPASS
      exists( [o, r1, r2], and(of_Class_type(o), left_link_Class_rel(r1, o), left_link_Class_rel(r2, o), not(equal(r1, r2))))
    SPASS
    adsl_assert :correct, <<-ADSL, :conjecture => "not(#{conjecture})"
      class Class { 0..1 Class rel }
      action blah() {}
    ADSL
    adsl_assert :incorrect, <<-ADSL, :conjecture => conjecture
      class Class { 0..1 Class rel }
      action blah() {}
    ADSL
  end

  def test__inverse_relations
    adsl_assert :correct, <<-ADSL
      class Class1 { 1 Class2 rel }
      class Class2 { 1 Class1 rel inverseof rel }
      action blah() {}
      invariant forall(Class1 a: a == a.rel.rel)
    ADSL
  end
end
