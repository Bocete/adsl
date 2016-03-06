require 'adsl/util/test_helper'
require 'adsl/ds/data_store_spec'
require 'adsl/ds/effect_domain_extensions'
require 'adsl/lang/ds_translation/ds_translation_context'
require 'set'

module ADSL::DS
  class EffectDomainExtensionsTest < ActiveSupport::TestCase
  
    def setup
      @parent   = DSClass.new(:name => 'parent')
      @child1   = DSClass.new(:name => 'child1', :parents => Set[@parent])
      @subchild = DSClass.new(:name => 'subchild', :parents => Set[@child1])
      @child2   = DSClass.new(:name => 'child2', :parents => Set[@parent])
      @diamond  = DSClass.new(:name => 'diamond', :parents => Set[@child1, @child2])
  
      @parent.children = [@child1, @child2]
      @child1.children = [@subchild, @diamond]
      @child2.children = [@diamond]
      
      @classes = [@parent, @child1, @subchild, @child2, @diamond]
  
      @context = ADSL::Lang::DSTranslation::DSTranslationContext.new
      @classes.each do |c|
        @context.classes[c.name] = [nil, c]
      end
      rel     = DSRelation.new(:from_class => @child1, :to_class => @child2, :name => 'child2', :inverse_of => nil)
      inv_rel = DSRelation.new(:from_class => @child2, :to_class => @child1, :name => 'child1', :inverse_of => rel)
      [rel, inv_rel].each do |rel|
        rel.from_class.members << rel
        @context.members[rel.from_class.name][rel.name] = [nil, rel]
      end
    end
  
    def test_node_effect_info__conflicting?
      node_info = NodeEffectDomainInfo.new
  
      node_info.delete(:a)
      assert_false node_info.conflicting?
  
      node_info.create(:b)
      assert_false node_info.conflicting?
  
      node_info.delete(:a, false)
      assert_false node_info.conflicting?
      
      node_info.read(:a, false)
      assert node_info.conflicting?
  
      node_info = NodeEffectDomainInfo.new
      node_info.delete(:a, true)
      node_info.create(:a, true)
      assert_false node_info.conflicting?
  
      node_info.create(:a)
      assert node_info.conflicting?
    end
    
    def test_children_of_class
      assert_equal Set[@parent, @child1, @child2, @subchild, @diamond], @parent.all_children(true)
      assert_equal Set[@child1, @child2, @subchild, @diamond], @parent.all_children(false)
  
      assert_equal Set[@subchild, @diamond, @child1], @child1.all_children(true)
      assert_equal Set[@subchild, @diamond], @child1.all_children(false)
  
      assert_equal Set[@diamond, @child2], @child2.all_children(true)
      assert_equal Set[@diamond], @child2.all_children(false)
  
      assert_equal Set[@diamond], @diamond.all_children(true)
      assert_equal Set[], @diamond.all_children(false)
    end
    
    def test_children_of_type_sig
      assert_equal Set[@parent, @child1, @child2, @subchild, @diamond], @parent.to_sig.all_children(true)
      assert_equal Set[@child1, @child2, @subchild, @diamond], @parent.to_sig.all_children(false)
  
      assert_equal Set[@subchild, @diamond, @child1], @child1.to_sig.all_children(true)
      assert_equal Set[@subchild, @diamond], @child1.to_sig.all_children(false)
  
      assert_equal Set[@diamond, @child2], @child2.to_sig.all_children(true)
      assert_equal Set[@diamond], @child2.to_sig.all_children(false)
  
      assert_equal Set[@diamond], @diamond.to_sig.all_children(true)
      assert_equal Set[], @diamond.to_sig.all_children(false)
  
      sig = TypeSig::ObjsetType.new @child1, @child2
      assert_equal Set[@child1, @child2, @diamond, @subchild], sig.all_children(true)
      assert_equal Set[@diamond, @subchild], sig.all_children(false)
    end
  
    def test_context_relations_around
      assert_equal Set[], @context.relations_around(@parent)
      assert_equal Set[@child1.members.first, @child2.members.first], @context.relations_around(@child1)
      assert_equal Set[@child1.members.first, @child2.members.first], @context.relations_around(@child2)
      assert_equal Set[@child1.members.first, @child2.members.first], @context.relations_around(@child1, @child2)
      assert_equal Set[@child1.members.first, @child2.members.first], @context.relations_around(@child1, @child2, @diamond)
  
      assert_equal Set[@child1.members.first, @child2.members.first], @context.relations_around(Set[@child1, @subchild, @parent])
    end
    
    def test_node_effect_info__conflicting_with_type_sigs
      node_info = NodeEffectDomainInfo.new
      node_info.create @child1
      node_info.create @child2
      assert_false node_info.conflicting?
  
      node_info = NodeEffectDomainInfo.new
      node_info.create @child1
      node_info.read   @child1
      assert node_info.conflicting?
      
      node_info = NodeEffectDomainInfo.new
      node_info.create @child1
      node_info.read   @parent.all_children(true)
      assert node_info.conflicting?
      
      node_info = NodeEffectDomainInfo.new
      node_info.read @parent, true
      node_info.read @child1
      assert_false node_info.conflicting?
      
      node_info = NodeEffectDomainInfo.new
      node_info.create @parent
      node_info.read   @child1
      assert_false node_info.conflicting?
    end
  
    def test_node_effect__block_empty
      block = ADSL::DS::DSBlock.new :statements => []
  
      info = NodeEffectDomainInfo.new
      block.effect_domain_analysis @context, info
      assert_false info.conflicting?
    end
    
    def test_node_effect__create_obj
      block = ADSL::DS::DSBlock.new :statements => [
        ADSL::DS::DSCreateObj.new(:klass => @parent)
      ]
  
      info = NodeEffectDomainInfo.new
      block.effect_domain_analysis @context, info
      assert_false info.conflicting?
    end
  
    def test_node_effect__delete_obj
      block = DSBlock.new :statements => [
        DSDeleteObj.new(:objset => DSAllOf.new(:klass => @parent))
      ]
  
      info = NodeEffectDomainInfo.new
      block.effect_domain_analysis @context, info
      assert_false info.conflicting?
    end
  
    def test_node_effect__create_and_subsequently_delete
      block = DSBlock.new :statements => [
        createobj = DSCreateObj.new(:klass => @parent),
        DSDeleteObj.new(:objset => DSCreateObjset.new(:createobj => createobj))
      ]
      info = NodeEffectDomainInfo.new
      block.effect_domain_analysis @context, info
      assert_false info.conflicting?
  
      block = DSBlock.new :statements => [
        DSCreateObj.new(:klass => @parent),
        DSDeleteObj.new(:objset => DSSubset.new(:objset => DSAllOf.new(:klass => @parent)))
      ]
      info = NodeEffectDomainInfo.new
      block.effect_domain_analysis @context, info
      assert info.conflicting?
    end
  
    def test_node_effect__create_parent_delete_child_is_ok  
      block = DSBlock.new :statements => [
        DSCreateObj.new(:klass => @parent),
        DSDeleteObj.new(:objset => DSSubset.new(:objset => DSAllOf.new(:klass => @child1)))
      ]
      info = NodeEffectDomainInfo.new
      block.effect_domain_analysis @context, info
      assert_false info.conflicting?
    end
  
    def test_node_effect__dereference_goes_global
      block = DSBlock.new :statements => [
        child1create = DSCreateObj.new(:klass => @child1),
        DSCreateObj.new(:klass => @child2),
        DSDeleteObj.new(:objset => DSDereference.new(
          :objset => DSCreateObjset.new(:createobj => child1create),
          :relation => @child1.members.first)
        )
      ]
      info = NodeEffectDomainInfo.new
      block.effect_domain_analysis @context, info
      assert info.conflicting?
    end
  
    def test_node_effect__delete_deletes_tuples_of_parents
      block = DSBlock.new :statements => [
        DSDeleteObj.new(:objset => DSSubset.new(:objset => DSAllOf.new(:klass => @subchild)))
      ]
      info = NodeEffectDomainInfo.new
      block.effect_domain_analysis @context, info
      assert_false info.conflicting?
      info.read @child1.members.first
      assert info.conflicting?
    end
  
    def test_node_effect__assignment_of_create_persists_local
      block = DSBlock.new :statements => [
        create = DSCreateObj.new(:klass => @child1),
        assign = DSAssignment.new(
          :var => (var = DSVariable.new :name => 'var', :type_sig => @child1.to_sig),
          :expr => DSCreateObjset.new(:createobj => create)
        ),
        DSDeleteObj.new(:objset => var)
      ]
  
      info = NodeEffectDomainInfo.new
      block.effect_domain_analysis @context, info
      assert_false info.conflicting?
    end
  end
end
