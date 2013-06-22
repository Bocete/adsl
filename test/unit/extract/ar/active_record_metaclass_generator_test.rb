require 'test/unit'
require 'extract/ar/active_record_metaclass_generator'
require 'pp'
require 'util/test_helper'
require 'active_record'

class ActiveRecordMetaclassGeneratorTest < Test::Unit::TestCase
  def setup
    assert_false class_defined? :Asd, :ADSLMetaAsd, :Kme, :ADSLMetaKme, :Blah, :ADSLMetaBlah, :Mod
    eval <<-ruby
      class Asd < ActiveRecord::Base
        has_one :asd
        has_many :kmes
      end

      class Kme < Asd
      end

      module Mod
        class Blah < ActiveRecord::Base
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
    
    generator = ActiveRecordMetaclassGenerator.new Kme
    assert_equal 'ADSLMetaKme', generator.target_classname
    
    generator = ActiveRecordMetaclassGenerator.new Mod::Blah
    assert_equal 'ADSLMetaBlah', generator.target_classname
  end

  def test_generate__links_superclasses_properly
    ActiveRecordMetaclassGenerator.new(Asd).generate_class

    assert_equal Object, ActiveRecordMetaclassGenerator.new(Asd).target_superclass
    assert_equal ADSLMetaAsd, ActiveRecordMetaclassGenerator.new(Kme).target_superclass
    assert_equal Object, ActiveRecordMetaclassGenerator.new(Mod::Blah).target_superclass
  end

  def test_generate__creates_the_correct_classes_in_correct_modules
    ActiveRecordMetaclassGenerator.new(Asd).generate_class
    ActiveRecordMetaclassGenerator.new(Kme).generate_class
    ActiveRecordMetaclassGenerator.new(Mod::Blah).generate_class

    assert self.class.const_defined? :ADSLMetaAsd
    assert self.class.const_defined? :ADSLMetaKme
    assert Mod.const_defined? :ADSLMetaBlah
  end
  
  def test_generate__metaclasses_create_instances_with_association_accessors
    ActiveRecordMetaclassGenerator.new(Asd).generate_class
    ActiveRecordMetaclassGenerator.new(Kme).generate_class
    ActiveRecordMetaclassGenerator.new(Mod::Blah).generate_class

    assert ADSLMetaAsd.new.respond_to? :asd
    assert ADSLMetaAsd.new.respond_to? :kmes
    
    assert ADSLMetaKme.new.respond_to? :asd
    assert ADSLMetaKme.new.respond_to? :kmes
  end
end
