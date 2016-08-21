require 'adsl/util/test_helper'

class BranchTest < ActiveSupport::TestCase
  include ADSL::FOL
  
  def test_either__blank
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah {
        if * {} else {}
      }
      invariant exists(Class o)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah {
        if * {} else {}
      }
      invariant not exists(Class o)
    ADSL
  end
  
  def test_either__doesnt_break_others
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah {
        create Class
        if * {} else {}
      }
      invariant exists(Class o)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah {
        if * {} else {}
        create Class
      }
      invariant exists(Class o)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah {
        if * {} else {}
        create Class
      }
      invariant not exists(Class o)
    ADSL
  end

  def test_either__may_delete_an_object
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah {
        if *
          delete Class
      }
      invariant exists(Class o)
    ADSL
  end

  def test_either__may_delete_and_create_an_object
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah {
        if * {
          delete Class
          create Class
        }
      }
      invariant not exists(Class o)
    ADSL
  end

  def test_either__branches_symmetrical
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah {
        if * {
          delete Class
          create Class
        }
      }
      invariant not exists(Class o)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah {
        if * {
          delete Class
          create Class
        }
      }
      invariant not exists(Class o)
    ADSL
  end

  def test_either__false_dichotomy
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah {
        if * {
          create Class
        } else {
          create Class
        }
      }
      invariant not exists(Class o)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah {
        if * {
          create Class
        } else {
          create Class
        }
      }
      invariant exists(Class o)
    ADSL
  end

  def test_either__multiple_options
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {
        if * {
          delete Class
          create Class
        } else {
          create Class
        }
      }
      invariant exists(Class o)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah {
        if * {
          create Class
        } elsif * {
          delete Class
          create Class
        } else {
          delete Class
        }
      }
      invariant exists(Class o)
    ADSL
  end
  
  def test_either__delete_and_create_an_object
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah {
        if * {
          delete Class
          create Class
        } else {
          delete Class
          create Class
        }
      }
      invariant forall(Class a, Class b: a == b)
    ADSL
  end

  def test_either__variables
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah {
        if * {
          a = create Class
          delete a
        } else {
          create Class
        }
      }
      invariant forall(Class a, Class b: a == b)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah {
        a = create Class
        if * {
          delete a
        }
      }
      invariant not exists(Class a)
    ADSL
  end

  def test_either__lambda
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah {
        a = create Class
        if * {
          delete a
        }
      }
      invariant forall(Class a, Class b: a == b)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      class Class{}
      action blah {
        a = create Class
        if * {
          delete a
        }
      }
      invariant forall(Class a, Class b: a == b)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah {
        a = create Class
        if * {
          delete a
        } else {
          delete a
        }
      }
      invariant not exists(Class a)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah {
        a = create Class
        if * {
          delete a
        } else {
          delete a
        }
      }
      invariant forall(Class a, Class b: a == b)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class{}
      action blah {
        a = Class
        if * {
          a = create Class
        } elsif * {
          a = create Class
          a = oneof Class
        } else {
          a = create Class
        }
        delete a
      }
      invariant forall(Class a, Class b: a == b)
    ADSL
  end

  def test_if__basic
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {
        if isempty(Class) {
          create Class
        }
      }
      invariant exists(Class o)
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {
        if not isempty(Class) {
          create Class
        }
      }
      invariant not exists(Class o)
    ADSL
  end

  def test_if__nested
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah {
        if exists(Class o) {
        } else {
          if not exists(Class o) {
            create Class
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
      action blah {
        foreach o: Class {
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
      action blah {
        foreach o: Class {
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
      action blah {
        if isempty(Class) {
          create Class
        }
      }
      invariant exists(Class o)
    ADSL
  end

  def test_if__lambda
    # adsl_assert :correct, <<-ADSL
    #   class Class {}
    #   action blah {
    #     var = empty
    #     if isempty(Class) {
    #       var = create Class
    #     } else {
    #       var = oneof Class
    #     }
    #     delete var
    #   }
    #   invariant forall(Class o1, Class o2: o1 == o2)
    # ADSL
    adsl_assert :correct, <<-ADSL
      class Class {}
      action blah {
        var = empty
        if forall(Class o1, Class o2: o1 == o2) {
          var = oneof Class
        }
        delete var
      }
      invariant not(exists(Class o) and forall(Class o1, Class o2: o1 == o2))
    ADSL
  end

  def test_for_each__no_contradictions
    adsl_assert :incorrect, <<-ADSL, :conjecture => false
      class Class{}
      action blah {
        foreach c: Class {
        }
      }
    ADSL
  end
  
  def test_for_each__no_contradictions_at_least_once
    adsl_assert :incorrect, <<-ADSL, :conjecture => false
      class Class{}
      action blah {
        create Class
        foreach c: Class {
        }
      }
    ADSL
  end

  def test_for_each__no_iterations
    adsl_assert :correct, <<-ADSL
      class Class1 {}
      class Class2 {}
      action blah {
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
      action blah {
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
      action blah {
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
      action blah {
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
      action blah {
        delete allof(Class1)
        delete allof(Class2)
        
        create(Class1)
        foreach c: allof(Class1) {
          create(Class2)
        }
      }
      invariant exists(Class2 a, Class2 b: a != b)
    ADSL
  end

  def test__unflat_for_each_no_contradictions
    adsl_assert :correct, <<-ADSL, :conjecture => true
      class Class {}
      action blah {
        unflatforeach c: Class {}
      }
    ADSL
    adsl_assert :incorrect, <<-ADSL, :conjecture => false
      class Class {}
      action blah {
        unflatforeach c: Class {}
      }
    ADSL
  end
  
  def test__unflat_empty_for_each_no_contradictions
    adsl_assert :correct, <<-ADSL, :conjecture => true
      action blah {
        unflatforeach c: empty {}
      }
    ADSL
    adsl_assert :incorrect, <<-ADSL, :conjecture => false
      action blah {
        unflatforeach c: empty {}
      }
    ADSL
  end
  
  def test__unflat_one_for_each_no_contradictions
    adsl_assert :correct, <<-ADSL, :conjecture => true
      class Class {}
      action blah {
        delete Class
        create Class
        unflatforeach c: Class {}
      }
    ADSL
    adsl_assert :incorrect, <<-ADSL, :conjecture => false
      class Class {}
      action blah {
        delete Class
        create Class
        unflatforeach c: Class {}
      }
    ADSL
  end
  
  def test__unflat_two_for_each_no_contradictions
    adsl_assert :correct, <<-ADSL, :conjecture => true
      class Class {}
      action blah {
        delete Class
        create Class
        create Class
        unflatforeach c: Class {}
      }
    ADSL
    adsl_assert :incorrect, <<-ADSL, :conjecture => false
      class Class {}
      action blah {
        delete Class
        create Class
        create Class
        unflatforeach c: Class {}
      }
    ADSL
  end
  
  def test__unflat_three_for_each_no_contradictions
    adsl_assert :correct, <<-ADSL, :conjecture => true
      class Class {}
      action blah {
        delete Class
        create Class
        create Class
        create Class
        unflatforeach c: Class {}
      }
    ADSL
    adsl_assert :incorrect, <<-ADSL, :conjecture => false
      class Class {}
      action blah {
        delete Class
        create Class
        create Class
        create Class
        unflatforeach c: Class {}
      }
    ADSL
  end

  def test__unflat_noempty_iterations
    adsl_assert :incorrect, <<-ADSL
      class Class {}
      action blah {
        unflatforeach c: Class {
          delete c
        }
      }
      invariant exists(Class c)
    ADSL
  end

  def test__something_flat_can_do
    adsl_assert :incorrect, <<-ADSL
      class Class {
        0+ Class other
      }
      action blah {
        flatforeach c: Class {
          if not isempty(c.other) {
            delete c
          }
        }
      }
      invariant exists(Class c: not isempty(c.other))
    ADSL
  end
  
  def test__something_unflat_cannot_do
    adsl_assert :incorrect, <<-ADSL
      class Class {
        0+ Class other
      }
      action blah {
        unflatforeach c: Class {
          if not isempty(c.other) {
            delete c
          }
        }
      }
      invariant exists(Class c: not isempty(c.other))
    ADSL
  end
  
  def test__all_objects_have_single_ref
    adsl_assert :correct, <<-ADSL
      class Class { 0+ Class rel }
      action blah {
        Class.rel -= Class
        foreach c: Class {
          c2 = oneof Class
          c.rel += c2
        }
      }
      invariant forall(Class o: not isempty(o.rel))
    ADSL
    adsl_assert :correct, <<-ADSL
      class Class { 0+ Class rel }
      action blah {
        Class.rel -= Class
        foreach c: Class {
          c2 = oneof Class
          c.rel += c2
        }
      }
      invariant not exists(Class o, Class o2, Class o3: o2 in o.rel and o3 in o.rel and o2 != o3)
    ADSL
  end

  def test_oneof_in_branch_is_tied_to_prestate
    adsl_assert :correct, <<-ADSL
      class Class {
        0+ Class2 rel
      }
      class Class2 {}
      action blah {
        if * {
          var = create Class
          var.rel = oneof Class2
        }
      }
      invariant forall(Class c: not isempty(c.rel))
    ADSL
  end

  def test_delete_deref_and_original_in_branch_when_defined_outside
    adsl_assert :correct, <<-ADSL
      class Class {
        0+ Sub subs inverseof owner
      }
      class Sub {
        0+ Class owner 
      }
      action blah {
        var = oneof Class
        if * {
          delete var.subs
          delete var
        }
      }
      invariant forall(Sub s: not isempty(s.owner))
    ADSL
  end

  def test_variables_in_branches_are_initialized
    adsl_assert :correct, <<-ADSL
      class A {}
      action blah {
        var = subset(A)
        if * {
          var = empty
        }
      }
      invariant true
    ADSL
  end

  def test_assignment_in_loop_with_branch
    adsl_assert :correct, <<-ADSL
      class Klass {}
      class Klass2 {}
      action blah {
        foreach b: Klass {
          a = create Klass2
          if (*) {}
        }
      }
      invariant true
    ADSL
  end
end

