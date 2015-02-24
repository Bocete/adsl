require 'adsl/parser/adsl_parser.tab'
require 'adsl/ds/data_store_spec'
require 'adsl/fol/first_order_logic'
require 'minitest/unit'
require 'minitest/autorun'
require 'pp'

module ADSL::Parser
  class RuleParserTest < MiniTest::Unit::TestCase
    include ADSL::Parser
    include ADSL::DS
    include ADSL::FOL
    
    def test_rule_formulas
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-ADSL
          class Class {}
          rule true
          action blah() {}
        ADSL
        assert_equal 1, spec.rules.length
        assert_equal ADSL::DS::DSConstant, spec.rules.first.formula.class
        assert_equal true, spec.rules.first.formula.value
      end
    end
  end
end
