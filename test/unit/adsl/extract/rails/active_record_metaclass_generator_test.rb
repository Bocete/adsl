require 'test/unit'
require 'pp'
require 'active_record'
require 'adsl/util/test_helper'
require 'adsl/parser/ast_nodes'
require 'adsl/extract/rails/active_record_metaclass_generator'
require 'adsl/extract/rails/rails_test_helper'
require 'adsl/extract/rails/rails_instrumentation_test_case'

module ADSL::Extract::Rails
  class ActiveRecordMetaclassGeneratorTest < RailsInstrumentationTestCase

    include ADSL::Parser

    def test_adsl_ast_class_name
      initialize_metaclasses
      
      assert_equal 'Asd',      Asd.adsl_ast_class_name
      assert_equal 'Kme',      Kme.adsl_ast_class_name
      assert_equal 'Mod_Blah', Mod::Blah.adsl_ast_class_name
    end

    def test_generate__class_method_defined__all
      initialize_metaclasses

      assert Asd.respond_to? :all
      assert_equal Asd, Asd.all.class
      assert_equal ASTAllOf, Asd.all.adsl_ast.class
    end
    
    def test_generate__metaclasses_create_instances_with_association_accessors
      initialize_metaclasses

      asd = Asd.new :adsl_ast => nil
      assert asd.respond_to? :blahs
      assert_equal Mod::Blah, asd.blahs.class
      
      blah = Mod::Blah.new :adsl_ast => nil
      assert blah.respond_to? :asd
      assert_equal Asd, blah.asd.class
    end

    def test_generate__associations_adsl_ast
      initialize_metaclasses
      
      asd = Asd.adsl_ast
      assert_equal 1, asd.relations.length
      assert_equal [0, 1.0/0.0], asd.relations.first.cardinality
      assert_equal 'Mod_Blah', asd.relations.first.to_class_name.text
      assert_equal 'blahs', asd.relations.first.name.text
      assert_equal 'asd', asd.relations.first.inverse_of_name.text

      kme = Kme.adsl_ast
      assert_equal 1, kme.relations.length
      assert_equal [0, 1], kme.relations.last.cardinality
      assert_equal 'Mod_Blah', kme.relations.last.to_class_name.text
      assert_equal 'blah', kme.relations.last.name.text
      assert_nil kme.relations.last.inverse_of_name

      blah = Mod::Blah.adsl_ast
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
      initialize_metaclasses
     
      assert Asd.adsl_ast.relations.select{ |rel| rel.name.text == 'kmes' }.empty?
      objset = Asd.new :adsl_ast => :something_unique
      through = objset.kmes
      assert_equal Kme, through.class

      assert_equal ASTDereference, through.adsl_ast.class
      assert_equal 'kme12', through.adsl_ast.rel_name.text 
      assert_equal ASTDereference, through.adsl_ast.objset.class
      assert_equal 'blahs', through.adsl_ast.objset.rel_name.text 
      assert_equal :something_unique, through.adsl_ast.objset.objset
    end

    def test_generate__delete_single_statements
      initialize_metaclasses

      asd_delete = Asd.new.delete
      assert_equal 1, asd_delete.length
      assert_equal ASTDeleteObj, asd_delete.first.class
      
      kme_delete = Kme.new.delete
      assert_equal 1, kme_delete.length
      assert_equal ASTDeleteObj, kme_delete.first.class
      
      blah_delete = Mod::Blah.new.delete
      assert_equal 1, blah_delete.length
      assert_equal ASTDeleteObj, blah_delete.first.class
    end

    def test_generate__destroy_propagates_to_delete_but_not_further
      initialize_metaclasses

      asd_delete = Mod::Blah.new(:adsl_ast => :blah).destroy
      assert_equal 2, asd_delete.length

      assert_equal ASTDeleteObj, asd_delete.first.class
      assert_equal ASTDereference, asd_delete.first.objset.class
      assert_equal 'kme12', asd_delete.first.objset.rel_name.text
      assert_equal :blah, asd_delete.first.objset.objset

      assert_equal ASTDeleteObj, asd_delete.last.class
      assert_equal :blah, asd_delete.last.objset
    end
    
    def test_generate__destroy_through_destroys_the_join_object
      initialize_metaclasses

      asd_delete = Asd.new(:adsl_ast => :blah).destroy
      assert_equal 3, asd_delete.length
      
      assert_equal ASTDeleteObj, asd_delete[0].class
      assert_equal ASTDereference, asd_delete[0].objset.class
      assert_equal ASTDereference, asd_delete[0].objset.objset.class
      assert_equal 'kme12', asd_delete[0].objset.rel_name.text
      assert_equal 'blahs', asd_delete[0].objset.objset.rel_name.text
      assert_equal :blah, asd_delete[0].objset.objset.objset

      assert_equal ASTDeleteObj, asd_delete[1].class
      assert_equal ASTDereference, asd_delete[1].objset.class
      assert_equal 'blahs', asd_delete[1].objset.rel_name.text
      assert_equal :blah, asd_delete[1].objset.objset
      
      assert_equal ASTDeleteObj, asd_delete[2].class
      assert_equal :blah, asd_delete[2].objset
    end
  
    def test_generate__include_subset_ops
      initialize_metaclasses
      
      asd = Asd.new :adsl_ast => ASTDummyObjset.new(:type => :blah)
      assert asd.respond_to? :include?
      assert asd.respond_to? :<=
      assert asd.respond_to? :>=
      
      kme = Kme.new :adsl_ast => ASTDummyObjset.new(:type => :blah2)

      subset = asd.include? kme
      assert_equal ASTIn, subset.class
      assert_equal :blah, subset.objset2.type
      assert_equal :blah2, subset.objset1.type

      subset = asd >= kme
      assert_equal ASTIn, subset.class
      assert_equal :blah, subset.objset2.type
      assert_equal :blah2, subset.objset1.type

      subset = asd <= kme
      assert_equal ASTIn, subset.class
      assert_equal :blah2, subset.objset2.type
      assert_equal :blah, subset.objset1.type
    end

    def test_generate__scopes_work_on_classes
      Asd.class_exec do
        scope :something_special, lambda{ where('id = ?', 4).order('id') }
      end
      assert Asd.respond_to? :something_special

      initialize_metaclasses

      assert Asd.respond_to? :something_special
      ss = Asd.something_special
      assert ss.respond_to? :adsl_ast

      assert_equal ASTSubset, ss.adsl_ast.class
      assert_equal ASTAllOf,  ss.adsl_ast.objset.class
      assert_equal 'Asd',     ss.adsl_ast.objset.class_name.text
    end
    
    def test_generate__scopes_work_on_relations
      Asd.class_exec do
        scope :something_special, lambda{ order('id') }
      end
      assert Asd.where('id < ?', 5).respond_to? :something_special

      initialize_metaclasses

      # make sure the scope does not do subset
      assert Asd.respond_to? :something_special
      assert_equal ASTAllOf, Asd.something_special.adsl_ast.class


      assert Asd.where('id = ?', 4).respond_to? :something_special
      ss = Asd.where('id = ?', 4).something_special

      assert_equal ASTSubset, ss.adsl_ast.class
      assert_equal ASTAllOf,  ss.adsl_ast.objset.class
      assert_equal 'Asd',     ss.adsl_ast.objset.class_name.text
    end

    def test_generate__conditions_scopes_work_on_classes
      Asd.class_exec do
        scope :something_special, :conditions => ["id < ?", 5]
      end
      assert Asd.respond_to? :something_special

      initialize_metaclasses

      assert Asd.respond_to? :something_special
      ss = Asd.something_special
      assert ss.respond_to? :adsl_ast

      assert_equal ASTSubset, ss.adsl_ast.class
      assert_equal ASTAllOf,  ss.adsl_ast.objset.class
      assert_equal 'Asd',     ss.adsl_ast.objset.class_name.text
    end

    def test_generate__scopes_through_associations
      Asd.class_exec do
        scope :asd_scope, lambda{ order('id') }
      end
      Mod::Blah.class_exec do
        scope :blah_scope, :conditions => ["id < ?", 5]
      end

      initialize_metaclasses

      assert_equal Mod::Blah, Asd.all.blahs.class
      assert_equal ASTDereference, Asd.all.blahs.adsl_ast.class

      ss = Asd.all.blahs.blah_scope.adsl_ast

      assert_equal ASTSubset,      ss.class
      assert_equal ASTDereference, ss.objset.class
    end

    def test_generate__conditions_scopes_work_on_relations
      Asd.class_exec do
        scope :asd_scope, lambda{ order('id') }
      end
      Mod::Blah.class_exec do
        scope :blah_scope, :conditions => ["id < ?", 5]
      end

      initialize_metaclasses

      assert_equal ASTSubset,      Mod::Blah.new.blah_scope.adsl_ast.class

      assert_equal ASTAllOf,       Asd.asd_scope.adsl_ast.class
      assert_equal ASTDereference, Asd.asd_scope.blahs.adsl_ast.class
      assert_equal ASTSubset,      Asd.asd_scope.blahs.blah_scope.adsl_ast.class
    end

    def test_generate__association_scope_count_by_group_is_unknown
      Mod::Blah.class_exec do
        scope :some_scope, :conditions => ["id < ?", 5]
      end

      initialize_metaclasses

      assert_equal Mod::Blah,   Asd.new.blahs.class
      assert_equal Mod::Blah,   Asd.new.blahs.some_scope.class
      assert_equal MetaUnknown, Asd.new.blahs.some_scope.count_by_group('id').class
    end

  end
end
