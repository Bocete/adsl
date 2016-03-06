require 'adsl/util/test_helper'
require 'active_record'
require 'ruby_parser'
require 'ruby2ruby'
require 'adsl/extract/rails/action_instrumenter'
require 'adsl/extract/rails/rails_test_helper'
require 'adsl/extract/rails/method'
require 'adsl/extract/rails/rails_instrumentation_test_case'

class ADSL::Extract::ActionInstrumenterTest < ADSL::Extract::Rails::RailsInstrumentationTestCase
  include ADSL::Lang::Parser
  include ADSL::Extract::Rails

  def test__local_instance_class_variables_differ
    instrumenter = ADSL::Extract::Rails::ActionInstrumenter.new ar_class_names, File.join(Dir.pwd, '/test/unit').to_s
    input_code = <<-rails
      def blah
        a = 1
        @a = 2
        @@a = 3
        return a, @a, @@a
      end
    rails

    Asd.class_eval input_code
    Kme.class_eval input_code

    asd, kme = Asd.new, Kme.new
    asd_values = asd.blah
    kme_values = instrumenter.execute_instrumented kme, :blah

    assert_equal [1, 2, 3], asd_values
    assert_equal [1, 2, 3], kme_values

    assert_equal 2, asd.instance_variable_get(:@a)
    assert_equal 3, Asd.class_variable_get(:@@a)

    assert_equal 2, kme.instance_variable_get(:@a)
    assert_equal 3, Kme.class_variable_get(:@@a)
  end

  def test__multiassign_simple
    instrumenter = ADSL::Extract::Rails::ActionInstrumenter.new ar_class_names, File.join(Dir.pwd, '/test/unit').to_s
    input_codes = {
      "def blah; @a, @b, @c = 1, 2, 3; end" => [1, 2, 3],
      "def blah; @a, @b, @c = 4, 5; end" => [4, 5, nil],
      "def blah; @a, @b = 6, 7, 8; end" => [6, 7, nil],
      "def call3; [8, 9, 10]; end; def blah; @a, @b, @c = call3; end" => [8, 9, 10],
      "def call2; [11, 12]; end; def blah; @a, @b, @c = call2; end" => [11, 12, nil],
      "def blah; @a, @b = [13, 14]; end" => [13, 14, nil],
      "def blah; @a, @b = [[15, 16], 17]; end" => [[15, 16], 17, nil]
    }
    input_codes.each do |code, expected_results|
      Asd.class_eval code
      Kme.class_eval code

      asd, kme = Asd.new, Kme.new
      asd.blah
      instrumenter.execute_instrumented kme, :blah

      assert_equal expected_results[0], asd.instance_variable_get(:@a), code
      assert_equal expected_results[1], asd.instance_variable_get(:@b), code
      assert_equal expected_results[2], asd.instance_variable_get(:@c), code

      assert_equal expected_results[0], kme.instance_variable_get(:@a), code
      assert_equal expected_results[1], kme.instance_variable_get(:@b), code
      assert_equal expected_results[2], kme.instance_variable_get(:@c), code
    end
  end

end
