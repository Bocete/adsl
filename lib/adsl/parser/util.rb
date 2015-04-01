require 'adsl/ds/data_store_spec'

module ADSL
  module Parser
    module Util
      
      def self.context_vars_that_differ(*contexts)
        vars_per_context = []
        contexts.each do |context|
          vars_per_context << context.var_stack.inject(ActiveSupport::OrderedHash.new) { |so_far, frame| so_far.merge! frame }
        end
        all_vars = vars_per_context.map{ |c| c.keys }.flatten.uniq
        packed = ActiveSupport::OrderedHash.new
        all_vars.each do |v|
          packed[v] = vars_per_context.map{ |vpc| vpc[v][1] }
        end
        packed.delete_if { |v, vars| vars.uniq.length == 1 }
        packed
      end

      def self.ops_and_expr_from_nodes(context, ops_node, expr_node)
        ops = Set[*ops_node.map do |op, line|
          case op
          when :read, :create, :delete, :assoc, :deassoc
            op
          when :edit
            [:create, :delete]
          else 
            raise ADSLError, "Unknown permission #{op} on line #{line}"
          end
        end.flatten]
        
        if expr_node
          expr = expr_node.typecheck_and_resolve context
          is_deref = expr.is_a?(ADSL::DS::DSDereference)
        else
          is_deref = false
        end

        if is_deref
          ops << :assoc if ops.include?(:create)
          ops << :deassoc if ops.include?(:delete)
        else
          [:assoc, :deassoc].each do |op|
            raise ADSLError, "#{op} permission is only applicable to dereferences (line #{@lineno})" if ops.include? op
          end
        end

        return ops, expr
      end

      def self.booleanify(ds_node)
        if ds_node.type_sig.is_objset_type?
          # ok, let's allow this for expression purposes only
          ADSL::DS::DSNot.new(:subformula => ADSL::DS::DSIsEmpty.new(
            :objset => condition
          ))
        elsif ds_node.type_sig.is_bool_type?
          ds_node
        else
          raise ADSLError, "Boolean expression expected (received type #{ds_node.type_sig})"
        end
      end
        
    end
  end
end
