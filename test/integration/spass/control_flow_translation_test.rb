require 'adsl/util/test_helper'
require 'test/unit'

class ControlFlowTranslationTest < Test::Unit::TestCase
  def test_either__blank
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah() {
        either {} or {}
      }
      invariant exists(Class o)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah() {
        either {} or {}
      }
      invariant not exists(Class o)
    ADSL
  end
  
  def test_either__doesnt_break_others
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah() {
        create(Class)
        either {} or {}
      }
      invariant exists(Class o)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah() {
        either {} or {}
        create(Class)
      }
      invariant exists(Class o)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah() {
        either {} or {}
        create(Class)
      }
      invariant not exists(Class o)
    ADSL
  end

  def test_either__may_delete_an_object
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah() {
        either {
          delete allof(Class)
        } or {}
      }
      invariant exists(Class o)
    ADSL
  end

  def test_either__blank_is_noop
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah() {
        create(Class)
        either {} or {} or {} or {}
      }
      invariant not exists(Class c)
    ADSL
  end

  def test_either__may_delete_and_create_an_object
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah() {
        either {
          delete allof(Class)
          create(Class)
        } or {}
      }
      invariant not exists(Class o)
    ADSL
  end

  def test_either__branches_symmetrical
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah() {
        either {
          delete allof(Class)
          create(Class)
        } or {}
      }
      invariant not exists(Class o)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah() {
        either {} or {
          delete allof(Class)
          create(Class)
        }
      }
      invariant not exists(Class o)
    ADSL
  end

  def test_either__false_dichotomy
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah() {
        either {
          create(Class)
        } or {
          create(Class)
        }
      }
      invariant not exists(Class o)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah() {
        either {
          create(Class)
        } or {
          create(Class)
        }
      }
      invariant exists(Class o)
    ADSL
  end

  def test_either__multiple_options
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {
        either {} or {
          delete allof(Class)
          create(Class)
        } or {
          create(Class)
        }
      }
      invariant exists(Class o)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah() {
        either {
          create(Class)
        } or {
          delete allof(Class)
          create(Class)
        } or {
          delete allof(Class)
        }
      }
      invariant exists(Class o)
    ADSL
  end
  
  def test_either__delete_and_create_an_object
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah() {
        either {
          delete allof(Class)
          create(Class)
        } or {
          delete allof(Class)
          create(Class)
        }
      }
      invariant forall(Class a, Class b: a == b)
    ADSL
  end

  def test_either__variables
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah() {
        either {
          a = create(Class)
          delete a
        } or {
          create(Class)
        }
      }
      invariant forall(Class a, Class b: a == b)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah() {
        a = create(Class)
        either {
          delete a
        } or {
        }
      }
      invariant not exists(Class a)
    ADSL
  end

  def test_either__lambda
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah() {
        a = create(Class)
        either {
        } or {
          delete a
        }
      }
      invariant forall(Class a, Class b: a == b)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah() {
        a = create(Class)
        either {
          delete a
        } or {
        }
      }
      invariant forall(Class a, Class b: a == b)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah() {
        a = create(Class)
        either {
          delete a
        } or {
          delete a
        }
      }
      invariant not exists(Class a)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah() {
        a = create(Class)
        either {
          delete a
        } or {
          delete a
        }
      }
      invariant forall(Class a, Class b: a == b)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah() {
        a = allof(Class)
        either {
          a = create(Class)
        } or {
          a = create(Class)
          a = oneof(allof(Class))
        } or {
          a = create(Class)
        }
        delete a
      }
      invariant forall(Class a, Class b: a == b)
    ADSL
  end

  def test_if__basic
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {
        if isempty(allof(Class)) {
          create(Class)
        }
      }
      invariant exists(Class o)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {
        if not isempty(allof(Class)) {
          create(Class)
        }
      }
      invariant not exists(Class o)
    ADSL
  end

  def test_if__nested
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah() {
        if exists(Class o) {
        } else {
          if not exists(Class o) {
            create(Class)
          }
        }
      }
      invariant not exists(Class o)
    ADSL
  end

  def test_if__in_loop
    adsl_assert :correct, <<-ADSL
      class Class {
        0+ Class2 rel
      }
      class Class2 {}
      action blah() {
        foreach o: allof(Class) {
          if isempty(o.rel) {
            o.rel += create(Class2)
          }
        }
      }
      invariant forall(Class o, Class2 r1, Class2 r2: implies(r1 == o.rel and r2 == o.rel, r1 == r2))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {
        0+ Class2 rel
      }
      class Class2 {}
      action blah() {
        foreach o: allof(Class) {
          if isempty(o.rel) {
            delete o
          }
        }
      }
      invariant exists(Class o: isempty(o.rel))
    ADSL
  end

  def test_if__no_objects
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {
        if isempty(allof(Class)) {
          create(Class)
        }
      }
      invariant exists(Class o)
    ADSL
  end

  def test_if__lambda
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {
        var = empty
        if isempty(allof(Class)) {
          var = create(Class)
        } else {
          var = oneof(allof(Class))
        }
        delete var
      }
      invariant forall(Class o1, Class o2: o1 == o2)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah() {
        var = empty
        if forall(Class o1, Class o2: o1 == o2) {
          var = oneof(allof(Class))
        }
        delete var
      }
      invariant not(exists(Class o) and forall(Class o1, Class o2: o1 == o2))
    ADSL
  end

  def test_for_each__no_contradictions
    adsl_assert :incorrect, <<-ADSL, :conjecture => false
      class Class{}
      action blah() {
        foreach c: allof(Class) {
        }
      }
    ADSL
  end
  
  def test_for_each__no_contradictions_at_least_once
    adsl_assert :incorrect, <<-ADSL, :conjecture => false
      class Class{}
      action blah() {
        create(Class)
        foreach c: allof(Class) {
        }
      }
    ADSL
  end

  def test_for_each__no_iterations
    adsl_assert :correct, <<-ADSL
      class Class1{}
      class Class2{}
      action blah() {
        create(Class1)
        delete allof(Class2)
        foreach i: allof(Class2) {
          delete allof(Class1)
        }
      }
      invariant exists(Class1 o)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class1{}
      class Class2{}
      action blah() {
        delete allof(Class2)
        foreach i: allof(Class2) {
          create(Class1)
        }
      }
      invariant not exists(Class1 o)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class1{}
      class Class2{}
      action blah() {
        delete allof(Class1)
        create(Class1)
        delete allof(Class2)
        foreach i: allof(Class2) {
          delete allof(Class1)
        }
      }
      invariant !exists(Class1 o)
    ADSL
  end

  def test_for_each__single_iteration
    adsl_assert :correct, <<-ADSL
      class Class1{}
      class Class2{}
      action blah() {
        delete allof(Class1)
        delete allof(Class2)
        
        create(Class1)
        foreach c: allof(Class1) {
          create(Class2)
        }
      }
      invariant exists(Class1 a)
      invariant exists(Class2 a)
      invariant forall(Class2 a, Class2 b: a == b)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class1 {}
      class Class2 {}
      action blah() {
        delete allof(Class1)
        delete allof(Class2)
        
        create(Class1)
        foreach c: allof(Class1) {
          create(Class2)
        }
      }
      invariant exists(Class2 a, Class2 b: not a == b)
    ADSL
  end

  def test_for_each__two_iterations_parallelizable
    adsl_assert :correct, <<-ADSL
      class Class1{}
      class Class2{}
      action blah() {
        delete allof(Class1)
        delete allof(Class2)
        
        create(Class1)
        create(Class1)
        foreach c: allof(Class1) {
          create(Class2)
        }
      }
      invariant exists(Class1 a)
      invariant exists(Class2 a)
      invariant forall(Class2 a, Class2 b, Class2 c: a == b or b == c or a == c)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class1{}
      class Class2{}
      action blah() {
        delete allof(Class1)
        delete allof(Class2)
        
        create(Class1)
        create(Class1)
        foreach c: allof(Class1) {
          create(Class2)
        }
      }
      invariant exists(Class2 a, Class2 b, Class2 c: !a == b and !b == c and !a == c)
    ADSL
  end

  def test__all_objects_have_single_ref
    adsl_assert :correct, <<-ADSL
      class Class { 0+ Class rel }
      action blah() {
        allof(Class).rel -= allof(Class)
        foreach c: allof(Class) {
          c2 = oneof(allof(Class))
          c.rel += c2
        }
      }
      invariant forall(Class o: not isempty(o.rel))
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class { 0+ Class rel }
      action blah() {
        allof(Class).rel -= allof(Class)
        foreach c: allof(Class) {
          c2 = oneof(allof(Class))
          c.rel += c2
        }
      }
      invariant not exists(Class o, Class o2, Class o3: o2 in o.rel and o3 in o.rel and o2 != o3)
    ADSL
  end
end
