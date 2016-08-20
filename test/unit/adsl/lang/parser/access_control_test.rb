require 'adsl/util/test_helper'
require 'adsl/lang/parser/adsl_parser.tab'
require 'adsl/ds/data_store_spec'

module ADSL::Lang
  module Parser
    class AccessControlParserTest < ActiveSupport::TestCase
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
            usergroup admin
          adsl
          assert_equal 1, spec.usergroups.length
          assert_equal 'admin', spec.usergroups.first.name
        end
        
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            authenticable class Class {}
            usergroup admin, moderator
          adsl
          assert_equal 2, spec.usergroups.length
          assert_equal ['admin', 'moderator'], spec.usergroups.map(&:name)
        end
  
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            authenticable class Class {}
            usergroup admin, moderator, bot
          adsl
          assert_equal 3, spec.usergroups.length
          assert_equal ['admin', 'moderator', 'bot'], spec.usergroups.map(&:name)
        end
        
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            authenticable class Class {}
            usergroup admin, moderator
            usergroup bot
          adsl
          assert_equal 3, spec.usergroups.length
          assert_equal ['admin', 'moderator', 'bot'], spec.usergroups.map(&:name)
        end
      end
  
      def test_usergroups_only_if_auth_class
        parser = ADSLParser.new
        assert_raises ADSLError do
          spec = parser.parse <<-adsl
            class Class {}
            usergroup admin, moderator
          adsl
        end
        assert_raises ADSLError do
          spec = parser.parse <<-adsl
            usergroup admin, moderator
            class Class {}
          adsl
        end
      end
  
      def test_usergroups__unique_names
        parser = ADSLParser.new
        assert_raises ADSLError do
          spec = parser.parse <<-adsl
            authenticable class Class {}
            usergroup admin, admin
          adsl
        end
        assert_raises ADSLError do
          spec = parser.parse <<-adsl
            authenticable class Class {}
            usergroup admin
            usergroup admin
          adsl
        end
      end
  
      def test_currentuser_requires_authclass
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            authenticable class User {}
            action blah {
              delete currentuser
            }
          adsl
        end
        assert_raises ADSLError do
          parser.parse <<-adsl
            class User {}
            action blah {
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
            action blah {
              u = allof(User)
              u = currentuser
            }
          adsl
        end
        assert_raises ADSLError do
          parser.parse <<-adsl
            authenticable class User {}
            class User2
            action blah {
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
            usergroup ug
            action blah {
              if inusergroup(ug) {
                create User
              }
            }
          adsl
        end
        assert_raises ADSLError do
          parser.parse <<-adsl
            authenticable class User {}
            usergroup ug
            action blah {
              if inusergroup(uga) {
                create User
              }
            }
          adsl
        end
      end
  
      def test_in_user_group__requires_authclass
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            authenticable class User {}
            usergroup ug
            action blah {
              if inusergroup(ug) {
                create User
              }
            }
          adsl
        end
        assert_raises ADSLError do
          parser.parse <<-adsl
            class User {}
            usergroup ug
            action blah {
              if inusergroup(ug) {
                create User
              }
            }
          adsl
        end
      end
  
      def test_in_user_group__is_bool_expression
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            authenticable class User {}
            usergroup ug
            action blah {
              if inusergroup(ug) {
                create User
              }
            }
            invariant not inusergroup(ug)
          adsl
        end
        assert_raises ADSLError do
          parser.parse <<-adsl
            authenticable class User {}
            usergroup ug
            action blah {
              a = inusergroup(ug)
            }
            invariant not inusergroup(ug)
          adsl
        end
      end
  
      def test_in_user_group__can_accept_expr
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            authenticable class User {}
            usergroup ug
            action blah {
              if inusergroup(ug) {
                create User
              }
            }
            invariant not inusergroup(allof(User), ug)
          adsl
        end
      end
  
      def test_all_of_user_group__requires_authclass
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            authenticable class User {}
            usergroup ug
            action blah {
              a = allofusergroup(ug)
            }
          adsl
        end
        assert_raises ADSLError do
          parser.parse <<-adsl
            class User {}
            action blah {
              a = allofusergroup(ug)
            }
          adsl
        end
      end
  
      def test_all_of_user_group__requires_proper_usergroup
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            authenticable class User {}
            usergroup ug
            action blah {
              a = allofusergroup(ug)
            }
          adsl
        end
        assert_raises ADSLError do
          parser.parse <<-adsl
            authenticable class User {}
            usergroup ug
            action blah {
              a = allofusergroup(ug2)
            }
          adsl
        end
      end
  
      def test_all_of_user_group__typechecks_correctly
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            authenticable class User {}
            usergroup ug
            action blah {
              a = allofusergroup(ug)
              a = create(User)
            }
          adsl
        end
        assert_raises ADSLError do
          parser.parse <<-adsl
            authenticable class User {}
            usergroup ug
            invariant allofusergroup(ug)
          adsl
        end
      end
  
      def test_permit__requires_authclass
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            authenticable class User {}
            usergroup ug
            permit ug edit allof(User)
          adsl
        end
        assert_raises ADSLError do
          parser.parse <<-adsl
            class User {}
            permit ug edit allof(User)
          adsl
        end
      end
  
      def test_permit__proper_operations_supported
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            authenticable class User {}
            usergroup ug
            permit ug edit, read, create, delete allof(User)
          adsl
          assert_equal Set[:read, :create, :delete], spec.ac_rules.first.ops
        end
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            authenticable class User {}
            usergroup ug
            permit ug edit, edit, delete allof(User)
          adsl
          assert_equal Set[:create, :delete], spec.ac_rules.first.ops
        end
        assert_raises ADSLError do
          parser.parse <<-adsl
            class User {}
            permit ug erase allof(User)
          adsl
        end
      end
  
      def test_permit__unrolling_of_all_meta_ops
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
            action blah {
              a = permittedbytype(create Nonexistent)
            }
          adsl
        end
      end
  
    end
  end
end

