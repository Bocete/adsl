require 'adsl/util/test_helper'
require 'active_record'
require 'adsl/lang/ast_nodes'
require 'adsl/extract/rails/active_record_metaclass_generator'
require 'adsl/extract/rails/rails_test_helper'
require 'adsl/extract/rails/rails_instrumentation_test_case'
require 'adsl/extract/extraction_error'

module ADSL::Extract
  module Rails
    class ActiveRecordMetaclassGeneratorTest < ADSL::Extract::Rails::RailsInstrumentationTestCase
      include ADSL::Lang
      
      def test_cyclic_destroy
        Object.lookup_or_create_class('::Mod::Blah', ActiveRecord::Base).class_exec do
          has_many :kmes, :dependent => :destroy
        end
        Object.lookup_or_create_class('::Kme', ActiveRecord::Base).class_exec do
          has_many :asds, :dependent => :destroy
        end
    
        assert_raises ExtractionError do
          initialize_metaclasses
        end
      end
    
      def test_cyclic_destroy_reflective
        Object.lookup_or_create_class('::Asd', ActiveRecord::Base).class_exec do
          has_many :asds, :dependent => :destroy
        end
    
        assert_raises ExtractionError do
          initialize_metaclasses
        end
      end
    
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
        assert_equal 1, asd.members.length
        assert_equal [0, 1.0/0.0], asd.members.first.cardinality
        assert_equal 'Mod_Blah', asd.members.first.to_class_name.text
        assert_equal 'blahs', asd.members.first.name.text
        assert_equal 'asd', asd.members.first.inverse_of_name.text
    
        kme = Kme.adsl_ast
        assert_equal 1, kme.members.length
        assert_equal [0, 1], kme.members.last.cardinality
        assert_equal 'Mod_Blah', kme.members.last.to_class_name.text
        assert_equal 'blah', kme.members.last.name.text
        assert_nil kme.members.last.inverse_of_name
    
        blah = Mod::Blah.adsl_ast
        assert_equal 2, blah.members.length
    
        assert_equal [0, 1], blah.members.first.cardinality
        assert_equal 'Asd', blah.members.first.to_class_name.text
        assert_equal 'asd', blah.members.first.name.text
        assert_nil blah.members.first.inverse_of_name
    
        assert_equal [0, 1], blah.members.second.cardinality
        assert_equal 'Kme', blah.members.second.to_class_name.text
        assert_equal 'kme12', blah.members.second.name.text
        assert_equal 'blah', blah.members.second.inverse_of_name.text
      end
    
      def test_generate__associations_through
        initialize_metaclasses
       
        assert Asd.adsl_ast.members.select{ |rel| rel.name.text == 'kmes' }.empty?
        objset = Asd.new :adsl_ast => :something_unique
        through = objset.kmes
        assert_equal Kme, through.class
    
        assert_equal ASTMemberAccess, through.adsl_ast.class
        assert_equal 'kme12', through.adsl_ast.member_name.text 
        assert_equal ASTMemberAccess, through.adsl_ast.objset.class
        assert_equal 'blahs', through.adsl_ast.objset.member_name.text 
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
    
        asd_delete = Mod::Blah.new(:adsl_ast => ASTDummyObjset.new).destroy
        assert_equal ASTBlock, asd_delete.class
        assert_equal 2,        asd_delete.exprs.length
    
        assert_equal ASTDeleteObj,    asd_delete.exprs.first.class
        assert_equal ASTMemberAccess, asd_delete.exprs.first.objset.class
        assert_equal 'kme12',         asd_delete.exprs.first.objset.member_name.text
        assert_equal ASTDummyObjset,  asd_delete.exprs.first.objset.objset.class
    
        assert_equal ASTDeleteObj,    asd_delete.exprs.last.class
        assert_equal ASTDummyObjset,  asd_delete.exprs.last.objset.class
      end
      
      def test_generate__destroy_through_destroys_the_join_object
        initialize_metaclasses
        
        asd_delete = Asd.new(:adsl_ast => ASTDummyObjset.new).destroy
        assert_equal ASTBlock, asd_delete.class
        assert_equal 3,        asd_delete.exprs.length
        
        assert_equal ASTDeleteObj,    asd_delete.exprs[0].class
        assert_equal ASTMemberAccess, asd_delete.exprs[0].objset.class
        assert_equal ASTMemberAccess, asd_delete.exprs[0].objset.objset.class
        assert_equal 'kme12',         asd_delete.exprs[0].objset.member_name.text
        assert_equal 'blahs',         asd_delete.exprs[0].objset.objset.member_name.text
        assert_equal ASTDummyObjset,  asd_delete.exprs[0].objset.objset.objset.class
    
        assert_equal ASTDeleteObj,    asd_delete.exprs[1].class
        assert_equal ASTMemberAccess, asd_delete.exprs[1].objset.class
        assert_equal 'blahs',         asd_delete.exprs[1].objset.member_name.text
        assert_equal ASTDummyObjset,  asd_delete.exprs[1].objset.objset.class
        
        assert_equal ASTDeleteObj,    asd_delete.exprs[2].class
        assert_equal ASTDummyObjset,  asd_delete.exprs[2].objset.class
      end
    
      def test_generate__include_subset_ops
        initialize_metaclasses
    
        asd = Asd.new :adsl_ast => ASTDummyObjset.new
        assert asd.respond_to? :include?
        assert asd.respond_to? :<=
        assert asd.respond_to? :>=
        
        kme = Kme.new :adsl_ast => ASTDummyObjset.new
    
        subset = asd.include? kme
        assert_equal ASTIn, subset.class
    
        subset = asd >= kme
        assert_equal ASTIn, subset.class
    
        subset = asd <= kme
        assert_equal ASTIn, subset.class
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
        assert_equal ASTMemberAccess, Asd.all.blahs.adsl_ast.class
    
        ss = Asd.all.blahs.blah_scope.adsl_ast
    
        assert_equal ASTSubset,       ss.class
        assert_equal ASTMemberAccess, ss.objset.class
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
    
        assert_equal ASTAllOf,        Asd.asd_scope.adsl_ast.class
        assert_equal ASTMemberAccess, Asd.asd_scope.blahs.adsl_ast.class
        assert_equal ASTSubset,       Asd.asd_scope.blahs.blah_scope.adsl_ast.class
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
    
      def test_generate__association_build_direct
        initialize_metaclasses
    
        new = Asd.find.blahs.build
    
        assert_equal Mod::Blah,            new.class
        assert_equal ASTDereferenceCreate, new.adsl_ast.class
        assert_equal ASTOneOf,             new.adsl_ast.objset.class
        assert_equal ASTAllOf,             new.adsl_ast.objset.objset.class
        assert_equal 'Asd',                new.adsl_ast.objset.objset.class_name.text
        assert_equal 'blahs',              new.adsl_ast.rel_name.text
      end
      
      def test_generate__association_build_through
        initialize_metaclasses
    
        new = Asd.find.kmes.build
    
        assert_equal Kme,                  new.class
        assert_equal ASTDereferenceCreate, new.adsl_ast.class
        assert_equal 'kme12',              new.adsl_ast.rel_name.text
        assert_equal ASTDereferenceCreate, new.adsl_ast.objset.class
        assert_equal 'blahs',              new.adsl_ast.objset.rel_name.text
        assert_equal ASTOneOf,             new.adsl_ast.objset.objset.class
        assert_equal ASTAllOf,             new.adsl_ast.objset.objset.objset.class
        assert_equal 'Asd',                new.adsl_ast.objset.objset.objset.class_name.text
      end

      def test_generate__create_association
        initialize_metaclasses

        new = Asd.find.create_blahs

        assert_equal Mod::Blah,            new.class
        assert_equal ASTDereferenceCreate, new.adsl_ast.class
        assert_equal ASTOneOf,             new.adsl_ast.objset.class
        assert_equal ASTAllOf,             new.adsl_ast.objset.objset.class
        assert_equal 'Asd',                new.adsl_ast.objset.objset.class_name.text
        assert_equal 'blahs',              new.adsl_ast.rel_name.text
      end
    
      def test_generate__add_direct
        initialize_metaclasses
    
        new = (Asd.find.blahs.add(Mod::Blah.find))
    
        assert_equal ASTCreateTup, new.class
        assert_equal ASTOneOf,     new.objset1.class
        assert_equal ASTAllOf,     new.objset1.objset.class
        assert_equal 'Asd',        new.objset1.objset.class_name.text
        assert_equal 'blahs',      new.rel_name.text
        assert_equal ASTOneOf,     new.objset2.class
        assert_equal ASTAllOf,     new.objset2.objset.class
        assert_equal 'Mod_Blah',   new.objset2.objset.class_name.text
      end
    
      def test_generate__add_through
        initialize_metaclasses
    
        new = (Asd.find.kmes.add(Kme.find))
    
        assert_equal ASTCreateTup,         new.class
        assert_equal ASTDereferenceCreate, new.objset1.class
        assert_equal ASTOneOf,             new.objset1.objset.class
        assert_equal ASTAllOf,             new.objset1.objset.objset.class
        assert_equal 'Asd',                new.objset1.objset.objset.class_name.text
        assert_equal 'blahs',              new.objset1.rel_name.text
        assert_equal 'kme12',              new.rel_name.text
        assert_equal ASTOneOf,             new.objset2.class
        assert_equal ASTAllOf,             new.objset2.objset.class
        assert_equal 'Kme',                new.objset2.objset.class_name.text
      end
    end
  end
end

