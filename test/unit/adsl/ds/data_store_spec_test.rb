require 'adsl/util/test_helper'
require 'adsl/ds/data_store_spec'

class ADSL::DS::DataStoreSpecTest < ActiveSupport::TestCase
  def test_replace
    assignment = ADSL::DS::DSAssignment.new :var => :kme, :expr => :objset
    for_each = ADSL::DS::DSForEach.new :objset => :kme, :block => ADSL::DS::DSBlock.new
    block = ADSL::DS::DSBlock.new :statements => [assignment, for_each]

    assert block.replace(:kme, :replaced)
    assert_false block.replace(:kme, :replaced)

    assert_equal assignment, block.statements[0]
    assert_equal for_each, block.statements[1]

    assert_equal :replaced, assignment.var
    assert_equal :replaced, for_each.objset
  end

  def test_replace__safe_against_recursion
    block = ADSL::DS::DSBlock.new :statements => []
    block.statements << block
    assert_false block.replace :kme, :kme

    block.statements << :kme

    assert block.replace :kme, :replaced
    assert_equal :replaced, block.statements.last
  end
end
