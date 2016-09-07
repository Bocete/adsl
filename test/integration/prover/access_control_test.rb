require 'adsl/util/test_helper'

class IntegrationsAccessControlTest < ActiveSupport::TestCase
  include ADSL::FOL
  
  def test_blank_data_store
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah {}
    ADSL
  end

  def test_auth_test_triggered_if_auth_class_and_permits_exist
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah {
      }
    ADSL
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah {
        create(User)
      }
    ADSL
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      permit read User
      action blah {
        create(User)
      }
    ADSL
  end

  def test_current_user_exists
    sort = Sort.new :UserSort
    pred = Predicate.new "User", sort
    adsl_assert :incorrect, <<-ADSL, :conjecture => Exists[sort, :o, pred[:o]]
      class User {}
      action blah {}
    ADSL
    adsl_assert :correct, <<-ADSL, :conjecture => Exists[sort, :o, pred[:o]]
      authenticable class User {}
      action blah {}
    ADSL
  end

  def test_create_needs_permission
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      permit read User
      action blah {
        create(User)
      }
    ADSL
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      permit create allof(User)
      action blah {
        create(User)
      }
    ADSL
  end

  def test_delete_needs_permission
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      permit read User
      action blah {
        delete allof(User)
      }
    ADSL
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah {
        delete allof(User)
      }
      permit delete allof(User)
    ADSL
  end

  def test_strange_result_with_creating_and_subeq_deleting_not_being_an_op
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah {
        delete create(User)
      }
    ADSL
  end

  def test_edit_implies_create_or_delete
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      permit delete allof(User)
      action blah {
        create(User)
        delete oneof(allof(User))
      }
    ADSL
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      permit create allof(User)
      action blah {
        create(User)
        delete oneof(allof(User))
      }
    ADSL
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      permit edit allof(User)
      action blah {
        create(User)
        delete oneof(allof(User))
      }
    ADSL
  end

  def test_edit_across_group_specified
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      usergroup ug
      rule inusergroup(currentuser, ug)
      action blah {
        create(User)
      }
      permit ug create allof(User)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      usergroup ug1, ug2
      rule not inusergroup(currentuser, ug1)
      action blah {
        create(User)
      }
      permit ug1 create allof(User)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      usergroup ug1
      action blah {
        create(User)
      }
      permit ug1 create allof(User)
    ADSL
  end

  def test_create_assoc_target
    adsl_assert :correct, <<-ADSL
      authenticable class User {
        0+ User friends
      }
      action blah {
        currentuser.friends += create(User)
      }
      permit edit currentuser.friends
    ADSL
  end
  
  def test_create_assoc__with_permit
    adsl_assert :correct, <<-ADSL
      authenticable class User {
        0+ User friends
      }
      action blah {
        currentuser.friends += oneof(allof(User))
      }
      permit read currentuser
      permit create currentuser.friends
    ADSL
    adsl_assert :correct, <<-ADSL
      authenticable class User {
        0+ User friends
      }
      action blah {
        currentuser.friends += oneof(allof(User))
      }
      permit create currentuser
      permit create currentuser.friends
    ADSL
  end

  def test_delete_assoc__with_permit
    adsl_assert :correct, <<-ADSL
      authenticable class User {
        0+ User friends
      }
      action blah {
        currentuser.friends -= oneof(allof(User))
      }
      permit delete currentuser
      permit delete currentuser.friends
    ADSL
    adsl_assert :correct, <<-ADSL
      authenticable class User {
        0+ User friends
      }
      action blah {
        currentuser.friends -= oneof(allof(User))
      }
      permit read currentuser
      permit delete currentuser.friends
    ADSL
  end

  def test_read__basic
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      permit create User
      action blah {
        at__v = allof(User)
      }
    ADSL
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah {
        at__v = allof(User)
      }
      permit read allof(User)
    ADSL
  end

  def test_read__some
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah {
        at__v = allof(User)
      }
      permit read allof(User)
    ADSL
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah {
        at__v = oneof(allof(User))
      }
      permit read allof(User)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      action blah {
        at__v = allof(User)
      }
      permit read oneof(allof(User))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      action blah {
        at__v = oneof(allof(User))
      }
      permit read oneof(allof(User))
    ADSL
  end

  def test_delete_deref
    adsl_assert :correct, <<-ADSL
      authenticable class User{
        0+ User friends
      }
      action blah {
        delete subset(currentuser.friends)
      }
      permit edit currentuser.friends
    ADSL
  end

  def test_permitted_create
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      class Stuff {}
      usergroup mod
      action blah {
        create(Stuff)
      }
      permit mod edit allof(User)
    ADSL
  end

  def test_not_permitted_implies_skip
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      class Stuff {}
      action blah {
        if permitted(delete allof(Stuff)) {
          delete oneof(allof(Stuff))
        }
      }
      invariant exists(Stuff u)
    ADSL
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      class Stuff {}
      action blah {
        if permitted(delete allof(Stuff)) {
          delete oneof(allof(Stuff))
        }
      }
      invariant not exists(Stuff s)
    ADSL
  end

  def test_permitted_create_deref
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {
        0+ Note notes
      }
      class Note {
        1 User owner inverseof notes
      }
      usergroup mod
      action blah {
        delete currentuser.notes
      }
      permit mod edit allof(Note)
    ADSL
    adsl_assert :correct, <<-ADSL
      authenticable class User {
        0+ Note notes
      }
      class Note {
        1 User owner inverseof notes
      }
      action blah {
        delete currentuser.notes
      }
      permit edit allof(Note)
    ADSL
    adsl_assert :correct, <<-ADSL
      authenticable class User {
        0+ Note notes
      }
      class Note {
        1 User owner inverseof notes
      }
      action blah {
        delete currentuser.notes
      }
      permit edit currentuser.notes
    ADSL
  end

  def test_floating_tuple_permission
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {
        0+ Other others
      }
      class Other {}
      action blah {
        obj = oneof(allof(Other))
        delete obj
      }
      permit read allof(Other)
      permit edit currentuser.others
    ADSL
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {
        0+ Other others
      }
      class Other {}
      action blah {
        obj = oneof(allof(Other))
        currentuser.others += obj
        currentuser.others -= obj
        delete obj
      }
      permit read allof(Other)
      permit edit currentuser.others
    ADSL
  end

  def test_should_this_be_allowed
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {
        1 Other others
      }
      class Other {}
      action blah {
        currentuser.others = create(Other)
        currentuser.others = create(Other)
        currentuser.others = create(Other)
      }
      permit edit currentuser.others
    ADSL
  end

  def test_the_user_reads_only_the_current_user
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      permit read currentuser
      action blah {
        at__user = oneof(allof(User))
        assert at__user in currentuser
      }
    ADSL
  end

  def test_the_user_reads_their_own_meals
    adsl_assert :correct, <<-ADSL
      authenticable class User {
        0+ Meal meals
      }
      class Meal {
        0..1 User user
      }
      permit read currentuser
      permit read currentuser.meals
      action blah {
        at__meals = subset(allof(Meal))
        assert at__meals in currentuser.meals
      }
    ADSL
  end

  def test_reads_of_initially_ambiguous_types
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {
      }
      permit read currentuser
      action blah {
        at__unknown = empty
        if * {
          at__unknown = oneof User
        }
      }
    ADSL
  end
end
