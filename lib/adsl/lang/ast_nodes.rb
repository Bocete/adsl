require 'rubygems'
require 'active_support'
require 'pp'
require 'set'
require 'adsl/ds/data_store_spec'
require 'adsl/ds/effect_domain_extensions'
require 'adsl/util/general'

require 'adsl/lang/ast_node'
# various extensions are required at the end of this file

module ADSL
  module Lang
   
    class ADSLError < StandardError; end
    
    class ASTDummyObjset < ASTNode
      node_fields :type_sig
    end

    class ASTFlag < ASTNode
      node_fields :label
    end

    class ASTSpec < ASTNode
      node_fields :classes, :usergroups, :actions, :invariants, :ac_rules, :rules

      def adsl_ast_size(args = {})
        action = @actions.select{ |a| a.name.text == args[:action_name]}.first
        invariant = @invariants.select{ |a| a.name.text == args[:invariant_name]}.first

        elements = [action, invariant].compact
        sum = elements.map(&:adsl_ast_size).sum

        sum > 0 ? sum : super() 
      end
    end
    
    class ASTUserGroup < ASTNode
      node_fields :name
    end
    
    class ASTClass < ASTNode
      node_fields :name, :parent_names, :members, :authenticable

      def authenticable?
        @authenticable
      end

      def associations
        @members.select{ |m| m.is_a? ASTRelation }
      end
    end
    
    class ASTRelation < ASTNode
      node_fields :cardinality, :to_class_name, :name, :inverse_of_name
      attr_accessor :class_name
    end

    class ASTField < ASTNode
      node_fields :name, :type_name
      attr_accessor :class_name
    end

    class ASTIdent < ASTNode
      node_fields :text

      def self.[](text)
        ASTIdent.new :text => text.to_s
      end
    end

    class ASTAction < ASTNode
      node_fields :name, :expr

      def declare_instance_vars!
        regex = /^(?:at){1,2}__.*/
        nested_variable_names = Set[]
        @expr.preorder_traverse do |node|
          next unless node.is_a?(ASTIf) || node.is_a?(ASTForEach)

          exprs = [node.condition, node.then_expr, node.else_expr] if node.is_a?(ASTIf)
          exprs = [node.objset, node.expr] if node.is_a?(ASTForEach)

          assignments = exprs.map{ |e| e.recursively_gather{ |n| n.is_a?(ASTAssignment) ? n : nil } }.flatten
          var_reads = assignments.map(&:var_name).map(&:text)
          var_reads.select!{ |var| var =~ regex }

          nested_variable_names += var_reads
        end

        root_assignments_names = Set[*recursively_select do |node|
          next true if node.is_a?(ASTAssignment)
          next false if node.is_a?(ASTIf) || node.is_a?(ASTForEach)
        end.map(&:var_name).map(&:text).select{ |var| var =~ regex }]
        
        vars_that_need_declaring = nested_variable_names - root_assignments_names

        if vars_that_need_declaring.any?
          @expr = ASTBlock.new(:exprs => [@expr]) unless @expr.is_a? ASTBlock
          vars_that_need_declaring.each do |name|
            @expr.exprs.unshift ASTAssignment.new(
              :var_name => ASTIdent.new(:text => name),
              :expr => ASTEmptyObjset.new
            )
          end
        end
      end

      # this refers to the case when a variable is assigned to in a before filter, and the same assignment is repeated in the action
      def remove_overwritten_assignments!(label_text)
        return unless @expr.is_a? ADSL::Lang::ASTBlock
        exprs = @expr.exprs
        action_index = exprs.index{ |s| s.is_a?(ADSL::Lang::ASTFlag) && s.label.to_s == label_text.to_s }

        return if action_index.nil?
  
        action_index -= 1
        before_action_assignments = {}
        exprs.first(action_index).each do |stmt|
          stmt.preorder_traverse do |node|
            before_action_assignments[node.var_name.text] = node.expr if node.is_a? ADSL::Lang::ASTAssignment
          end
        end
  
        exprs[action_index..-1].each do |stmt|
          stmt.block_replace do |node|
            if node.is_a? ADSL::Lang::ASTAssignment
              if before_action_assignments[node.var_name.text] == node.expr
                # this assigment, and its expression, never happened
                before_action_assignments.delete node.var_name.text
                next ADSL::Lang::ASTEmptyObjset.new
              end
            elsif node.is_a? ADSL::Lang::ASTVariableRead
              before_action_assignments.delete node.var_name.text
            end
            node
          end
        end
      end
    end

    class ASTBlock < ASTNode
      node_fields :exprs
    end

    class ASTAssignment < ASTNode
      node_fields :var_name, :expr
    end

    class ASTAssertFormula < ASTNode
      node_fields :formula
    end

    class ASTCreateObjset < ASTNode
      node_fields :class_name
    end

    class ASTForEach < ASTNode
      node_fields :var_name, :objset, :expr

      def force_flat!(value)
        @force_flat = value
        self
      end
      
      def list_creations
        @expr.list_creations
      end
    end

    class ASTReturnGuard < ASTNode
      node_fields :expr
    end

    class ASTReturn < ASTNode
      node_fields :expr
    end

    class ASTRaise < ASTNode
      node_fields
    end

    class ASTIf < ASTNode
      node_fields :condition, :then_expr, :else_expr

      def list_entity_classes_written_to
        [@then_expr, @else_expr].map(&:list_entity_classes_written_to).flatten
      end
    end

    class ASTDeleteObj < ASTNode
      node_fields :objset
    end

    class ASTCreateTup < ASTNode
      node_fields :objset1, :rel_name, :objset2
    end

    class ASTDeleteTup < ASTNode
      node_fields :objset1, :rel_name, :objset2
    end

    class ASTMemberSet < ASTNode
      node_fields :objset, :member_name, :expr
    end

    class ASTAllOf < ASTNode
      node_fields :class_name
      
      def list_entity_classes_read
        Set[context.classes[@class_name.text]]
      end
    end

    class ASTSubset < ASTNode
      node_fields :objset
    end
    
    class ASTTryOneOf < ASTNode
      node_fields :objset
    end

    class ASTOneOf < ASTNode
      node_fields :objset
    end
    
    class ASTUnion < ASTNode
      node_fields :objsets
    end

    class ASTVariableRead < ASTNode
      node_fields :var_name
    end

    class ASTJSExpr < ASTNode
      node_fields :js
    end

    class ASTMemberAccess < ASTNode
      node_fields :objset, :member_name
    end

    class ASTDereferenceCreate < ASTNode
      node_fields :objset, :rel_name, :empty_first
    end

    class ASTEmptyObjset < ASTNode
      node_fields

      INSTANCE = ASTEmptyObjset.new
    end

    class ASTCurrentUser < ASTNode
      node_fields
      
      INSTANCE = ASTCurrentUser.new
    end

    class ASTInUserGroup < ASTNode
      node_fields :objset, :groupname
    end

    class ASTAllOfUserGroup < ASTNode
      node_fields :groupname
    end

    class ASTPermitted < ASTNode
      node_fields :ops, :expr
    end

    class ASTPermit < ASTNode
      node_fields :group_names, :ops, :expr
    end

    class ASTInvariant < ASTNode
      node_fields :name, :formula
    end

    class ASTRule < ASTNode
      node_fields :formula
    end

    class ASTBoolean < ASTNode
      node_fields :bool_value
      
      TRUE = ASTBoolean.new :bool_value => true
      FALSE = ASTBoolean.new :bool_value => false
    end

    class ASTNumber < ASTNode
      node_fields :value
    end

    class ASTString < ASTNode
      node_fields :value
    end

    class ASTForAll < ASTNode
      node_fields :vars, :subformula
    end

    class ASTExists < ASTNode
      node_fields :vars, :subformula
    end

    class ASTNot < ASTNode
      node_fields :subformula 
    end

    class ASTAnd < ASTNode
      node_fields :subformulae
    end
    
    class ASTOr < ASTNode
      node_fields :subformulae
    end

    class ASTXor < ASTNode
      node_fields :subformulae
    end

    class ASTImplies < ASTNode
      node_fields :subformula1, :subformula2
    end

    class ASTEqual < ASTNode
      node_fields :exprs
    end

    class ASTIn < ASTNode
      node_fields :objset1, :objset2
    end
    
    class ASTIsEmpty < ASTNode
      node_fields :objset
    end
  end
end

require 'adsl/lang/ast_nodes/to_adsl_extensions'
require 'adsl/lang/ast_nodes/optimization_extensions'
require 'adsl/lang/ast_nodes/remove_dead_code_extensions'
require 'adsl/lang/ds_translation/ast_nodes_extensions'
