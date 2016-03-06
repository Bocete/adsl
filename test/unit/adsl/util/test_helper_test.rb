require 'adsl/util/test_helper'
require 'adsl/fol/first_order_logic'

class ADSL::Util::TestHelperTest < ActiveSupport::TestCase
  def test_adsl_assert__plain
    adsl_assert :correct, <<-ADSL
      class Class {}
      action a {}
      invariant true
    ADSL
  end

  def test_adsl_assert__custom_conjecture
    adsl_assert :correct, <<-ADSL
      class Class {}
      action a {}
      invariant true
    ADSL
    adsl_assert :correct, <<-ADSL, :conjecture => true
      class Class {}
      action a {}
    ADSL
    adsl_assert :incorrect, <<-ADSL, :conjecture => false
      class Class {}
      action a {}
    ADSL
  end

  def test_class_defined__basic
    assert_false class_defined? :TestClassDefinedBasic
    eval <<-ruby
      class TestClassDefinedBasic
      end
    ruby
    assert class_defined? :TestClassDefinedBasic
  end

  def test_class_defined__multiple
    assert_false class_defined? :Multiple1, :Multiple2
    eval <<-ruby
      class Multiple1
      end
    ruby
    assert class_defined? :Multiple1, :Multiple2
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

  def test_unload_class__works_through_modules
    assert_false class_defined? '::Mod::TestUnloadClassWorksThroughModules'
    if Object.const_defined? :Mod
      assert_false class_defined? '::Mod::TestUnloadClassWorksThroughModules'
    end

    eval <<-ruby
      module ::Mod
        class TestUnloadClassWorksThroughModules
        end
      end
    ruby

    assert class_defined? '::Mod::TestUnloadClassWorksThroughModules'
    unload_class '::Mod::TestUnloadClassWorksThroughModules'
    assert_false class_defined? '::Mod::TestUnloadClassWorksThroughModules'
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

  def test_in_temp_file__block_called
    called = false
    in_temp_file "" do |path|
      called = true
    end
    assert called
  end
 
  def test_in_temp_file__content_there
    expected_content = "blah\nasd\n\n"
    in_temp_file expected_content do |path|
      file = File.open path, 'r'
      assert_equal expected_content, file.read
      file.close
    end
  end

  def test_in_temp_file__file_gone_after_call
    stored_path = nil
    in_temp_file "" do |path|
      stored_path = path
    end
    assert_false File.exists? stored_path
  end
end
