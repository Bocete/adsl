require 'test/unit'
require 'ds/data_store_spec'
require 'pp'

class DataStoreSpecTest < Test::Unit::TestCase
  def test_replace
    assignment = DS::DSAssignment.new :var => :kme, :objset => :objset
    for_each = DS::DSForEach.new :objset => :kme, :block => DS::DSBlock.new
    block = DS::DSBlock.new :statements => [assignment, for_each]

    assert block.replace(:kme, :replaced)
    assert_false block.replace(:kme, :replaced)

    assert_equal assignment, block.statements[0]
    assert_equal for_each, block.statements[1]

    assert_equal :replaced, assignment.var
    assert_equal :replaced, for_each.objset
  end

  def test_replace__safe_against_recursion
    block = DS::DSBlock.new :statements => []
    block.statements << block
    assert_false block.replace :kme, :kme

    block.statements << :kme

    assert block.replace :kme, :replaced
    assert_equal :replaced, block.statements.last
  end

  def test_class__superclass_of
    parent = DS::DSClass.new :name => 'parent'
    child1 = DS::DSClass.new :name => 'child1', :parent => parent
    child2 = DS::DSClass.new :name => 'child2', :parent => parent
    grandchild = DS::DSClass.new :name => 'grandchild', :parent => child1
    
    assert parent.superclass_of? parent
    assert parent.superclass_of? child1
    assert parent.superclass_of? child2
    assert parent.superclass_of? grandchild

    assert !child1.superclass_of?(parent)
    assert !child2.superclass_of?(parent)
    assert !grandchild.superclass_of?(parent)

    assert child1.superclass_of? child1
    assert child1.superclass_of? grandchild
    assert !child1.superclass_of?(child2)

    assert !child2.superclass_of?(child1)
    assert !child2.superclass_of?(grandchild)
  end
end
