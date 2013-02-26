require "parser/adsl_parser.tab.rb"
require "test/unit"
require 'pp'

class ParserUtilTest < Test::Unit::TestCase
  def test_context__var_read_events
    context = ADSL::ADSLTypecheckResolveContext.new
    context.classes['class1'] = [:class1, :class1]
    context.actions['action1'] = [:action1, :action1]
    context.relations['class1'] = {"relation1" => [:relation1, :relation1]}
    context.push_frame
    var = DS::DSVariable.new :name => "varname", :type => :whatever
    context.define_var var, :node

    counter = 0

    context.on_var_read do |name|
      assert_equal "varname", name
      counter += 1
    end
   
    context.lookup_var "varname"
    
    assert_equal 1, counter

    context.push_frame
    context.on_var_read do |name|
      assert_equal "varname", name
      assert_equal counter, 1
      counter += 1
    end

    context.lookup_var "varname"
    assert_equal 3, counter

    context.pop_frame
    
    context.lookup_var "varname"
    assert_equal 4, counter
  end
  
  def test_context__var_write_events
    context = ADSL::ADSLTypecheckResolveContext.new
    context.classes['class1'] = [:class1, :class1]
    context.actions['action1'] = [:action1, :action1]
    context.relations['class1'] = {"relation1" => [:relation1, :relation1]}
    context.push_frame

    counter = 0

    context.on_var_write do |name|
      assert_equal "varname", name
      counter += 1
    end
    
    var = DS::DSVariable.new :name => "varname", :type => :whatever
    context.define_var var, :node
    
    assert_equal 1, counter

    context.push_frame
    context.on_var_write do |name|
      assert_equal "varname", name
      assert_equal counter, 1
      counter += 1
    end

    context.redefine_var var, :node
    assert_equal 3, counter

    context.pop_frame
    
    context.redefine_var var, :node
    assert_equal 4, counter
  end

  def test_context__clone
    context = ADSL::ADSLTypecheckResolveContext.new
    context.classes['class1'] = [:class1, :class1]
    context.actions['action1'] = [:action1, :action1]
    context.relations['class1'] = {"relation1" => [:relation1, :relation1]}
    context.push_frame
    var = DS::DSVariable.new :name => "varname", :type => :whatever
    context.define_var var, :node

    context2 = context.clone

    assert context != context2
    assert_equal [:class1, :class1], context2.classes.values.first
    assert_equal 1, context2.var_stack.length

    context2.on_var_write do |name|
      flunk
    end
    assert context.var_stack.last.var_write_listeners.empty?

    context.define_var DS::DSVariable.new(:name => 'other', :type => :whatever), :node2

    assert_equal 1, context2.var_stack.count
    assert_equal 1, context.var_stack.count
    assert_equal 2, context.var_stack.first.length
    assert_equal 1, context2.var_stack.first.length

    written = false
    context.on_var_write do |name|
      assert_equal "varname", name
      written = true
    end
    context.push_frame
    
    assert_equal 1, context2.var_stack.count
    assert_equal 2, context.var_stack.count

    context.redefine_var var, :node
    assert written
  end

  def test_var_writes_and_reads

  end
end
