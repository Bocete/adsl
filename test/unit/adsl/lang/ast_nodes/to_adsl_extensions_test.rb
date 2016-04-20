require 'adsl/util/test_helper'
require 'adsl/util/general'
require 'adsl/lang/ast_nodes'
require 'set'

class ADSL::Lang::ASTNodeToADSLExtensionsTest < ActiveSupport::TestCase
  include ADSL::Lang

  def assert_leading_whitespace_equal(expected, actual)
    raise unless expected.is_a?(String) && actual.is_a?(String)
    
    expected_wlws = expected.without_leading_whitespace.rstrip
    actual_wlws   = actual.without_leading_whitespace

    assert_equal expected_wlws, actual_wlws
  end

  def block(*args)
    ASTBlock.new :exprs => args
  end

  def create_objset(klass = "Klass")
    ASTCreateObjset.new :class_name => ASTIdent[klass]
  end

  def empty
    ASTEmptyObjset.new
  end

  def test_create_objset_to_adsl
    node = create_objset 'AsdKme'
    assert_leading_whitespace_equal <<-adsl, node.to_adsl
      create AsdKme
    adsl
  end

  def test_block_to_adsl
    node = block empty, empty
    assert_leading_whitespace_equal <<-adsl, node.to_adsl
      {
        empty
        empty
      }
    adsl
  end

  def test_if_to_adsl
    node = ASTIf.new :condition => ASTBoolean.new, :then_expr => create_objset('Asd'), :else_expr => block(create_objset 'Kme')
    assert_leading_whitespace_equal <<-adsl, node.to_adsl
      if (*) {
        create Asd
      } else {
        create Kme
      }
    adsl
  end

  def test_if_not_to_adsl
    node = ASTIf.new :condition => ASTBoolean.new, :then_expr => block, :else_expr => block(create_objset 'Kme')
    assert_leading_whitespace_equal <<-adsl, node.to_adsl
      if not (*) {
        create Kme
      }
    adsl
  end

  def test_block_nesting
    node = block(block, block(create_objset, create_objset, block(create_objset), block(empty)))
    assert_leading_whitespace_equal <<-adsl, node.to_adsl
      {
        {}
        {
          create Klass
          create Klass
          {
            create Klass
          }
          {
            empty
          }
        }
      }
    adsl
  end

  def test_return_guard_nesting
    node = ASTReturnGuard.new :expr => block(ASTReturn.new :expr => ASTAllOf.new(:class_name => ASTIdent['Asd']))
    assert_leading_whitespace_equal <<-adsl, node.to_adsl
      returnguard {
        return Asd
      }
    adsl
  end

end
