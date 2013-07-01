require 'test/unit'
require 'extract/rails/active_record_metaclass_generator'
require 'pp'
require 'util/test_helper'
require 'active_record'
require 'activerecord-tableless'
require 'parser/adsl_ast'

class ActiveRecordMetaclassGeneratorTest < Test::Unit::TestCase
  include Extract::Rails
  
  def setup
    assert_false class_defined? :Asd, :ADSLMetaAsd, :Kme, :ADSLMetaKme, :Blah, :ADSLMetaBlah, :Mod
    eval <<-ruby
      class Asd < ActiveRecord::Base
        has_no_table
        has_one :asd
        has_many :kmes
      end

      class Kme < Asd
        has_no_table
      end

      module Mod
        class Blah < ActiveRecord::Base
          has_no_table
        end
      end
    ruby
  end

  def teardown
    unload_class :Asd, :ADSLMetaAsd, :Kme, :ADSLMetaKme, :Blah, :ADSLMetaBlah, :Mod
  end

  def test_target_classname
    generator = ActiveRecordMetaclassGenerator.new Asd
    assert_equal 'ADSLMetaAsd', generator.target_classname
    assert_equal 'ADSLMetaTesting', generator.target_classname('Testing')
    
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
    assert_equal ADSL::ADSLAllOf, ADSLMetaAsd.all.adsl_ast.class
  end
  
  def test_generate__metaclasses_create_instances_with_association_accessors
    ActiveRecordMetaclassGenerator.new(Asd).generate_class
    ActiveRecordMetaclassGenerator.new(Kme).generate_class
    ActiveRecordMetaclassGenerator.new(Mod::Blah).generate_class

    assert ADSLMetaAsd.new.respond_to? :asd
    assert_equal ADSLMetaAsd, ADSLMetaAsd.new.asd.class
    assert ADSLMetaAsd.new.respond_to? :kmes
    assert_equal ADSLMetaKme, ADSLMetaAsd.new.kmes.class
    
    assert ADSLMetaKme.new.respond_to? :asd
    assert_equal ADSLMetaAsd, ADSLMetaKme.new.asd.class
    assert ADSLMetaKme.new.respond_to? :kmes
    assert_equal ADSLMetaKme, ADSLMetaKme.new.kmes.class
  end
end
