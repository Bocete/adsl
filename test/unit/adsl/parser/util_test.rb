require 'adsl/util/test_helper'
require 'adsl/parser/util'
require 'adsl/ds/data_store_spec'
require 'adsl/parser/ast_nodes'
require 'set'

class ADSL::Parser::AstNodesTest < ActiveSupport::TestCase
  include ADSL::Parser
  include ADSL::DS

  def test_action__context_difference
    context1 = ASTTypecheckResolveContext.new
    context1.push_frame

    klass = DSClass.new :name => 'klass'
    sig = TypeSig::ObjsetType.new klass

    a1 = DSVariable.new :name => 'a', :type_sig => sig
    a2 = DSVariable.new :name => 'a', :type_sig => sig
    b1 = DSVariable.new :name => 'b', :type_sig => sig
    b2 = DSVariable.new :name => 'b', :type_sig => sig

    context1.define_var a1, true
    context1.define_var b1, true

    context2 = context1.dup

    context2.redefine_var a2, false

    assert_equal({"a" => [a1, a2]}, Util.context_vars_that_differ(context1, context2))

    context3 = context2.dup
    assert_equal({"a" => [a1, a2, a2]}, Util.context_vars_that_differ(context1, context2, context3))

    context3.redefine_var b2, false
    assert_equal({"a" => [a1, a2, a2], "b" => [b1, b1, b2]}, Util.context_vars_that_differ(context1, context2, context3))
  end

end
