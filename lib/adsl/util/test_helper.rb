require 'test/unit'
require 'adsl/parser/adsl_parser.tab'
require 'adsl/spass/bin'
require 'adsl/spass/spass_ds_extensions'
require 'adsl/spass/util'
require 'adsl/util/general'

class Test::Unit::TestCase
  include ADSL::Spass::Bin
  include ADSL::Spass::Util

  SPASS_TIMEOUT = 5
  
  def adsl_assert(expected_result, input, options={})
    ds_spec = ADSL::Parser::ADSLParser.new.parse input
    raise "Exactly one action required in ADSL" if ds_spec.actions.length != 1
    action_name = ds_spec.actions.first.name
    spass = ds_spec.translate_action(action_name).to_spass_string
    spass = replace_conjecture spass, options[:conjecture] if options.include? :conjecture
    result = exec_spass(spass, options[:timeout] || SPASS_TIMEOUT)
    if result == :inconclusive
      puts "inconclusive result on testcase #{self.class.name}.#{method_name}"
    else
      assert_equal expected_result, result 
    end
  rescue Exception => e
    puts spass unless spass.nil?
    raise e
  end

  def spass_assert(expected_result, input, timeout = SPASS_TIMEOUT)
    adsl_assert expected_result, input, :timeout => timeout
  end

  def unload_class(*classes)
    classes.each do |klass_name|
      const = self.class.lookup_const klass_name
      next if const.nil?
      const.parent_module.send :remove_const, const.name.split('::').last
    end
  end

  def class_defined?(*classes)
    classes.each do |klass_name|
      return true unless self.class.lookup_const(klass_name).nil?
    end
    return false
  end

  def in_temp_file(content)
    Tempfile.with_tempfile content do |path|
      yield path
    end
  end

  def assert_set_equal(expected, actual, failure_msg = nil)
    expected.each do |elem|
      assert_block failure_msg || "Actual collection does not contain `#{elem}'" do
        actual.include? elem
      end
    end
    actual.each do |elem|
      assert_block failure_msg || "Expected collection does not contain `#{elem}'" do
        expected.include? elem
      end
    end
  end

  def assert_all_different(objects = {})
    counts = Hash.new{ |key, val| [] }
    objects.each{ |name, o| counts[o] << name }
    counts.each do |object, names|
      assert_equal 1, names.length, "Multiple identical objects found. Keys: #{ names.map(&:to_s).join(', ') }"
    end
  end
end
