require 'adsl/parser/adsl_parser.tab'
require 'adsl/ds/data_store_spec'
require 'adsl/util/test_helper'
require 'minitest/unit'

require 'minitest/autorun'
require 'pp'

module ADSL::Parser
  class AccessControlParserTest < MiniTest::Unit::TestCase
    include ADSL::DS

    def test_authenticable_class
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class {}
          authenticable class Class2 {}
        adsl
        assert_false spec.classes.first.authenticable?
        assert       spec.classes.last.authenticable?
      end
    end
    
    def test_multiple_authenticable_classes
      parser = ADSLParser.new
      assert_raises ADSLError do
        spec = parser.parse <<-adsl
          authenticable class Class {}
          authenticable class Class2 {}
        adsl
      end
    end

    def test_usergroup_declared
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          authenticable class Class {}
          usergroup Admin
        adsl
        assert_equal 1, spec.usergroups.length
        assert_equal 'Admin', spec.usergroups.first.name
      end
      
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          authenticable class Class {}
          usergroup Admin, Moderator
        adsl
        assert_equal 2, spec.usergroups.length
        assert_equal ['Admin', 'Moderator'], spec.usergroups.map(&:name)
      end

      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          authenticable class Class {}
          usergroup Admin, Moderator, Bot
        adsl
        assert_equal 3, spec.usergroups.length
        assert_equal ['Admin', 'Moderator', 'Bot'], spec.usergroups.map(&:name)
      end
      
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          authenticable class Class {}
          usergroup Admin, Moderator
          usergroup Bot
        adsl
        assert_equal 3, spec.usergroups.length
        assert_equal ['Admin', 'Moderator', 'Bot'], spec.usergroups.map(&:name)
      end
    end

    def test_usergroups_only_if_auth_class
      parser = ADSLParser.new
      assert_raises ADSLError do
        spec = parser.parse <<-adsl
          class Class {}
          usergroup Admin, Moderator
        adsl
      end
      assert_raises ADSLError do
        spec = parser.parse <<-adsl
          usergroup Admin, Moderator
          class Class {}
        adsl
      end
    end

    def test_usergroups__unique_names
      parser = ADSLParser.new
      assert_raises ADSLError do
        spec = parser.parse <<-adsl
          authenticable class Class {}
          usergroup Admin, Admin
        adsl
      end
      assert_raises ADSLError do
        spec = parser.parse <<-adsl
          authenticable class Class {}
          usergroup Admin
          usergroup Admin
        adsl
      end
    end

    def test_currentuser_requires_authclass
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        parser.parse <<-adsl
          authenticable class User {}
          action blah() {
            delete currentuser
          }
        adsl
      end
      assert_raises ADSLError do
        parser.parse <<-adsl
          class User {}
          action blah() {
            delete currentuser
          }
        adsl
      end
    end

    def test_currentuser_authclass_typechecks
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        parser.parse <<-adsl
          authenticable class User {}
          action blah() {
            u = allof(User)
            u = currentuser
          }
        adsl
      end
      assert_raises ADSLError do
        parser.parse <<-adsl
          authenticable class User {}
          class User2
          action blah() {
            u = allof(User2)
            u = currentuser
          }
        adsl
      end
    end

    def test_in_user_group__requires_usergroups
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        parser.parse <<-adsl
          authenticable class User {}
          usergroup UG
          action blah() {
            a = inusergroup(UG)
          }
        adsl
      end
      assert_raises ADSLError do
        parser.parse <<-adsl
          authenticable class User {}
          usergroup UG
          action blah() {
            a = inusergroup(UGa)
          }
        adsl
      end
    end

    def test_in_user_group__requires_authclass
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        parser.parse <<-adsl
          authenticable class User {}
          usergroup UG
          action blah() {
            a = inusergroup(UG)
          }
        adsl
      end
      assert_raises ADSLError do
        parser.parse <<-adsl
          class User {}
          usergroup UG
          action blah() {
            a = inusergroup(UG)
          }
        adsl
      end
    end

    def test_in_user_group__is_bool_expression
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        parser.parse <<-adsl
          authenticable class User {}
          usergroup UG
          action blah() {
            a = inusergroup(UG)
          }
          invariant not inusergroup(UG)
        adsl
      end
    end

    def test_in_user_group__can_accept_expr
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        parser.parse <<-adsl
          authenticable class User {}
          usergroup UG
          action blah() {
            a = inusergroup(UG)
          }
          invariant not inusergroup(allof(User), UG)
        adsl
      end
    end

    def test_all_of_user_group__requires_authclass
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        parser.parse <<-adsl
          authenticable class User {}
          usergroup UG
          action blah() {
            a = allofusergroup(UG)
          }
        adsl
      end
      assert_raises ADSLError do
        parser.parse <<-adsl
          class User {}
          action blah() {
            a = allofusergroup(UG)
          }
        adsl
      end
    end

    def test_all_of_user_group__requires_proper_usergroup
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        parser.parse <<-adsl
          authenticable class User {}
          usergroup UG
          action blah() {
            a = allofusergroup(UG)
          }
        adsl
      end
      assert_raises ADSLError do
        parser.parse <<-adsl
          authenticable class User {}
          usergroup UG
          action blah() {
            a = allofusergroup(UG2)
          }
        adsl
      end
    end

    def test_all_of_user_group__typechecks_correctly
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        parser.parse <<-adsl
          authenticable class User {}
          usergroup UG
          action blah() {
            a = allofusergroup(UG)
            a = create(User)
          }
        adsl
      end
      assert_raises ADSLError do
        parser.parse <<-adsl
          authenticable class User {}
          usergroup UG
          invariant allofusergroup(UG)
        adsl
      end
    end

    def test_permit__requires_authclass
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        parser.parse <<-adsl
          authenticable class User {}
          usergroup UG
          permit UG edit allof(User)
        adsl
      end
      assert_raises ADSLError do
        parser.parse <<-adsl
          class User {}
          permit UG edit allof(User)
        adsl
      end
    end

    def test_permit__proper_operations_supported
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          authenticable class User {}
          usergroup UG
          permit UG edit, read, create, delete allof(User)
        adsl
        assert_equal Set[:read, :create, :delete], spec.ac_rules.first.ops
      end
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          authenticable class User {}
          usergroup UG
          permit UG edit, edit, delete allof(User)
        adsl
        assert_equal Set[:create, :delete], spec.ac_rules.first.ops
      end
      assert_raises ADSLError do
        parser.parse <<-adsl
          class User {}
          permit UG erase allof(User)
        adsl
      end
    end

    def test_permit__assoc_deassoc_require_deref_expr
      parser = ADSLParser.new
      ["assoc", "deassoc"].each do |op|
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            authenticable class User {
              0+ User friends
            }
            permit #{op} allof(User).friends
          adsl
        end
        assert_raises ADSLError do
          parser.parse <<-adsl
            authenticable class User {
              0+ User friends
            }
            permit #{op} allof(User)
          adsl
        end
      end
    end

    def test_permit__create_delete_edit_imply_assoc_deassoc_in_derefs
      parser = ADSLParser.new
      expected = {
        :create => [:assoc],
        :delete => [:deassoc],
        :edit => [:assoc, :deassoc]
      }
      expected.each do |op, result|
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            authenticable class User {
              0+ User friends
            }
            permit #{op} allof(User).friends
          adsl
          result.each do |ex_op|
            assert spec.ac_rules.first.ops.include? ex_op
          end
        end
      end
    end

    def test_permit__unrolling_of_all_meta_ops
      parser = ADSLParser.new
      expected = {
        :read => [:read],
        :assoc => [:assoc],
        :deassoc => [:deassoc],
        :create => [:assoc, :create],
        :delete => [:deassoc, :delete],
        :edit => [:create, :delete, :assoc, :deassoc]
      }
      expected.each do |op, result|
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            authenticable class User {
              0+ User friends
            }
            permit #{op} allof(User).friends
          adsl
          assert_set_equal result, spec.ac_rules.first.ops
        end
      end
    end

    def test_permitted_by_type__requires_the_right_class
      parser = ADSLParser.new
      assert_raises ADSLError do
        parser.parse <<-adsl
          authenticable class User {}
          action blah() {
            a = permittedbytype(create Nonexistent)
          }
        adsl
      end
    end

    def test_permitted_by_type__ops_match
      parser = ADSLParser.new
      expected = {
        :read => [:read],
        :create => [:create],
        :delete => [:delete],
        :edit => [:create, :delete]
      }
      expected.each do |op, result|
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            authenticable class User {}
            action blah() {
              a = permittedbytype(#{op} User)
            }
          adsl
          action = spec.actions.first
          assert_set_equal result, action.block.statements.first.expr.ops
        end
      end
    end

  end
end
