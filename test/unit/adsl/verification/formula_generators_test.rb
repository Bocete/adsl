require 'test/unit'
require 'pp'
require 'adsl/extract/meta'
require 'adsl/util/test_helper'
require 'adsl/verification/formula_generators'
require 'adsl/verification/objset'

class ADSL::Verification::FormulaGeneratorsTest < Test::Unit::TestCase
  include ADSL::Verification::FormulaGenerators
  include ADSL::Parser
  include ADSL::Verification
  
  def setup
    eval <<-ruby
      class ::User; end
      class ::UserAddress; end
    ruby
  end

  def teardown
    unload_class :User, :UserAddress
  end

  def anything_with_adsl_ast
    o = Object.new
    o.define_singleton_method :adsl_ast do
      nil
    end
    o
  end

  def test_forall__raises_unless_return_value_has_an_adsl_ast
    forall do |user|
      anything_with_adsl_ast
    end
    assert_raise do
      forall do |user|
        'blah!'
      end
    end
  end

  def test_constants
    [true, self.true].each do |t|
      assert_equal true, t.adsl_ast.bool_value
      assert t.respond_to? :and
    end
    [false, self.false].each do |t|
      assert_equal false, t.adsl_ast.bool_value
      assert t.respond_to? :and
    end
  end

  def test_negation
    formula = self.not(true).adsl_ast
    assert_equal ASTNot, formula.class
    assert_equal true, formula.subformula.bool_value
    
    formula = neg(true).adsl_ast
    assert_equal ASTNot, formula.class
    assert_equal true, formula.subformula.bool_value
    
    formula = self.not.true.adsl_ast
    assert_equal ASTNot, formula.class
    assert_equal true, formula.subformula.bool_value
  end
  
  def test_quantification__explicit_types_from_block_params
    {:forall => ASTForAll, :exists => ASTExists}.each do |quantifier, klass|
      formula = send(quantifier, {:a => User}, &lambda do |a|
        assert_equal Objset, a.class
        assert_equal ASTVariable, a.adsl_ast.class
        assert_equal 'a', a.adsl_ast.var_name.text
        anything_with_adsl_ast
      end)
      assert_equal klass, formula.adsl_ast.class
      assert_equal 'User', formula.adsl_ast.vars[0][1].class_name.text

      formula = send(quantifier, {:a => User, :b => UserAddress}, &lambda do |a, b|
        assert_equal Objset, a.class
        assert_equal ASTVariable, a.adsl_ast.class
        assert_equal 'a', a.adsl_ast.var_name.text
        assert_equal Objset, b.class
        assert_equal ASTVariable, b.adsl_ast.class
        assert_equal 'b', b.adsl_ast.var_name.text
        anything_with_adsl_ast
      end)
      assert_equal klass, formula.adsl_ast.class
      assert_equal 'User', formula.adsl_ast.vars[0][1].class_name.text
      assert_equal 'UserAddress', formula.adsl_ast.vars[1][1].class_name.text
    end
  end

  def test_quantifiers__infer_types_from_block_params
    {:forall => ASTForAll, :exists => ASTExists}.each do |quantifier, klass|
      formula = send(quantifier, &lambda do |user|
        assert_equal Objset, user.class
        assert_equal ASTVariable, user.adsl_ast.class
        assert_equal 'user', user.adsl_ast.var_name.text
        anything_with_adsl_ast
      end)
      assert_equal klass, formula.adsl_ast.class
      assert_equal 'User', formula.adsl_ast.vars[0][1].class_name.text

      formula = send(quantifier, &lambda do |user, user_address|
        assert_equal Objset, user.class
        assert_equal ASTVariable, user.adsl_ast.class
        assert_equal 'user', user.adsl_ast.var_name.text
        assert_equal Objset, user_address.class
        assert_equal ASTVariable, user_address.adsl_ast.class
        assert_equal 'user_address', user_address.adsl_ast.var_name.text
        anything_with_adsl_ast
      end)
      assert_equal klass, formula.adsl_ast.class
      assert_equal 'User', formula.adsl_ast.vars[0][1].class_name.text
      assert_equal 'UserAddress', formula.adsl_ast.vars[1][1].class_name.text
    end
  end
  
  def test_quantifier__precedence_of_type_inferment_lesser_than_explicit_declaration
    {:forall => ASTForAll, :exists => ASTExists}.each do |quantifier, klass|
      formula = send(quantifier, {:user => UserAddress}, &lambda do |user|
        assert_equal Objset, user.class
        assert_equal ASTVariable, user.adsl_ast.class
        assert_equal 'user', user.adsl_ast.var_name.text
        anything_with_adsl_ast
      end)
      assert_equal klass, formula.adsl_ast.class
      assert_equal 'UserAddress', formula.adsl_ast.vars[0][1].class_name.text
    end
  end

  def test_quantifier__at_least_one_variable
    [:forall, :exists].each do |quantifier|
      assert_raise do
        send(quantifier, {}, &lambda do
          anything_with_adsl_ast
        end)
      end
    end
  end

  def test_quantifier__contains_the_subformula
    {:forall => ASTForAll, :exists => ASTExists}.each do |quantifier, klass|
      formula = send(quantifier, &lambda do |user|
        true
      end)
      assert_equal klass, formula.adsl_ast.class
      assert_equal true, formula.adsl_ast.subformula.bool_value
    end
  end

  def test_binary_operators__prefix
    {:implies => ASTImplies}.each do |operator, klass|
      formula = send(operator, true, self.false)
      assert_equal klass, formula.adsl_ast.class
      assert_equal true,  formula.adsl_ast.subformula1.bool_value
      assert_equal false, formula.adsl_ast.subformula2.bool_value
    end
  end
  
  def test_and_or__prefix_any_number_of_params
    {:and => ASTAnd, :or => ASTOr, :equiv => ASTEquiv}.each do |operator, klass|
      formula = send(operator, true, false)
      assert_equal klass, formula.adsl_ast.class
      assert_equal true,  formula.adsl_ast.subformulae.first.bool_value
      assert_equal false, formula.adsl_ast.subformulae.second.bool_value

      formula = send(operator, true, false, true, false)
      assert_equal klass, formula.adsl_ast.class
      assert_equal true,  formula.adsl_ast.subformulae[0].bool_value
      assert_equal false, formula.adsl_ast.subformulae[1].bool_value
      assert_equal true,  formula.adsl_ast.subformulae[2].bool_value
      assert_equal false, formula.adsl_ast.subformulae[3].bool_value
    end
  end

  def test_and_or__infix
    {:and => ASTAnd, :or => ASTOr}.each do |operator, klass|
      formula = true.send(operator).false
      assert_equal klass, formula.adsl_ast.class
      assert_equal true,  formula.adsl_ast.subformulae[0].bool_value
      assert_equal false, formula.adsl_ast.subformulae[1].bool_value
    end
  end
  
  def test_and_or__not_precedence
    {:and => ASTAnd, :or => ASTOr}.each do |operator, klass|
      formula = true.send(operator).not.false
      assert_equal klass, formula.adsl_ast.class
      assert_equal true,  formula.adsl_ast.subformulae[0].bool_value
      assert_equal ASTNot, formula.adsl_ast.subformulae[1].class
      
      formula = neg.true.send(operator).false
      assert_equal klass, formula.adsl_ast.class
      assert_equal ASTNot, formula.adsl_ast.subformulae[0].class
      assert_equal false, formula.adsl_ast.subformulae[1].bool_value
    end
  end
end
