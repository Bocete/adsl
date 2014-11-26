require 'adsl/parser/adsl_parser.tab.rb'
require 'adsl/ds/type_sig'
require 'minitest/unit'

require 'minitest/autorun'
require 'pp'

module ADSL::Parser
  class ParserUtilTest < MiniTest::Unit::TestCase
    include ADSL::Parser
    include ADSL::DS

    def test_context__var_read_events
      context = ASTTypecheckResolveContext.new
      context.classes['class1'] = [:class1, :class1]
      context.actions['action1'] = [:action1, :action1]
      context.members['class1'] = {"relation1" => [:relation1, :relation1]}
      context.push_frame
      var = DSVariable.new :name => "varname", :type_sig => ADSL::DS::TypeSig::UNKNOWN
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
      context = ASTTypecheckResolveContext.new
      context.classes['class1'] = [:class1, :class1]
      context.actions['action1'] = [:action1, :action1]
      context.members['class1'] = {"relation1" => [:relation1, :relation1]}
      context.push_frame

      counter = 0

      context.on_var_write do |name|
        assert_equal "varname", name
        counter += 1
      end
      
      var = DSVariable.new :name => "varname", :type_sig => ADSL::DS::TypeSig::UNKNOWN
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
      context = ASTTypecheckResolveContext.new
      context.classes['class1'] = [:class1, :class1]
      context.actions['action1'] = [:action1, :action1]
      context.members['class1'] = {"relation1" => [:relation1, :relation1]}
      context.push_frame
      var = DSVariable.new :name => "varname", :type_sig => ADSL::DS::TypeSig::UNKNOWN
      context.define_var var, :node

      context2 = context.clone

      assert context != context2
      assert_equal [:class1, :class1], context2.classes.values.first
      assert_equal 1, context2.var_stack.length

      context2.on_var_write do |name|
        flunk
      end
      assert context.var_stack.last.var_write_listeners.empty?

      context.define_var DSVariable.new(:name => 'other', :type_sig => ADSL::DS::TypeSig::UNKNOWN), :node2

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
  end
end
