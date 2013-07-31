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
      assert_equal 'Mod::ADSLMetaBlah', generator.target_classname
    end

    def test_adsl_ast_class_name
      ActiveRecordMetaclassGenerator.new(Asd).generate_class
      ActiveRecordMetaclassGenerator.new(Kme).generate_class
      ActiveRecordMetaclassGenerator.new(Mod::Blah).generate_class
      
      assert_equal 'Asd',      ADSLMetaAsd.adsl_ast_class_name
      assert_equal 'Kme',      ADSLMetaKme.adsl_ast_class_name
      assert_equal 'Mod_Blah', Mod::ADSLMetaBlah.adsl_ast_class_name
    end

    def test_generate__links_superclasses_properly
      ActiveRecordMetaclassGenerator.new(Asd).generate_class
      ActiveRecordMetaclassGenerator.new(Kme).generate_class
      ActiveRecordMetaclassGenerator.new(Mod::Blah).generate_class
      
      assert_equal Asd, ADSLMetaAsd.superclass
      assert_equal Kme, ADSLMetaKme.superclass
      assert_equal Mod::Blah, Mod::ADSLMetaBlah.superclass
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

    def test_generate__associations_adsl_ast
      ActiveRecordMetaclassGenerator.new(Asd).generate_class
      ActiveRecordMetaclassGenerator.new(Kme).generate_class
      ActiveRecordMetaclassGenerator.new(Mod::Blah).generate_class
      
      asd = ADSLMetaAsd.adsl_ast
      assert_equal 1, asd.relations.length
      assert_equal [0, 1.0/0.0], asd.relations.first.cardinality
      assert_equal 'Mod_Blah', asd.relations.first.to_class_name.text
      assert_equal 'blahs', asd.relations.first.name.text
      assert_equal 'asd', asd.relations.first.inverse_of_name.text

      kme = ADSLMetaKme.adsl_ast
      assert_equal 1, kme.relations.length
      assert_equal [0, 1], kme.relations.last.cardinality
      assert_equal 'Mod_Blah', kme.relations.last.to_class_name.text
      assert_equal 'blah', kme.relations.last.name.text
      assert_nil kme.relations.last.inverse_of_name

      blah = Mod::ADSLMetaBlah.adsl_ast
      assert_equal 2, blah.relations.length

      assert_equal [0, 1], blah.relations.first.cardinality
      assert_equal 'Asd', blah.relations.first.to_class_name.text
      assert_equal 'asd', blah.relations.first.name.text
      assert_nil blah.relations.first.inverse_of_name

      assert_equal [0, 1], blah.relations.second.cardinality
      assert_equal 'Kme', blah.relations.second.to_class_name.text
      assert_equal 'kme12', blah.relations.second.name.text
      assert_equal 'blah', blah.relations.second.inverse_of_name.text
    end

    def test_generate__associations_through
      ActiveRecordMetaclassGenerator.new(Asd).generate_class
      ActiveRecordMetaclassGenerator.new(Kme).generate_class
      ActiveRecordMetaclassGenerator.new(Mod::Blah).generate_class
     
      assert ADSLMetaAsd.adsl_ast.relations.select{ |rel| rel.name.text == 'kmes' }.empty?
      objset = ADSLMetaAsd.new :adsl_ast => :something_unique
      through = objset.kmes
      assert_equal ADSLMetaKme, through.class

      assert_equal ASTDereference, through.adsl_ast.class
      assert_equal 'kme12', through.adsl_ast.rel_name.text 
      assert_equal ASTDereference, through.adsl_ast.objset.class
      assert_equal 'blahs', through.adsl_ast.objset.rel_name.text 
      assert_equal :something_unique, through.adsl_ast.objset.objset
    end
  end
end
