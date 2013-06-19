require 'test/unit'
require 'util/test_helper'
require 'fol/first_order_logic'

class TestHelperTest < Test::Unit::TestCase
  def test_adsl_assert__plain
    adsl_assert :correct, <<-ADSL
      class Class {}
      action Action() {}
      invariant true
    ADSL
  end

  def test_adsl_assert__custom_conjecture
    adsl_assert :correct, <<-ADSL
      class Class {}
      action Action() {}
      invariant true
    ADSL
    adsl_assert :correct, <<-ADSL, :conjecture => true
      class Class {}
      action Action() {}
    ADSL
    adsl_assert :incorrect, <<-ADSL, :conjecture => false
      class Class {}
      action Action() {}
    ADSL
  end

  def test_class_defined__basic
    assert_false class_defined? :TestClassDefinedBasic
    eval <<-ruby
      class TestClassDefinedBasic
      end
    ruby
    assert_true class_defined? :TestClassDefinedBasic
  end

  def test_class_defined__multiple
    assert_false class_defined? :Multiple1, :Multiple2
    eval <<-ruby
      class Multiple1
      end
    ruby
    assert_true class_defined? :Multiple1, :Multiple2
  end
  
  def test_unload_class__classes_unload
    assert_false class_defined? :TestUnloadClassClassesUnload
    eval <<-ruby
      class TestUnloadClassClassesUnload
      end
    ruby
    assert class_defined? :TestUnloadClassClassesUnload
    unload_class :TestUnloadClassClassesUnload
    assert_false class_defined? :TestUnloadClassClassesUnload
  end

  def test_unload_class__methods_get_removed
    assert_false class_defined? :TestUnloadClassMethodsGetRemoved
    eval <<-ruby
      class TestUnloadClassMethodsGetRemoved
        def a; end
      end
    ruby
    assert class_defined? :TestUnloadClassMethodsGetRemoved
    assert self.class.const_get(:TestUnloadClassMethodsGetRemoved).method_defined?('a')
    unload_class :TestUnloadClassMethodsGetRemoved
    assert_false class_defined? :TestUnloadClassMethodsGetRemoved
    eval <<-ruby
      class TestUnloadClassMethodsGetRemoved
      end
    ruby
    assert class_defined? :TestUnloadClassMethodsGetRemoved
    assert_false self.class.const_get(:TestUnloadClassMethodsGetRemoved).methods.include?('a')
  end
  
end
