require 'test/unit'
require 'parser/adsl_parser.tab'
require 'spass/bin'
require 'spass/spass_ds_extensions'
require 'spass/util'

class Test::Unit::TestCase
  include Spass::Bin
  include Spass::Util

  SPASS_TIMEOUT = 5
  
  def adsl_assert(expected_result, input, options={})
    ds_spec = ADSL::ADSLParser.new.parse input
    raise "Exactly one action required in ADSL" if ds_spec.actions.length != 1
    action_name = ds_spec.actions.first.name
    spass = ds_spec.translate_action(action_name)
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
end
