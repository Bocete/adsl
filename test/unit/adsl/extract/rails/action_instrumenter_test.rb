require 'test/unit'
require 'active_record'
require 'ruby_parser'
require 'ruby2ruby'
require 'adsl/util/test_helper'
require 'adsl/extract/rails/action_instrumenter'
require 'adsl/extract/rails/rails_test_helper'
require 'adsl/extract/rails/rails_instrumentation_test_case'

class ADSL::Extract::ActionInstrumenterTest < ADSL::Extract::Rails::RailsInstrumentationTestCase

  def test__replaces_activerecord_names
    instrumenter = ADSL::Extract::Rails::ActionInstrumenter.new ar_class_names, File.join(Dir.pwd, '/test/unit').to_s
    input_code = <<-rails
      def blah
        Asd.all.something Kme.all, Mod::Blah.find, Asd
      end
    rails
    
    resulting_code = Ruby2Ruby.new.process instrumenter.instrument_sexp(RubyParser.new.process input_code)

    assert_equal 4, resulting_code.scan(/ADSLMeta/).length
    assert_equal 2, resulting_code.scan(/ADSLMetaAsd/).length
    assert_equal 2, resulting_code.scan(/Asd/).length
    assert_equal 1, resulting_code.scan(/ADSLMetaKme/).length
    assert_equal 1, resulting_code.scan(/Kme/).length
    assert_equal 1, resulting_code.scan(/Mod::ADSLMetaBlah/).length
    assert_equal 0, resulting_code.scan(/Mod::Blah/).length
  end
  
  def test__assignments_assign_to_metavariables
    instrumenter = ADSL::Extract::Rails::ActionInstrumenter.new ar_class_names, File.join(Dir.pwd, '/test/unit').to_s
    input_code = <<-rails
      def blah
        a = 5
        b = :kme
      end
    rails
    instrumented_sexp = instrumenter.instrument_sexp(RubyParser.new.process input_code)
    resulting_code = Ruby2Ruby.new.process instrumented_sexp

    assert_equal 2, resulting_code.scan(/Extract::Rails::MetaVariable/).length
  end

end
