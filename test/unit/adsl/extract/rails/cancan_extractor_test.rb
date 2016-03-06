require 'adsl/util/test_helper'
require 'adsl/lang/ast_nodes'
require 'adsl/extract/rails/cancan_extractor'
require 'adsl/extract/rails/rails_extractor'
require 'adsl/extract/rails/rails_test_helper'
require 'adsl/extract/rails/rails_instrumentation_test_case'

class ADSL::Extract::Rails::CanCanExtractorTest < ADSL::Extract::Rails::RailsInstrumentationTestCase
  include ::ADSL::Lang

  def setup
    super
    define_cancan_suite
    Ability.class_exec do
      def initialize(user)
        alias_action :read, :to => :onlyread
        can :onlyread, Asd
        if user.is_admin
          can :manage, :all
        else
          can :manage, Asd, :user => user
          can :manage, User, :id => user.id
        end
      end
    end
  end

  def teardown
    teardown_cancan_suite
    super
  end

  def assert_class_level_auth_check(node)
    assert_equal ASTOr,           node.class
    assert_equal 2,               node.subformulae.length
    assert_equal ASTInUserGroup,  node.subformulae[0].class
    assert_equal 'admin',         node.subformulae[0].groupname.text
    assert_equal ASTInUserGroup,  node.subformulae[1].class
    assert_equal 'nonadmin',      node.subformulae[1].groupname.text
  end

  def assert_variable_read_auth_check(node, var_name, op)
    assert_equal ASTOr, node.class
    assert_equal 2,     node.subformulae.length

    node.subformulae.each do |sub|
      assert_equal ASTAnd,         sub.class
      assert_equal 2,              sub.subformulae.length
      assert_equal ASTInUserGroup, sub.subformulae[0].class
    end

    if node.subformulae.first.subformulae[0].groupname.text == 'admin'
      option1, option2 = node.subformulae
    else
      option2, option1 = node.subformulae
    end

    assert_equal 'admin',         option1.subformulae[0].groupname.text
    assert_equal ASTIn,           option1.subformulae[1].class
    assert_equal ASTVariableRead, option1.subformulae[1].objset1.class
    assert_equal var_name,        option1.subformulae[1].objset1.var_name.text
    assert_equal ASTAllOf,        option1.subformulae[1].objset2.class
    assert_equal 'Asd',           option1.subformulae[1].objset2.class_name.text

    assert_equal 'nonadmin',      option2.subformulae[0].groupname.text
    assert_equal ASTIn,           option2.subformulae[1].class
    assert_equal ASTVariableRead, option2.subformulae[1].objset1.class
    assert_equal var_name,        option2.subformulae[1].objset1.var_name.text

    if op == :read
      assert_equal ASTUnion,        option2.subformulae[1].objset2.class
      assert_equal ASTAllOf,        option2.subformulae[1].objset2.objsets[0].class
      assert_equal 'Asd',           option2.subformulae[1].objset2.objsets[0].class_name.text
      assert_equal ASTMemberAccess, option2.subformulae[1].objset2.objsets[1].class
      assert_equal 'asds',          option2.subformulae[1].objset2.objsets[1].member_name.text
      assert_equal ASTCurrentUser,  option2.subformulae[1].objset2.objsets[1].objset.class
    else
      assert_equal ASTMemberAccess, option2.subformulae[1].objset2.class
      assert_equal 'asds',          option2.subformulae[1].objset2.member_name.text
      assert_equal ASTCurrentUser,  option2.subformulae[1].objset2.objset.class
    end
  end

  def test_setup_and_teardown
    extractor = create_rails_extractor
    ast = extractor.adsl_ast

    assert_equal 4, ast.classes.length
    
    userNode = ast.classes.select{ |c| c.name.text == 'User' }.first
    assert userNode
    assert userNode.authenticable

    assert_equal 2, ast.usergroups.length
    assert_set_equal %w|admin nonadmin|, ast.usergroups.map(&:name).map(&:text)
  end

  def test_policy_set
    extractor = create_rails_extractor
    ast = extractor.adsl_ast

    permits = ast.ac_rules.sort_by{ |a| a.group_names.map(&:text).sort.join('') }

    assert_equal 7, permits.length

    ['Asd', 'Kme', 'Mod_Blah', 'User'].each_index do |class_name, i|
      assert_equal     ['admin'],                 permits[i].group_names.map(&:text)
      assert_set_equal [:create, :delete, :read], permits[i].ops
      assert_equal     ASTAllOf,                  permits[i].expr.class
      assert_equal     class_name,                permits[i].expr.class_name.text
    end
    
    assert_equal ['nonadmin'],    permits[4].group_names.map(&:text)
    assert_equal [:read],         permits[4].ops
    assert_equal ASTAllOf,        permits[4].expr.class
    assert_equal 'Asd',           permits[4].expr.class_name.text

    assert_equal     ['nonadmin'],              permits[5].group_names.map(&:text)
    assert_set_equal [:create, :delete, :read], permits[5].ops
    assert_equal     ASTCurrentUser,            permits[5].expr.class

    assert_equal     ['nonadmin'],       permits[6].group_names.map(&:text)
    assert_set_equal [:create, :delete], permits[6].ops
    assert_equal     ASTMemberAccess,    permits[6].expr.class
    assert_equal     'asds',             permits[6].expr.member_name.text
    assert_equal     ASTCurrentUser,     permits[6].expr.objset.class
  end

  def test_currentuser_in_action
    AsdsController.class_exec do
      def nothing
        @user = current_user
        respond_to
      end
    end
   
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing) 

    assert_equal ASTAssignment,  ast.expr.class
    assert_equal 'at__user',     ast.expr.var_name.text
    assert_equal ASTCurrentUser, ast.expr.expr.class
  end

  def test_can_test_in_action
    AsdsController.class_exec do
      def nothing
        raise unless can? :create, User
        @user = User.new
        respond_to
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing) 

    assert_equal ASTBlock, ast.expr.class

    statements = ast.expr.exprs

    assert_equal 2,                statements.length
    assert_equal ASTAssertFormula, statements[0].class
    assert_class_level_auth_check  statements[0].formula
    assert_equal ASTAssignment,    statements[1].class
    assert_equal 'at__user',       statements[1].var_name.text
    assert_equal ASTCreateObjset,  statements[1].expr.class
    assert_equal 'User',           statements[1].expr.class_name.text
  end

  def test_can_manage_all_extracted
    extractor = create_rails_extractor
    ast = extractor.adsl_ast
    expected = ASTPermit.new(
      :expr => ASTAllOf.new(:class_name => ASTIdent.new(:text => 'Mod_Blah')),
      :ops => [:create, :delete, :read],
      :group_names => [ASTIdent.new(:text => 'admin')]
    )

    assert ast.ac_rules.include?(expected)
  end

  def test_authorize_resource_ensures_permissions
    AsdsController.class_exec do
      authorize_resource

      def create
        Asd.new
        respond_to
      end
    end
    
    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create)

    assert_equal ASTBlock, ast.expr.class
    statements = ast.expr.exprs

    assert_equal 2, statements.length

    assert_equal ASTAssertFormula, statements[0].class
    assert_class_level_auth_check  statements[0].formula
    assert_equal ASTCreateObjset,  statements[1].class
  end

  def test_authorize_resource_doesnt_persist_between_tests
    # authorize resource and ensure resource is authorized
    test_authorize_resource_ensures_permissions

    teardown
    setup

    # ensure authorize resource does not happen after teardown and setup
    AsdsController.class_exec do
      def create
        Asd.new
        respond_to
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create)

    assert_equal ASTCreateObjset, ast.expr.class

    teardown
    setup

    # ensure authorize resource can be reenabled
    test_authorize_resource_ensures_permissions
  end

  def test_load_and_authorize_loads_and_authorizes_show
    AsdsController.class_exec do
      load_and_authorize_resource
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :show)

    assert_equal ASTBlock, ast.expr.class

    statements = ast.expr.exprs
    assert_equal 2, statements.length
    
    assert_equal ASTAssignment, statements[0].class
    assert_equal ASTOneOf,      statements[0].expr.class
    assert_equal ASTAllOf,      statements[0].expr.objset.class
    assert_equal 'Asd',         statements[0].expr.objset.class_name.text

    assert_equal ASTAssertFormula,  statements[1].class
    assert_variable_read_auth_check statements[1].formula, 'at__asd', :read
  end

  def test_load_and_authorize_loads_and_authorizes_index
    AsdsController.class_exec do
      load_and_authorize_resource
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :index)

    assert_equal ASTBlock, ast.expr.class
    statements = ast.expr.exprs
    assert_equal 2, statements.length
    
    assert_equal ASTAssignment, statements[0].class
    assert_equal ASTSubset,     statements[0].expr.class
    assert_equal ASTAllOf,      statements[0].expr.objset.class
    assert_equal 'Asd',         statements[0].expr.objset.class_name.text

    assert_equal ASTAssertFormula,  statements[1].class
    assert_variable_read_auth_check statements[1].formula, 'at__asds', :read
  end

  def test_load_and_authorize_loads_and_authorizes_create
    AsdsController.class_exec do
      load_and_authorize_resource
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create)

    assert_equal ASTBlock, ast.expr.class

    statements = ast.expr.exprs
    assert_equal 2, statements.length

    assert_equal ASTAssignment,   statements[0].class
    assert_equal ASTCreateObjset, statements[0].expr.class
    assert_equal 'Asd',           statements[0].expr.class_name.text

    assert_equal ASTAssertFormula,  statements[1].class
    assert_variable_read_auth_check statements[1].formula, 'at__asd', :create
  end

  def test_load_and_authorize_loads_and_authorizes_create_with_recreation
    AsdsController.class_exec do
      load_and_authorize_resource

      def create
        @asd = Asd.build params
      end
    end

    extractor = create_rails_extractor
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create)

    assert_equal ASTBlock, ast.expr.class

    statements = ast.expr.exprs
    assert_equal 2, statements.length
    
    assert_equal ASTAssignment,   statements[0].class
    assert_equal ASTCreateObjset, statements[0].expr.class
    assert_equal 'Asd',           statements[0].expr.class_name.text

    assert_equal ASTAssertFormula,  statements[1].class
    assert_variable_read_auth_check statements[1].formula, 'at__asd', :create
  end
end
