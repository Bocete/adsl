require 'adsl/util/test_helper'
require 'adsl/lang/ast_nodes'
require 'adsl/lang/parser/adsl_parser.tab'
require 'adsl/ds/data_store_spec'
require 'adsl/fol/first_order_logic'

module ADSL::Lang
  module Parser
    class RuleParserTest < ActiveSupport::TestCase
      
      def test_rule_formulas
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-ADSL
            class Class {}
            rule true
            action blah {}
          ADSL
          assert_equal 1, spec.rules.length
          assert_equal ADSL::DS::DSConstant, spec.rules.first.formula.class
          assert_equal true, spec.rules.first.formula.value
        end
      end
      
    end
  end
end
