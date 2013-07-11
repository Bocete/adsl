require 'test/unit'
require 'pp'
require 'active_record'
require 'adsl/util/test_helper'
require 'adsl/parser/ast_nodes'
require 'adsl/extract/rails/active_record_metaclass_generator'
require 'adsl/extract/rails/rails_test_helper'

module ADSL::Extract::Rails
  class ActiveRecordMetaclassGeneratorTest < Test::Unit::TestCase

    include ADSL::Parser

    def setup
      assert_false class_defined? :ADSLMetaAsd, :ADSLMetaKme, 'Mod::ADSLMetaBlah'
      initialize_test_context
    end

    def teardown
      unload_class :ADSLMetaAsd, :ADSLMetaKme, 'Mod::ADSLMetaBlah'
    end

    def test_target_classname
      generator = ActiveRecordMetaclassGenerator.new Asd
      assert_equal 'ADSLMetaAsd', generator.target_classname
      assert_equal 'ADSLMetaTesting', ActiveRecordMetaclassGenerator.target_classname('Testing')
      
      generator = ActiveRecordMetaclassGenerator.new Kme
      assert_equal 'ADSLMetaKme', generator.target_classname
      
      generator = ActiveRecordMetaclassGenerator.new Mod::Blah
      assert_equal 'ADSLMetaBlah', generator.target_classname
    end

    def test_generate__links_superclasses_properly
      ActiveRecordMetaclassGenerator.new(Asd).generate_class

      assert_equal Asd, ActiveRecordMetaclassGenerator.new(Asd).target_superclass
      assert_equal ADSLMetaAsd, ActiveRecordMetaclassGenerator.new(Kme).target_superclass
      assert_equal Mod::Blah, ActiveRecordMetaclassGenerator.new(Mod::Blah).target_superclass
    end

    def test_generate__creates_the_correct_classes_in_correct_modules
      ActiveRecordMetaclassGenerator.new(Asd).generate_class
      ActiveRecordMetaclassGenerator.new(Kme).generate_class
      ActiveRecordMetaclassGenerator.new(Mod::Blah).generate_class

      assert self.class.const_defined? :ADSLMetaAsd
      assert self.class.const_defined? :ADSLMetaKme
      assert Mod.const_defined? :ADSLMetaBlah
    end
    
    def test_generate__class_method_defined__all
      ActiveRecordMetaclassGenerator.new(Asd).generate_class
      ActiveRecordMetaclassGenerator.new(Kme).generate_class
      ActiveRecordMetaclassGenerator.new(Mod::Blah).generate_class

      assert ADSLMetaAsd.respond_to? :all
      assert_equal ADSLMetaAsd, ADSLMetaAsd.all.class
      assert_equal ASTAllOf, ADSLMetaAsd.all.adsl_ast.class
    end
    
    def test_generate__metaclasses_create_instances_with_association_accessors
      ActiveRecordMetaclassGenerator.new(Asd).generate_class
      ActiveRecordMetaclassGenerator.new(Kme).generate_class
      ActiveRecordMetaclassGenerator.new(Mod::Blah).generate_class

      asd = ADSLMetaAsd.new :adsl_ast => nil
      assert asd.respond_to? :blahs
      assert_equal Mod::ADSLMetaBlah, asd.blahs.class
      
      blah = Mod::ADSLMetaBlah.new :adsl_ast => nil
      assert blah.respond_to? :asd
      assert_equal ADSLMetaAsd, blah.asd.class
    end
  end
end
