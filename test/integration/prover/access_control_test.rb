require 'adsl/util/test_helper'
require 'minitest/unit'

require 'minitest/autorun'

class IntegrationsAccessControlTest < MiniTest::Unit::TestCase
  include ADSL::FOL
  
  def test_blank_data_store
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah() {}
    ADSL
  end

  def test_auth_test_triggered_if_auth_class_exists
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah() {
      }
    ADSL
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      action blah() {
        create(User)
      }
    ADSL
  end

  def test_current_user_exists
    sort = Sort.new :UserSort
    pred = Predicate.new "User", sort
    adsl_assert :incorrect, <<-ADSL, :conjecture => Exists[sort, :o, pred[:o]]
      class User {}
      action blah() {}
    ADSL
    adsl_assert :correct, <<-ADSL, :conjecture => Exists[sort, :o, pred[:o]]
      authenticable class User {}
      action blah() {}
    ADSL
  end

  def test_create_needs_permission
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      action blah() {
        create(User)
      }
    ADSL
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah() {
        create(User)
      }
      permit create allof(User)
    ADSL
  end

  def test_delete_needs_permission
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      action blah() {
        delete allof(User)
      }
    ADSL
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah() {
        delete allof(User)
      }
      permit delete allof(User)
    ADSL
  end

  def test_strange_result_with_creating_and_subeq_deleting_not_being_an_op
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah() {
        delete create(User)
      }
    ADSL
  end

  def test_edit_implies_create_or_delete
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      action blah() {
        create(User)
        delete oneof(allof(User))
      }
      permit delete allof(User)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      action blah() {
        create(User)
        delete oneof(allof(User))
      }
      permit create allof(User)
    ADSL
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah() {
        create(User)
        delete oneof(allof(User))
      }
      permit edit allof(User)
    ADSL
  end

  def test_edit_across_group_specified
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      usergroup ug
      rule inusergroup(currentuser, ug)
      action blah() {
        create(User)
      }
      permit ug create allof(User)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      usergroup ug1, ug2
      rule not inusergroup(currentuser, ug1)
      action blah() {
        create(User)
      }
      permit ug1 create allof(User)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      usergroup ug1
      action blah() {
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
      action blah() {
        currentuser.friends += create(User)
      }
      permit edit currentuser.friends
    ADSL
  end

  def test_create_assoc__without_assoc_permit
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {
        0+ User friends
      }
      action blah() {
        currentuser.friends += oneof(allof(User))
      }
    ADSL
  end

  def test_create_assoc__with_assoc_permit
    adsl_assert :correct, <<-ADSL
      authenticable class User {
        0+ User friends
      }
      action blah() {
        currentuser.friends += oneof(allof(User))
      }
      permit assoc currentuser.friends
    ADSL
  end

  def test_delete_assoc__without_deassoc_permit
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {
        0+ User friends
      }
      action blah() {
        currentuser.friends -= oneof(allof(User))
      }
    ADSL
  end

  def test_delete_assoc__with_deassoc_permit
    adsl_assert :correct, <<-ADSL
      authenticable class User {
        0+ User friends
      }
      action blah() {
        currentuser.friends -= oneof(allof(User))
      }
      permit deassoc currentuser.friends
    ADSL
  end

  def test_read__basic
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      action blah() {
        v = allof(User)
      }
    ADSL
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah() {
        v = allof(User)
      }
      permit read allof(User)
    ADSL
  end

  def test_read__some
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah() {
        v = allof(User)
      }
      permit read allof(User)
    ADSL
    adsl_assert :correct, <<-ADSL
      authenticable class User {}
      action blah() {
        v = oneof(allof(User))
      }
      permit read allof(User)
    ADSL
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      action blah() {
        v = allof(User)
      }
      permit read oneof(allof(User))
    ADSL
    adsl_assert :incorrect, <<-ADSL
      authenticable class User {}
      action blah() {
        v = oneof(allof(User))
      }
      permit read oneof(allof(User))
    ADSL
  end

  def test_delete_deref
    adsl_assert :correct, <<-ADSL
      authenticable class User{
        0+ User friends
      }
      action blah() {
        delete subset(currentuser.friends)
      }
      permit edit currentuser.friends
    ADSL
  end
end
