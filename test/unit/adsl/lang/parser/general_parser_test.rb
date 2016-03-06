require 'adsl/util/test_helper'
require 'adsl/lang/parser/adsl_parser.tab'

module ADSL::Lang::Parser
  class GeneralParserTest < ActiveSupport::TestCase

    def test_comments_single_line
      parser = ADSLParser.new
     
      ['#', '//'].each do |commentchar|
        spec = parser.parse <<-ADSL
          class Class1 {}
          #{commentchar} class Class1 {}
          class Class2
          #{commentchar} class Class3
          {} #{commentchar}#{commentchar} class Class4 {}
          #{commentchar}#{commentchar}
          #{commentchar}
        ADSL
        assert_equal ['Class1', 'Class2'], spec.classes.map{ |c| c.name }

        spec = parser.parse <<-ADSL
          #{commentchar} class Class1 {}
        ADSL
        assert spec.classes.empty?
      end
    end

    def test_comments_multi_line
      parser = ADSLParser.new

      spec = parser.parse <<-ADSL
        class Class1 {}
        /* class Class2 {} */
      ADSL
      assert_equal ['Class1'], spec.classes.map{ |c| c.name }

      spec = parser.parse <<-ADSL
        class Class1 /*
        */ {} /*
        */ class Class2 {}
      ADSL
      assert_equal ['Class1', 'Class2'], spec.classes.map{ |c| c.name }
    end

    def test_different_comment_types_dont_interfere
      parser = ADSLParser.new

      spec = parser.parse <<-ADSL
        class Class1 {}
        /* // */
        class Class2 {}
        /* # */
      ADSL
      assert_equal ['Class1', 'Class2'], spec.classes.map{ |c| c.name }

      spec = parser.parse <<-ADSL
        // /*
        class Class1 {}
        # */
      ADSL
      assert_equal ['Class1'], spec.classes.map{ |c| c.name }
    end
  end
end
