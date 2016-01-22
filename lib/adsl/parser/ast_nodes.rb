require 'rubygems'
require 'active_support'
require 'pp'
require 'set'
require 'adsl/ds/data_store_spec'
require 'adsl/ds/effect_domain_extensions'
require 'adsl/util/general'
require 'adsl/parser/util'

class Array
  def optimize
    map! do |e|
      e.respond_to?(:optimize) ? e.optimize : e
    end
    self
  end
end

class Numeric
  alias_method :to_adsl, :to_s
end

class NilClass
  alias_method :to_adsl, :to_s
end

class TrueClass
  alias_method :to_adsl, :to_s
end

class FalseClass
  alias_method :to_adsl, :to_s
end

module ADSL
  module Parser
   
    class ASTNode
      def expr_has_side_effects?
        false
      end

      def self.is_statement?
        @is_statement
      end

      def self.is_expr?
        @is_expr
      end

      def self.node_type(*types)
        @is_statement = types.include? :statement
        @is_expr      = types.include? :expr
      end

      def self.node_fields(*fields)
        container_for *[*fields, :lineno]
        recursively_comparable
      end

      def returns?; false; end
      
      def raises?; false; end

      def reaches_view?; false; end

      def optimize
        children = self.class.container_for_fields.map{ |field_name| [field_name, send(field_name)] }
        until children.empty?
          child_name, child = children.pop
          if child.respond_to?(:optimize)
            new_value = child.optimize
            send "#{child_name}=", new_value unless new_value.equal? child
          end
        end
        self
      end

      def block_replace(&block)
        children = self.class.container_for_fields.map{ |field_name| [field_name, send(field_name)] }
        children.each do |name, value|
          new_value = if value.is_a? Array
            value.map do |e|
              new_e = e.respond_to?(:block_replace) ? e.block_replace(&block) : nil
              new_e.nil? ? e.dup : new_e
            end
          elsif value.is_a? ASTNode
            new_value = value.block_replace(&block)
            new_value.nil? ? value.dup : new_value
          elsif value.is_a?(Symbol) || value.nil?
            value
          else
            value.dup
          end
          send("#{name}=", new_value) if new_value != value
        end
        new_value = block[self]
        new_value.nil? ? self.dup : new_value
      end

      def preorder_traverse(&block)
        self.class.container_for_fields.each do |field_name|
          field = send field_name
          if field.is_a? Array
            field.flatten.each do |subfield|
              subfield.preorder_traverse &block if subfield.respond_to? :preorder_traverse
            end
          else
            field.preorder_traverse &block if field.respond_to? :preorder_traverse
          end
        end
        block[self]
      end

      # used for statistics
      def adsl_ast_size
        sum = 1
        self.class.container_for_fields.each do |field_name|
          field = send field_name
          if field.is_a? Array
            field.flatten.each do |subfield|
              sum += subfield.adsl_ast_size if subfield.respond_to? :adsl_ast_size
            end
          else
            sum += field.adsl_ast_size if field.respond_to? :adsl_ast_size
          end
        end
        sum
      end
    end

    class ADSLError < StandardError; end
    
    class ASTTypecheckResolveContext
      attr_accessor :classes, :usergroups, :members, :actions, :invariants, :ac_rules, :rules, :var_stack, :pre_stmts 

      class ASTStackFrame < ActiveSupport::OrderedHash
        attr_accessor :var_write_listeners
        attr_accessor :var_read_listeners
        
        def initialize
          super
          @var_write_listeners = []
          @var_read_listeners = []
        end
      
        def on_var_read(&block)
          listeners = @var_read_listeners
          listeners.push block
        end
        
        def on_var_write(&block)
          listeners = @var_write_listeners
          listeners.push block
        end

        def fire_write_event(name)
          listeners = @var_write_listeners
          listeners.each do |listener|
            listener.call name
          end
        end
        
        def fire_read_event(name)
          listeners = @var_read_listeners
          listeners.each do |listener|
            listener.call name
          end
        end

        def dup
          other = ASTStackFrame.new
          self.each do |key, val|
            other[key] = val.dup
          end
          other.var_write_listeners = @var_write_listeners.dup
          other.var_read_listeners = @var_read_listeners.dup
          other
        end

        def clone
          dup
        end
      end

      def initialize
        # name => [astnode, dsobj]
        @classes = ActiveSupport::OrderedHash.new
        @usergroups = ActiveSupport::OrderedHash.new

        # classname => name => [astnode, dsobj]
        @members = ActiveSupport::OrderedHash.new{ |hash, key| hash[key] = ActiveSupport::OrderedHash.new }

        # stack of name => [astnode, dsobj]
        @actions = ActiveSupport::OrderedHash.new

        @invariants = []
        @ac_rules = []
        @rules = []
        @var_stack = []
        @pre_stmts = []
      end

      def initialize_copy(source)
        super
        source.classes.each do |name, value|
          @classes[name] = value.dup
        end
        source.usergroups.each do |name, value|
          @usergroups[name] = value.dup
        end
        source.members.each do |class_name, class_entry|
          entries = @members[class_name]
          class_entry.each do |name, value|
            entries[name] = value.dup
          end
        end
        @actions = source.actions.dup
        @invariants = source.invariants.dup
        @ac_rules = source.ac_rules.dup
        @rules = source.rules.dup
        @var_stack = source.var_stack.map{ |frame| frame.dup }
        @pre_stmts = source.pre_stmts.map{ |stmt| stmt.dup }
      end
      
      def on_var_write(&block)
        @var_stack.last.on_var_write(&block)
      end
      
      def on_var_read(&block)
        @var_stack.last.on_var_read(&block)
      end

      def in_stack_frame
        push_frame
        yield
      ensure
        pop_frame
      end

      def push_frame
        @var_stack.push ASTStackFrame.new
      end

      def pop_frame
        @var_stack.pop
      end

      def define_var(var, node)
        raise ADSLError, "Defining variables on a stack with no stack frames" if @var_stack.empty?
        prev_var_node, prev_var = lookup_var var.name
        raise ADSLError, "Duplicate identifier '#{var.name}' on line #{node.lineno}; previous definition on line #{prev_var_node.lineno}" unless prev_var.nil?
        @var_stack.last[var.name] = [node, var]
        @var_stack.last.fire_write_event var.name
        return var
      end

      def redefine_var(var, node)
        @var_stack.length.times do |frame_index|
          frame = @var_stack[frame_index]
          next unless frame.include? var.name
          
          old_var = frame[var.name][1]
          type_sig = old_var.type_sig & var.type_sig
          if type_sig.is_invalid_type?
            raise ADSLError, "Unmatched type signatures '#{ old_var.type_sig }' and  '#{ var.type_sig }' for variable '#{var.name}' on line #{node.lineno}"
          end
          var.type_sig = type_sig

          frame[var.name][1] = var

          @var_stack[frame_index..-1].reverse.each do |subframe|
            subframe.fire_write_event var.name
          end
          
          return var
        end
        return define_var var, node
      end

      def lookup_var(name, fire_read_event=true)
        @var_stack.length.times do |index|
          frame = @var_stack[index]
          next if frame[name].nil?
          var = frame[name]

          if fire_read_event
            @var_stack[index..-1].reverse.each do |subframe|
              subframe.fire_read_event name
            end
          end

          # handle events here, none defined atm
          return var
        end
        nil
      end
    
      def find_member(from_type_sig, name, lineno, to_type_sig=nil)
        unless from_type_sig.is_a? ADSL::DS::TypeSig::ObjsetType
          raise ADSLError, "#{from_type_sig}.#{name} is not a class type (on line #{lineno})"
        end
        origin_class_names = from_type_sig.all_parents(true).map(&:name)

        member_map = @members.select{ |klass_name, rel_map| origin_class_names.include? klass_name }.values.inject(&:merge) || {}
        
        unless member_map.include? name
          raise ADSLError, "Unknown relation #{name} from type signature #{from_type_sig} on line #{lineno}"
        end

        member = member_map[name][1]
        
        if (to_type_sig &&
            !(member.type_sig >= to_type_sig) &&
            !(to_type_sig.is_ambiguous_objset_type? && member.type_sig.is_objset_type?))
          raise ADSLError, "Mismatched right-hand-side type for member #{from_type_sig}.#{name} on line #{lineno}. Expected #{to_type_sig} but was #{member.type_sig}"
        end

        member
      end

      def auth_class
        return @auth_class unless @auth_class.nil?
        candidates = @classes.values.select{ |cn, c| c.authenticable? }
        if candidates.empty?
          return nil
        elsif candidates.length > 1
          raise ADSLError, "There can be at most one authenticable class: #{
            candidates.map(&:first).map(&:name).map(&:text).join ', '
          }"
        else
          @auth_class = candidates.first
          return @auth_class
        end
      end
    end

    class ASTDummyObjset < ASTNode
      node_fields :type_sig
      node_type :expr

      def expr_has_side_effects?
        false
      end

      def typecheck_and_resolve(context)
        self
      end

      def to_adsl
        "DummyObjset(#{ @type_sig })"
      end
    end

    class ASTDummyStmt < ASTNode
      node_fields :label
      node_type :statement

      def typecheck_and_resolve(context)
      end

      def to_adsl
        "DummyStmt(#{ @label })\n"
      end

      def arbitrary?
        @label != :render
      end

      def reaches_view?
        @label == :render
      end
    end

    class ASTSpec < ASTNode
      node_fields :classes, :usergroups, :actions, :invariants, :ac_rules, :rules

      def typecheck_and_resolve
        context = ASTTypecheckResolveContext.new

        # make sure class names are unique
        @classes.each do |class_node|
          if context.classes.include? class_node.name.text
            raise ADSLError, "Duplicate class name '#{class_node.name.text}' on line #{class_node.name.lineno} (first definition on line #{context.classes[class_node.name.text][0].name.lineno}"
          end
          klass = ADSL::DS::DSClass.new :name => class_node.name.text, :authenticable => class_node.authenticable
          context.classes[klass.name] = [class_node, klass]
        end

        # make sure the parent classes are declared properly and that the inheritance graph is non-cyclic
        parents = Hash.new{}
        context.classes.values.each do |class_node, klass|
          class_node.parent_names.map(&:text).each do |parent_name|
            parent_node, parent = context.classes[parent_name]
            raise ADSLError, "Unknown parent class name #{parent_name} for class #{class_node.name.text}" if parent.nil?
            klass.parents << parent
          end
        end
        context.classes.values.each do |class_node, klass|
          raise ADSLError, "Cyclic inheritance detected with class #{klass.name}" if klass.all_parents.include? klass
        end

        # auth stuff
        # this call might raise exceptions
        authclass = context.auth_class
        if authclass
          @usergroups.each do |ug_node|
            ug_node.typecheck_and_resolve context
          end
        elsif @usergroups.length > 0
          raise ADSLError, "UserGroups can only be declared if there exists an authenticable class"
        end

        # setup children of said classes
        context.classes.values.each do |class_node, klass|
          klass.parents.each do |parent|
            parent.children << klass
          end
        end

        # make sure relations are valid and refer to existing classes
        context.classes.values.each do |class_node, klass|
          class_node.members.each do |rel_node|
            klass.all_parents(true).each do |superclass|
              if context.members[superclass.name].include? rel_node.name.text
                raise ADSLError, "Duplicate member name '#{class_node.name.text}' under class '#{klass.name}' on line #{rel_node.lineno} (first definition on line #{context.members[superclass.name][rel_node.name.text][0].lineno}"
              end
            end
            
            rel_node.class_name = klass.name
            if rel_node.is_a? ADSL::Parser::ASTRelation
              ds_obj = ADSL::DS::DSRelation.new :name => rel_node.name.text, :from_class => klass
            else
              ds_obj = ADSL::DS::DSField.new :name => rel_node.name.text, :from_class => klass
            end
            context.members[klass.name][ds_obj.name] = [rel_node, ds_obj]
            klass.members << ds_obj
          end
        end

        # now that classes and rels are initialized, check them
        @classes.each do |class_node|
          class_node.typecheck_and_resolve context
        end

        @actions.each do |action_node|
          action_node.typecheck_and_resolve context
        end

        @rules.each do |rule_node|
          context.rules << (rule_node.typecheck_and_resolve context)
        end

        # make sure invariants have unique names; create names for unnamed invariants
        names = Set.new
        @invariants.each do |invariant_node|
          invariant = invariant_node.typecheck_and_resolve context
          if invariant.name && names.include?(invariant.name)
            raise ADSLError, "Duplicate invariant name #{invariant.name} on line #{invariant_node.lineno}"
          end
          name = invariant.name || "unnamed_line_#{invariant_node.lineno}"
          while names.include? name
            name = name.increment_suffix
          end
          invariant.name = name
          context.invariants << invariant
          names << name
        end

        @invariants.each do |invariant_node|
          invariant = invariant_node.typecheck_and_resolve context
        end

        @ac_rules.each do |ac_rule|
          context.ac_rules << ac_rule.typecheck_and_resolve(context)
        end

        ADSL::DS::DSSpec.new(
          :classes => context.classes.map{ |a, b| b[1] }, 
          :usergroups => context.usergroups.map{ |a, b| b[1] },
          :actions => context.actions.map{ |a, b| b[1] },
          :invariants => context.invariants.dup,
          :ac_rules => context.ac_rules.dup,
          :rules => context.rules.dup
        )
      end

      def to_adsl
        output = [@classes, @usergroups, @rules, @ac_rules, @actions, @invariants].map{ |coll| coll.map(&:to_adsl).join }.join "\n"
        output.gsub(/\n{2,}/, "\n\n")
      end

      def adsl_ast_size(options = {})
        sum = 1
        @classes.each do |c|
          sum += c.adsl_ast_size
        end
        actions = options[:action_name].nil? ? @actions : @actions.select{ |a| a.name.text == options[:action_name] }
        actions.each do |a|
          sum += options[:pre_optimize] ? a.pre_optimize_adsl_ast_size : a.adsl_ast_size
        end
        invs = options[:invariant_name].nil? ? @invariants : @invariants.select{ |a| a.name.text == options[:invariant_name] }
        invs.each do |i|
          sum += i.adsl_ast_size
        end
        sum
      end

      def split_into_individual_ac_rules
        @ac_rules = @ac_rules.map do |rule|
          subrules = []
          group_name_lists = rule.group_names.map{ |name| [name] }
          group_name_lists = [[]] if group_name_lists.empty?
          group_name_lists.each do |group_names|
            rule.ops.each do |op|
              subrules << ADSL::Parser::ASTPermit.new(:group_names => group_names, :ops => [op], :expr => rule.expr.dup)
            end
          end
          subrules
        end.flatten.uniq
      end

      def remove_redundant_rules
        rules_that_cover_all = @ac_rules.select{ |a| a.expr.is_a? ADSL::Parser::ASTAllOf }.group_by{ |a| a.expr.class_name.text }
        rules_that_dereference = @ac_rules.select{ |a| a.expr.is_a? ADSL::Parser::ASTMemberAccess }

        rules_that_dereference.each do |deref_entry|
          login_class ||= @classes.select{ |c| c.authenticable }.first
          to_class = login_class.members.select{ |a| a.name.text == deref_entry.expr.member_name.text }.first.to_class_name.text
          cover_alls = rules_that_cover_all[to_class]
          next if cover_alls.nil? || cover_alls.empty?

          deref_covered_by_all = cover_alls.any? do |cover_all_entry|
            cover_all_entry.group_names == deref_entry.group_names && cover_all_entry.ops == deref_entry.ops
          end
          @ac_rules.delete deref_entry if deref_covered_by_all
        end
      end

      def merge_rule_ops
        rules_by_non_ops = @ac_rules.group_by{ |e| [e.group_names, e.expr] }
        @ac_rules = rules_by_non_ops.map do |pair, entries|
          next entries.first if entries.length == 1
          ADSL::Parser::ASTPermit.new :group_names => pair[0], :ops => entries.map(&:ops).flatten.uniq.sort, :expr => pair[1]
        end
      end

      def merge_rule_groups
        rules_by_non_role_groups = @ac_rules.group_by{ |e| [e.ops, e.expr] }
        @ac_rules = rules_by_non_role_groups.map do |pair, entries|
          next entries.first if entries.length == 1
          ADSL::Parser::ASTPermit.new :group_names => entries.map(&:group_names).flatten.uniq.sort_by(&:text), :ops => pair[0], :expr => pair[1]
        end
      end

      def optimize_ac_rules
        split_into_individual_ac_rules
        remove_redundant_rules
        merge_rule_ops
        merge_rule_groups
        @ac_rules.sort_by!{ |rule| [rule.group_names.map(&:text), rule.expr.to_adsl] }
      end

      def optimize!
        optimize_ac_rules
        self
      end
    end
    
    class ASTUserGroup < ASTNode
      node_fields :name

      def typecheck_and_resolve(context)
        name = @name.text
        if context.usergroups.include? name
          raise ADSLError, "Duplicate usergroup name #{name} at line #{@lineno}"
        end
        ug = ADSL::DS::DSUserGroup.new :name => name
        context.usergroups[name] = [self, ug]
      end

      def to_adsl
        "usergroup #{@name.text}\n"
      end
    end
    
    class ASTClass < ASTNode
      node_fields :name, :parent_names, :members, :authenticable

      def typecheck_and_resolve(context)
        klass = context.classes[@name.text][1]
        @members.each do |member_node|
          member_node.typecheck_and_resolve context
        end
      end

      def authenticable?
        @authenticable
      end

      def associations(incl_parent = true)
        @members.select{ |m| m.is_a? ASTRelation }
      end

      def to_adsl
        par_names = @parent_names.empty? ? "" : "extends #{@parent_names.map(&:text).join(', ')} "
        "#{authenticable? ? 'authenticable ' : ''}class #{ @name.text } #{ par_names }{\n#{ @members.map(&:to_adsl).adsl_indent }}\n"
      end
    end
    
    class ASTRelation < ASTNode
      node_fields :cardinality, :to_class_name, :name, :inverse_of_name
      attr_accessor :class_name

      def to_adsl
        card_str = cardinality[1] == Float::INFINITY ? "#{cardinality[0]}+" : "#{cardinality[0]}..#{cardinality[1]}"
        inv_str = inverse_of_name.nil? ? "" : " inverseof #{inverse_of_name.text}"
        "#{ card_str } #{ @to_class_name.text } #{ @name.text }#{ inv_str }\n"
      end

      def typecheck_and_resolve(context)
        rel = context.members[@class_name][@name.text][1]
          
        if @cardinality[0] > @cardinality[1]
          raise ADSLError, "Invalid cardinality of relation #{@class_name}.#{@name.text} on line #{@cardinality[2]}: minimum cardinality #{@cardinality[0]} must not be greater than the maximum cardinality #{@cardinality[1]}"
        end
        if @cardinality[1] == 0
          raise ADSLError, "Invalid cardinality of relation #{@class_name}.#{@name.text} on line #{@cardinality[2]}: maximum cardinality #{@cardinality[1]} must be positive"
        end
        unless context.classes.include? @to_class_name.text
          raise ADSLError, "Unknown class name #{@to_class_name.text} in relation #{@class_name}.#{@name.text} on line #{@to_class_name.lineno}"
        end

        rel.to_class = context.classes[@to_class_name.text][1]
        rel.cardinality = ADSL::DS::TypeSig::ObjsetCardinality.new *@cardinality

        if @inverse_of_name
          target_class = rel.to_class
          target_rel = (target_class.all_parents(true)).map{ |klass| klass.members }.flatten.select{ |rel| rel.name == @inverse_of_name.text}.first
           
          if target_rel.nil?
            raise ADSLError, "Unknown relation to which #{@class_name}.#{rel.name} relation is inverse to: #{rel.to_class.name}.#{@inverse_of_name.text} on line #{@inverse_of_name.lineno}"
          end
          unless target_rel.is_a? ADSL::DS::DSRelation
            raise ADSLError, "Inverse relation of #{@class_name}.#{rel.name} is not a relation (#{rel.to.class.name}.#{@inverse_of_name.text}) on line #{@inverse_of_name.lineno}"
          end

          rel.inverse_of = target_rel

          if target_rel.inverse_of
            raise ADSLError, "Relation #{@class_name}.#{rel.name} cannot be inverse to an inverse relation #{rel.to_class.name}.#{@inverse_of_name.text} on line #{@inverse_of_name.lineno}"
          end
        end
      end
    end

    class ASTField < ASTNode
      node_fields :name, :type_name
      attr_accessor :class_name

      def to_adsl
        "#{ @type_name } #{ @name }\n"
      end

      def typecheck_and_resolve(context)
        type = ADSL::DS::TypeSig::BasicType.for_sym type_name.to_sym

        if type.nil?
          raise ADSLError, "Unknown basic type `#{@type_name}` on line #{@lineno}"
        end

        field = context.members[@class_name][@name.text][1]
        field.type = type
      end
    end

    class ASTIdent < ASTNode
      node_fields :text
    end

    class ASTAction < ASTNode
      node_fields :name, :block

      def typecheck_and_resolve(context)
        old_action_node, old_action = context.actions[@name.text]
        raise ADSLError, "Duplicate action name #{@name.text} on line #{@name.lineno}; first definition on line #{old_action_node.name.lineno}" unless old_action.nil?
        arguments = []
        cardinalities = []
        block = nil
        context.in_stack_frame do
          block = @block.typecheck_and_resolve context, false
        end
        action = ADSL::DS::DSAction.new(
          :name => @name.text,
          :block => block
        )
        context.actions[action.name] = [self, action]
        action
      end

      def variable_read_by_view(var_name)
        var_name.start_with? 'at__'
      end

      def optimize
        @pre_optimize_adsl_ast_size ||= adsl_ast_size

        loop do
          pre_loop_size = adsl_ast_size
          @block = @block.optimize

          # update counters of branches that might be necesarry
          return_counter_map = Hash.new{ |hash, key| hash[key] = 0 }
          if_counter_map     = Hash.new{ |hash, key| hash[key] = 0 }
          @block.block_replace do |expr|
            if expr.is_a? ASTReturned
              return_counter_map[expr.return_guard] += 1
            elsif expr.is_a? ASTIfExpr
              if_counter_map[expr.if] += 1
            end
            nil
          end

          @block.block_replace do |expr|
            if expr.is_a?(ASTReturnGuard) && return_counter_map[expr] == 0
              expr.block.block_replace do |expr|
                next unless expr.is_a? ASTReturn
                ASTBlock.new(:statements => expr.exprs.map do |returned|
                  ASTExprStmt.new :expr => returned
                end)
              end
              expr.block
            elsif expr.is_a?(ASTIf) && if_counter_map[expr] == 0
              next ASTDummyStmt.new if expr.blocks.map(&:statements).flatten.empty?
              if expr.condition.is_a?(ASTBoolean)
                case expr.condition.bool_value
                when true;  next expr.then_block
                when false; next expr.else_block
                when nil;   next ASTEither.new(:blocks => expr.blocks)
                end
              end
              expr
            end
          end

          # remove variables that are assigned to but are not read
          variables_read = Set[]
          @block.preorder_traverse do |node|
            next unless node.is_a? ASTVariable
            variables_read << node.var_name.text
          end
          @block.preorder_traverse do |node|
            next unless node.is_a? ASTBlock
            next unless node.reaches_view?
            assignments = node.statements.select{ |s| s.is_a?(ASTExprStmt) && s.expr.is_a?(ASTAssignment) }
            variables_read += assignments.map{ |s| s.expr.var_name.text }
          end
          @block.block_replace do |node|
            next unless node.is_a? ASTAssignment
            next if node.var_name.nil? || variables_read.include?(node.var_name.text)
            next if variable_read_by_view node.var_name.text.to_s
            node.expr
          end

          # if the block is a lone either statement, remove empty blocks
          if @block.statements.length == 1 && @block.statements.first.is_a?(ASTEither)
            either = @block.statements.first
            either.blocks.reject!{ |subblock| subblock.statements.empty? }
            if either.blocks.length == 0
              @block = ASTBlock.new(:statements => [])
            elsif either.blocks.length == 1
              @block = either.blocks.first
            else
              @block = ASTBlock.new(:statements => [either])
            end
          end

          new_adsl_ast_size = adsl_ast_size
          break if new_adsl_ast_size == pre_loop_size
        end

        # finally, we can remove all dummy stmts, some of which we used for labels and placeholders and such
        @block = until_no_change @block do |block|
          block.block_replace do |block|
            next unless block.is_a? ASTBlock
            block.statements.reject!{ |s| s.is_a? ADSL::Parser::ASTDummyStmt }
            nil
          end
        end

        self
      end

      def pre_optimize_adsl_ast_size
        @pre_optimize_adsl_ast_size || adsl_ast_size
      end

      def prepend_global_variables_by_signatures(*regexes)
        variable_names = Set[]
        @block.statements.each do |stmt|
          if stmt.is_a?(ASTBlock) || stmt.is_a?(ASTIf) || stmt.is_a?(ASTEither) || stmt.is_a?(ASTForEach)
            stmt.blocks.each do |block|
              block.preorder_traverse do |node|
                next unless node.is_a? ASTVariable
                name = node.var_name.text
                variable_names << name if regexes.map{ |r| r =~ name ? true : false }.include? true
              end
            end
          end
        end
        variable_names.each do |name|
          @block.statements.unshift ASTExprStmt.new(:expr => ASTAssignment.new(
            :var_name => ASTIdent.new(:text => name),
            :expr => ASTEmptyObjset.new
          ))
        end
      end

      def to_adsl
        args = []
        "action #{@name.text} {\n#{ @block.to_adsl.adsl_indent }}\n"
      end
    end

    class ASTBlock < ASTNode
      node_fields :statements
      node_type :statement

      def typecheck_and_resolve(context, open_subcontext=true)
        context.push_frame if open_subcontext
        stmts = []
        @statements.each do |node|
          main_stmt = node.typecheck_and_resolve context
          stmts += context.pre_stmts
          stmts << main_stmt unless main_stmt.nil?
          context.pre_stmts = []
        end
        return ADSL::DS::DSBlock.new :statements => stmts.flatten
      ensure
        context.pop_frame if open_subcontext
      end

      def stmt_type_inevitable(type)
        vals = @statements.map{ |s| s.send type }.uniq
        return true if vals.include? true
        return nil if vals.include? nil
        false
      end

      def blocks
        [self]
      end

      def returns?
        stmt_type_inevitable :returns?
      end

      def raises?
        stmt_type_inevitable :raises?
      end

      def reaches_view?
        stmt_type_inevitable :reaches_view?
      end

      # if there is an assignment before the action, and the exact same assignment repeated in the action,
      # remove the second one.
      #
      # this is to avoid issues like creating an object with default values, authenticating, and recreating
      def remove_overwritten_assignments!(action_label)
        action_index = @statements.index{ |s| s.is_a?(ASTDummyStmt) && s.label.to_s == action_label.to_s }
        return if action_index.nil?

        action_index -= 1
        before_action_assignments = Set[]
        @statements.first(action_index).each do |stmt|
          stmt.preorder_traverse do |node|
            before_action_assignments << node.var_name.text if node.is_a? ASTAssignment
          end
        end

        @statements[action_index..-1].each do |stmt|
          stmt.block_replace do |node|
            if node.is_a?(ASTAssignment)
              if before_action_assignments.delete? node.var_name.text
                # this assigment, and its expression, never happened
                next ASTDummyObjset.new
              end
            elsif node.is_a?(ASTVariable)
              before_action_assignments.delete node.var_name.text
            end
            node
          end
        end
      end

      def remove_statements_after_returns!(tail = [])
        return_statuses = @statements.map &:returns?
        
        if return_statuses.include? true
          first_return_index = return_statuses.index true
          @statements = @statements.first(first_return_index + 1)
          case @statements.last
          when ASTBlock
            @statements.last.remove_statements_after_returns!
          when ASTIf, ASTEither
            @statements.last.blocks.each do |block|
              block.remove_statements_after_returns!
            end
          end
        end

        return_statuses = @statements.map &:returns?
        if return_statuses.include? nil
          first_maybe_return_index = return_statuses.index nil
          stmt = @statements[first_maybe_return_index]
          tail = @statements[(first_maybe_return_index + 1)..-1] + tail
          @statements = @statements.first first_maybe_return_index + 1
          case stmt
          when ASTBlock
            stmt.remove_statements_after_returns! tail
          when ASTIf, ASTEither
            stmt.blocks.each do |block|
              block.remove_statements_after_returns! tail
            end
          else
            raise "Cannot remove statements after returns: #{stmt.class}"
          end
        end

        @statements += tail if return_statuses.uniq == [false]
      end

      def optimize
        super

        return self if @statements.empty?
        return ASTBlock.new :statements => [ASTRaise.new] if raises?
        @statements = @statements.map do |stmt|
          stmt.is_a?(ASTBlock) ? stmt.statements : [stmt]
        end.flatten(1)
        @statements.reject! do |stmt|
          stmt.is_a?(ASTDummyStmt) && stmt.arbitrary?
        end

        self
      end

      def to_adsl
        @statements.map(&:to_adsl).join("")
      end
    end

    class ASTAssignment < ASTNode
      node_fields :var_name, :expr
      node_type :expr
      
      def expr_has_side_effects?; true; end

      def typecheck_and_resolve(context)
        expr = @expr.typecheck_and_resolve context
        var = ADSL::DS::DSVariable.new :name => @var_name.text, :type_sig => expr.type_sig
        context.redefine_var var, @var_name
        create_prestmt = ADSL::DS::DSAssignment.new :var => var, :expr => expr
        context.pre_stmts << create_prestmt
        var
      end

      def to_adsl
        "#{ @var_name.text } = #{ @expr.to_adsl }"
      end
    end

    class ASTDeclareVar < ASTNode
      node_fields :var_name
      node_type :statement

      def typecheck_and_resolve(context)
        var = context.lookup_var @var_name.text, false
        if var.nil?
          ASTExprStmt.new(
            :expr => ASTAssignment.new(:var_name => @var_name.dup, :expr => ASTEmptyObjset.new)
          ).typecheck_and_resolve(context)
        else
          []
        end
      end

      def to_adsl
        "declare #{ @var_name.text }\n"
      end
    end

    class ASTExprStmt < ASTNode
      node_fields :expr
      node_type :statement

      def typecheck_and_resolve(context)
        @expr.typecheck_and_resolve(context)
        return nil
      end

      def optimize
        super
        return ASTDummyStmt.new unless @expr.expr_has_side_effects?
        self
      end

      def to_adsl
        "#{ @expr.to_adsl }\n"
      end
    end

    class ASTAssertFormula < ASTNode
      node_fields :formula
      node_type :statement

      def typecheck_and_resolve(context)
        formula = @formula.typecheck_and_resolve context
        unless formula.type_sig.is_bool_type?
          raise ADSLError, "Asserted formula is not of boolean type (type provided `#{formula.type_sig}` on line #{ @lineno })"
        end
        ADSL::DS::DSAssertFormula.new :formula => formula
      end

      def to_adsl
        "assert #{ @formula.to_adsl }\n"
      end
    end

    class ASTCreateObjset < ASTNode
      node_fields :class_name
      node_type :expr
      
      def expr_has_side_effects?; true; end

      def typecheck_and_resolve(context)
        klass_node, klass = context.classes[@class_name.text]
        raise ADSLError, "Undefined class #{@class_name.text} referred to at line #{@class_name.lineno}" if klass.nil?
        if @create_obj.nil?
          @create_obj = ADSL::DS::DSCreateObj.new :klass => klass
          context.pre_stmts << @create_obj
        end
        ADSL::DS::DSCreateObjset.new :createobj => @create_obj
      end

      def to_adsl
        "create(#{ @class_name.text })"
      end
    end

    class ASTForEach < ASTNode
      node_fields :var_name, :objset, :block
      node_type :statement

      def blocks
        [block]
      end

      def force_flat(value)
        @force_flat = value
      end

      def typecheck_and_resolve(context)
        before_context = context.dup
        objset = @objset.typecheck_and_resolve context

        return [] if objset.type_sig.cardinality.empty?

        unless objset.type_sig.is_objset_type?
          raise ADSLError, "ForEach can iterate over object sets only (type provided `#{objset.type_sig}` on line #{ @lineno })"
        end

        temp_iterator_objset = ASTDummyObjset.new :type_sig => objset.type_sig
        assignment = ASTExprStmt.new(
          :expr => ASTAssignment.new(:lineno => @lineno, :var_name => @var_name, :expr => temp_iterator_objset)
        )
        @block.statements = [assignment, @block.statements].flatten
        
        vars_written_to = Set[]
        vars_read = Set[]
        vars_read_before_being_written_to = Set[]
        
        context.push_frame
        
        context.on_var_write do |name|
          vars_written_to << name
        end
        context.on_var_read do |name|
          var_node, var = context.lookup_var name, false
          vars_read_before_being_written_to << name unless
              vars_written_to.include?(name) or vars_read_before_being_written_to.include? name
          vars_read << name unless vars_read.include? name
        end

        block = @block.typecheck_and_resolve context
        context.pop_frame

        vars_read_before_being_written_to.each do |var_name|
          vars_read_before_being_written_to.delete var_name unless vars_written_to.include? var_name
        end

        vars_needing_post_lambdas = vars_written_to & Set[*before_context.var_stack.map(&:keys).flatten]
        
        flat = if @force_flat.nil?
          if vars_needing_post_lambdas.empty?
            info = ADSL::DS::NodeEffectDomainInfo.new
            block.effect_domain_analysis context, info
            !info.conflicting?
          else
            false
          end
        else
          @force_flat
        end

        if flat
          for_each = ADSL::DS::DSFlatForEach.new :objset => objset, :block => block
        else
          for_each = ADSL::DS::DSForEach.new :objset => objset, :block => block
        end

        vars_read_before_being_written_to.each do |var_name|
          before_var_node, before_var = before_context.lookup_var var_name, false
          inside_var_node, inside_var = context.lookup_var var_name, false
          lambda_expr = ADSL::DS::DSForEachPreLambdaExpr.new(
            :for_each => for_each, :before_var => before_var, :inside_var => inside_var
          )
          var = ADSL::DS::DSVariable.new :name => var_name, :type_sig => before_var.type_sig
          assignment = ADSL::DS::DSAssignment.new :var => var, :expr => lambda_expr
          block.replace before_var, var
          block.statements.unshift assignment
        end
        
        iterator_objset = ADSL::DS::DSForEachIteratorObjset.new :for_each => for_each
        block.replace temp_iterator_objset, iterator_objset

        post_lambda_assignments = vars_needing_post_lambdas.map do |var_name|
          before_var_node, before_var = before_context.lookup_var var_name, false
          inside_var_node, inside_var = context.lookup_var var_name, false
          lambda_expr = ADSL::DS::DSForEachPostLambdaExpr.new(
            :for_each => for_each, :before_var => before_var, :inside_var => inside_var
          )
          var = ADSL::DS::DSVariable.new :name => var_name, :type_sig => before_var.type_sig
          ADSL::DS::DSAssignment.new :var => var, :expr => lambda_expr
        end

        return [for_each, post_lambda_assignments]
      end

      def list_creations
        @block.list_creations
      end

      def optimize
        super
        if @block.statements.empty?
          return ASTExprStmt.new(:expr => @objset).optimize
        end
        self
      end

      def to_adsl
        "foreach #{ @var_name.text } : #{ @objset.to_adsl } {\n#{ @block.to_adsl.adsl_indent }}\n"
      end
    end

    class ASTReturnGuard < ASTNode
      node_fields :block
      node_type :statement
      attr_reader :guard

      def typecheck_and_resolve(context)
        block = @block.typecheck_and_resolve context

        returns = recursively_select do |elem|
          next true if elem.is_a? ADSL::DS::DSReturn
          # stop at a nested return
          next false if elem.is_a? ADSL::DS::DSReturnGuard
        end

        type_sigs = []
        unless returns.empty?
          return_lengths = returns.map{ |ret| ret.exprs.length }
          raise "All return statements need to be the same length" if returns.uniq.length > 1

          length = return_lengths.first
          length.times do |i|
            type_sig = ADSL::DS::TypeSig.join *returns.map{ |ret| ret.exprs[i].type_sig }
            type_sigs << type_sig
          end
        end
          
        @guard ||= ADSL::DS::DSReturnGuard.new :block => block, :ret_type_sigs => type_sigs
      end

      def to_adsl
        "returnguard {\n#{ @block.to_adsl.adsl_indent }}\n"
      end
    end

    class ASTReturn < ASTNode
      node_fields :exprs
      node_type :statement

      def typecheck_and_resolve(context)
        ADSL::DS::DSReturn.new :exprs => @exprs.map{ |e| e.typecheck_and_resolve context }
      end

      def returns?; true; end

      def to_adsl
        "return #{ @expr.to_adsl }\n"
      end
    end

    class ASTReturned < ASTNode
      node_fields :return_guard, :index
      node_type :expr

      def typecheck_and_resolve(context)
        ADSL::DS::DSReturned.new :guard => @return_guard.guard, :index => @index
      end

      def to_adsl
        "Returned !?!?!?!??!?!"
      end
    end

    class ASTRaise < ASTNode
      node_fields
      node_type :statement

      def typecheck_and_resolve(context)
        ADSL::DS::DSRaise.new
      end

      def returns?; false; end

      def raises?; true; end

      def to_adsl
        "raise\n"
      end
    end

    class ASTEither < ASTNode
      node_fields :blocks
      node_type :statement

      def typecheck_and_resolve(context)
        context.push_frame

        contexts = [context]
        (@blocks.length-1).times do
          contexts << context.dup
        end

        blocks = []
        @blocks.length.times do |i|
          blocks << @blocks[i].typecheck_and_resolve(contexts[i])
        end

        contexts.each do |c|
          c.pop_frame
        end

        either = ADSL::DS::DSEither.new :blocks => blocks

        lambdas = []

        ADSL::Parser::Util.context_vars_that_differ(*contexts).each do |var_name, variables|
          variables = variables.map{ |v| ADSL::DS::DSVariableRead.new :variable => v }
          type_sig = ADSL::DS::TypeSig.join variables.map(&:type_sig)
          var = ADSL::DS::DSVariable.new :name => var_name, :type_sig => type_sig
          expr = ADSL::DS::DSEitherLambdaExpr.new :either => either, :exprs => variables
          assignment = ADSL::DS::DSAssignment.new :var => var, :expr => expr
          context.redefine_var var, nil
          lambdas << assignment
        end

        return [ either, lambdas ]
      end

      def list_entity_classes_written_to
        @blocks.map(&:list_entity_classes_written_to).flatten
      end

      def stmt_type_inevitable(type)
        vals = @blocks.map{ |b| b.send type }.uniq
        return true if vals.uniq == [true]
        return false if vals.uniq == [false]
        return nil
      end

      def returns?
        stmt_type_inevitable :returns?
      end

      def raises?
        stmt_type_inevitable :raises?
      end

      def reaches_view?
        stmt_type_inevitable :reaches_view?
      end

      def merge_to_nonreturning_branch(stmts)
        @blocks.each do |block|
          merge_to_nonreturning_branch stmts
        end
      end

      def optimize
        super
       
        @blocks = @blocks.map do |block|
          if block.statements.length == 1 && block.statements.first.is_a?(ASTEither)
            block.statements.first.blocks
          else
            [block]
          end
        end.flatten(1).uniq
        if @blocks.any?{ |b| !b.raises? }
          @blocks.reject! &:raises?
        end
        return ASTDummyStmt.new if @blocks.empty?
        return @blocks.first if @blocks.length == 1

        self
      end

      def to_adsl
        "either #{ @blocks.map{ |b| "{\n#{ b.to_adsl.adsl_indent }}" }.join(" or ") }\n"
      end
    end

    class ASTIf < ASTNode
      node_fields :condition, :then_block, :else_block
      node_type :statement
      attr_reader :ds_if

      def blocks
        [@then_block, @else_block]
      end
      
      def stmt_type_inevitable(type)
        vals = blocks.map{ |b| b.send type }
        return true if vals.uniq == [true]
        return false if vals.uniq == [false]
        return nil
      end

      def returns?
        stmt_type_inevitable :returns?
      end

      def raises?
        stmt_type_inevitable :raises?
      end

      def reaches_view?
        stmt_type_inevitable :reaches_view?
      end

      def merge_to_nonreturning_branch(stmts)
        @blocks.each do |block|
          merge_to_nonreturning_branch stmts
        end
      end

      def typecheck_and_resolve(context)
        context.push_frame
        
        condition = @condition.typecheck_and_resolve(context)
        if condition.type_sig.is_objset_type?
          condition = ADSL::DS::DSNot.new(:subformula => ADSL::DS::DSIsEmpty.new(:objset => condition))
        end
        unless condition.type_sig.is_bool_type?
          raise ADSLError, "If condition is not of boolean type (type provided `#{condition.type_sig}` on line #{ @lineno })"
        end
        
        pre_stmts = context.pre_stmts
        context.pre_stmts = []

        context.push_frame
        
        contexts = [context, context.dup]
        blocks = [
          @then_block.typecheck_and_resolve(contexts[0]),
          @else_block.typecheck_and_resolve(contexts[1])
        ]
        contexts.each{ |c| c.pop_frame; c.pop_frame }

        @ds_if = ADSL::DS::DSIf.new :condition => condition, :then_block => blocks[0], :else_block => blocks[1]

        lambdas = []
        ADSL::Parser::Util.context_vars_that_differ(*contexts).each do |var_name, variables|
          variables = variables.map{ |v| ADSL::DS::DSVariableRead.new :variable => v }
          type_sig = ADSL::DS::TypeSig.join variables.map(&:type_sig)
          var = ADSL::DS::DSVariable.new :name => var_name, :type_sig => type_sig
          expr = ADSL::DS::DSIfLambdaExpr.new :if => @ds_if, :then_expr => variables[0], :else_expr => variables[1]
          assignment = ADSL::DS::DSAssignment.new :var => var, :expr => expr
          context.redefine_var var, nil
          lambdas << assignment
        end

        return [*pre_stmts, ds_if, lambdas]
      end

      def list_entity_classes_written_to
        [@then_block, @else_block].map(&:list_entity_classes_written_to).flatten
      end

      def to_adsl
        if @then_block.statements.empty? && !@else_block.statements.empty?
          return "if not #{@condition.to_adsl} {\n#{ @else_block.to_adsl.adsl_indent }}\n"
        end
        else_code = @else_block.statements.empty? ? "" : " else {\n#{ @else_block.to_adsl.adsl_indent }}"
        "if #{@condition.to_adsl} {\n#{ @then_block.to_adsl.adsl_indent }}#{ else_code }\n"
      end
    end

    class ASTIfExpr < ASTNode
      node_fields :if, :then_expr, :else_expr
      node_type :expr

      def typecheck_and_resolve(context)
        ADSL::DS::DSIfLambdaExpr.new(:if => @if.ds_if,
                                     :then_expr => (@then_expr.typecheck_and_resolve context),
                                     :else_expr => (@else_expr.typecheck_and_resolve context))
      end

      def optimize
        super
        if @if.condition.is_a?(ASTBoolean)
          case @if.condition.bool_value
          when true;  return @then_expr.optimize
          when false; return @else_expr.optimize
          when nil;   return ASTPickOneExpr.new(:exprs => [@then_expr, @else_expr] ).optimize
          else raise 'Invalid boolean expression value'
          end
        end
        if @then_expr == @else_expr
          @if.referred_by_if_expr_count -= 1
          return @then_expr
        end
        self
      end

      def to_adsl
        "ifexpr(#{ @if.condition.to_adsl }, #{ @then_expr.to_adsl }, #{ @else_expr.to_adsl })"
      end
    end

    class ASTDeleteObj < ASTNode
      node_fields :objset
      node_type :statement

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        unless objset.type_sig.is_objset_type?
          raise ADSLError, "DeleteObj can delete object sets only (type provided `#{objset.type_sig}` on line #{ @lineno })"
        end
        return [] if objset.type_sig.cardinality.empty?
        return ADSL::DS::DSDeleteObj.new :objset => objset
      end

      def to_adsl
        "delete #{ @objset.to_adsl }\n"
      end
    end

    class ASTCreateTup < ASTNode
      node_fields :objset1, :rel_name, :objset2
      node_type :statement

      def typecheck_and_resolve(context)
        objset1 = @objset1.typecheck_and_resolve context
        objset2 = @objset2.typecheck_and_resolve context
        
        unless objset1.type_sig.is_objset_type?
          raise ADSLError, "Tuples can be created between object sets only (type provided `#{objset1.type_sig}` on line #{ @lineno })"
        end
        unless objset2.type_sig.is_objset_type?
          raise ADSLError, "Tuples can be created between objset sets only (type provided `#{objset2.type_sig}` on line #{ @lineno })"
        end
        if objset1.type_sig.is_ambiguous_objset_type?
          raise ADSLError, "Ambiguous type on the left hand side on line #{@objset1.lineno}"
        end
        
        return [] if objset1.type_sig.cardinality.empty? || objset2.type_sig.cardinality.empty?
        relation = context.find_member objset1.type_sig, @rel_name.text, @rel_name.lineno, objset2.type_sig
        raise ADSLError, "#{objset1.type_sig}.#{@rel_name.text} is not a relation" unless relation.is_a? ADSL::DS::DSRelation
        return ADSL::DS::DSCreateTup.new :objset1 => objset1, :relation => relation, :objset2 => objset2
      end

      def to_adsl
        "#{ @objset1.to_adsl }.#{ @rel_name.text } += #{ @objset2.to_adsl }\n"
      end
    end

    class ASTDeleteTup < ASTNode
      node_fields :objset1, :rel_name, :objset2
      node_type :statement
      
      def typecheck_and_resolve(context)
        objset1 = @objset1.typecheck_and_resolve context
        objset2 = @objset2.typecheck_and_resolve context
        
        unless objset1.type_sig.is_objset_type?
          raise ADSLError, "Tuples can be deleted between object sets only (type provided `#{objset1.type_sig}` on line #{ @lineno })"
        end
        unless objset2.type_sig.is_objset_type?
          raise ADSLError, "Tuples can be deleted between objset sets only (type provided `#{objset2.type_sig}` on line #{ @lineno })"
        end
        if objset1.type_sig.is_ambiguous_objset_type?
          raise ADSLError, "Ambiguous type on the left hand side on line #{@objset1.lineno}"
        end
        
        return [] if objset1.type_sig.cardinality.empty? || objset2.type_sig.cardinality.empty?
        relation = context.find_member objset1.type_sig, @rel_name.text, @rel_name.lineno, objset2.type_sig
        raise ADSLError, "#{objset1.type_sig}.#{@rel_name.text} is not a relation" unless relation.is_a? ADSL::DS::DSRelation
        return ADSL::DS::DSDeleteTup.new :objset1 => objset1, :relation => relation, :objset2 => objset2
      end

      def to_adsl
        "#{ @objset1.to_adsl }.#{ @rel_name.text } -= #{ @objset2.to_adsl }\n"
      end
    end

    class ASTMemberSet < ASTNode
      node_fields :objset, :member_name, :expr
      node_type :statement

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        expr   = @expr.typecheck_and_resolve context
        
        unless objset.type_sig.is_objset_type?
          raise ADSLError, "Member set possible only on objset sets (type provided `#{objset.type_sig}` on line #{ @lineno })"
        end
        if objset.type_sig.is_ambiguous_objset_type?
          raise ADSLError, "Ambiguous type on the left hand side on line #{@objset.lineno}"
        end

        member = context.find_member objset.type_sig, @member_name.text, @member_name.lineno, expr.type_sig

        if member.is_a?(ADSL::DS::DSRelation)
          stmts = member.type_sig.classes.map do |c|
            ADSL::DS::DSDeleteTup.new(
              :objset1 => objset,
              :relation => member,
              :objset2 => ADSL::DS::DSAllOf.new(:klass => c)
            )
          end
          stmts << ADSL::DS::DSCreateTup.new(:objset1 => objset, :relation => member, :objset2 => expr)
          stmts
        else
          ADSL::DS::DSFieldSet.new(:objset => objset, :field => member, :expr => expr)
        end
      end

      def to_adsl
        "#{ @objset.to_adsl }.#{ @member_name.text } = #{ @expr.to_adsl }\n"
      end
    end

    class ASTAllOf < ASTNode
      node_fields :class_name
      node_type :expr

      def typecheck_and_resolve(context)
        klass_node, klass = context.classes[@class_name.text]
        raise ADSLError, "Unknown class name #{@class_name.text} on line #{@class_name.lineno}" if klass.nil?
        return ADSL::DS::DSAllOf.new :klass => klass
      end

      def list_entity_classes_read
        Set[context.classes[@class_name.text]]
      end

      def to_adsl
        "allof(#{@class_name.text})"
      end
    end

    class ASTSubset < ASTNode
      node_fields :objset
      node_type :expr

      def expr_has_side_effects?
        @objset.nil? ? false : @objset.expr_has_side_effects?
      end

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
       
        unless objset.type_sig.is_objset_type?
          raise ADSLError, "Subset possible only on objset sets (type provided `#{objset.type_sig}` on line #{ @lineno })"
        end

        return ADSL::DS::DSEmptyObjset.new if objset.type_sig.cardinality.empty?
        return objset if objset.type_sig.cardinality.singleton?
        return ADSL::DS::DSSubset.new :objset => objset
      end

      def optimize
        super

        return @objset if @objset.is_a?(ASTSubset) || @objset.is_a?(ASTTryOneOf)
        return ASTTryOneOf.new :objset => @objset.objset if @objset.is_a?(ASTOneOf)

        self
      end

      def to_adsl
        "subset(#{ @objset.to_adsl })"
      end
    end
    
    class ASTTryOneOf < ASTNode
      node_fields :objset
      node_type :expr
      
      def expr_has_side_effects?
        @objset.nil? ? false : @objset.expr_has_side_effects?
      end

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
       
        unless objset.type_sig.is_objset_type?
          raise ADSLError, "TryOneOf possible only on objset sets (type provided `#{objset.type_sig}` on line #{ @lineno })"
        end

        return ADSL::DS::DSEmptyObjset.new if objset.type_sig.cardinality.empty?
        return ADSL::DS::DSTryOneOf.new :objset => objset
      end

      def optimize
        super

        return @objset if @objset.is_a?(ASTOneOf) or @objset.is_a?(ASTTryOneOf)
        @objset = @objset.objset if @objset.is_a?(ASTSubset)

        self
      end

      def to_adsl
        "tryoneof(#{ @objset.to_adsl })"
      end
    end

    class ASTOneOf < ASTNode
      node_fields :objset
      node_type :expr
      
      def expr_has_side_effects?
        @objset.nil? ? false : @objset.expr_has_side_effects?
      end

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
       
        unless objset.type_sig.is_objset_type?
          raise ADSLError, "TryOneOf possible only on objset sets (type provided `#{objset.type_sig}` on line #{ @lineno })"
        end

        return ADSL::DS::DSOneOf.new :objset => objset
      end

      def optimize
        super

        return @objset if @objset.is_a?(ASTOneOf) or @objset.is_a?(ASTTryOneOf)
        @objset = @objset.objset if @objset.is_a?(ASTSubset)
        
        self
      end

      def to_adsl
        "oneof(#{ @objset.to_adsl })"
      end
    end
    
    class ASTUnion < ASTNode
      node_fields :objsets
      node_type :expr
      
      def expr_has_side_effects?
        @objsets.select(&:expr_has_side_effects?).any?
      end

      def typecheck_and_resolve(context)
        objsets = @objsets.map{ |o| o.typecheck_and_resolve context }
        
        objsets.each do |objset|
          unless objset.type_sig.is_objset_type?
            raise ADSLError, "TryOneOf possible only on objset sets (type provided `#{objset.type_sig}` on line #{ @lineno })"
          end
        end

        objsets.reject!{ |o| o.type_sig.cardinality.empty? }
        
        return ADSL::DS::DSEmptyObjset.new if objsets.length == 0
        return objsets.first if objsets.length == 1

        # will raise an error if no single common supertype exists
        ADSL::DS::TypeSig.join objsets.map(&:type_sig)

        return ADSL::DS::DSUnion.new :objsets => objsets
      end

      def optimize
        super

        flat_objsets = @objsets.map{ |objset| objset.is_a?(ASTUnion) ? objset.objsets : [objset] }.flatten(1)
        flat_objsets.reject!{ |o| o.is_a? ASTEmptyObjset }
        flat_objsets.uniq!{ |o| o.expr_has_side_effects? ? o.object_id : o }
        @objsets = flat_objsets

        return ASTEmptyObjset.new if @objsets.empty?
        return @objsets.first if @objsets.length == 1
        ASTUnion.new(:objsets => flat_objsets)

        self
      end

      def to_adsl
        "union(#{ @objsets.map(&:to_adsl).join(', ') })"
      end
    end

    class ASTPickOneExpr < ASTNode
      node_fields :exprs
      node_type :expr
      
      def expr_has_side_effects?
        @exprs.nil? ? false : @exprs.map{ |o| o.expr_has_side_effects? }.include?(true)
      end

      def typecheck_and_resolve(context)
        exprs = @exprs.map{ |o| o.typecheck_and_resolve context }
        
        exprs.each do |expr|
          unless expr.type_sig.is_objset_type?
            raise ADSLError, "Pick one objset possible only on objset sets (type provided `#{expr.type_sig}` on line #{ @lineno })"
          end
        end
        
        # will raise an error if no single common supertype exists
        ADSL::DS::TypeSig.join exprs.map(&:type_sig)
        
        if exprs.length == 0
          ADSL::DS::DSEmptyObjset.new
        elsif exprs.length == 1
          exprs.first
        else
          ADSL::DS::DSPickOneExpr.new :exprs => exprs
        end
      end

      def optimize
        super
        
        return ASTEmptyObjset.new if @exprs.empty?
        return @exprs.first if @exprs.length == 1
        @exprs.uniq!{ |o| o.expr_has_side_effects? ? o.object_id : o }

        self
      end

      def to_adsl
        "pickoneexpr(#{ @exprs.map(&:to_adsl).join ', ' })"
      end
    end
    
    class ASTVariable < ASTNode
      node_fields :var_name
      node_type :expr

      def typecheck_and_resolve(context)
        var_node, var = context.lookup_var @var_name.text
        raise ADSLError, "Undefined variable #{@var_name.text} on line #{@var_name.lineno}" if var.nil?
        ADSL::DS::DSVariableRead.new(:variable => var)
      end

      def to_adsl
        @var_name.text
      end
    end

    class ASTJSExpr < ASTNode
      node_fields :js
      node_type :expr

      def typecheck_and_resolve(context)
        ADSL::DS::DSAnything.new
      end
    end

    class ASTMemberAccess < ASTNode
      node_fields :objset, :member_name
      node_type :expr
      
      def expr_has_side_effects?
        @objset.nil? ? false : @objset.expr_has_side_effects?
      end

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        unless objset.type_sig.is_objset_type?
          raise ADSLError, "Member access possible only on objset sets (type provided `#{objset.type_sig}` on line #{ @lineno })"
        end

        if objset.type_sig.is_ambiguous_objset_type?
          raise ADSLError, "Origin type of member access unknown on line #{lineno}"
        end

        member = context.find_member objset.type_sig, @member_name.text, @member_name.lineno
        if member.is_a?(ADSL::DS::DSRelation)
          ADSL::DS::DSDereference.new :objset => objset, :relation => member
        else
          unless objset.type_sig.cardinality.max == 1
            raise ADSLError, "Field values can only be read on singleton object sets (line #{ @lineno })"
          end
          ADSL::DS::DSFieldRead.new :objset => objset, :field => member
        end
      end

      def to_adsl
        "#{ @objset.to_adsl }.#{ member_name.text }"
      end
    end

    class ASTDereferenceCreate < ASTNode
      node_fields :objset, :rel_name, :empty_first
      node_type :expr

      def expr_has_side_effects?; true; end

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        unless objset.type_sig.is_objset_type?
          raise ADSLError, "Derefcreate possible only on object sets (type provided `#{objset.type_sig}` on line #{ @lineno })"
        end

        raise ADSLError, 'Cannot create an object on an empty objset' if objset.type_sig.cardinality.empty?
        relation = context.find_member objset.type_sig, @rel_name.text, @rel_name.lineno
        unless relation.is_a? ADSL::DS::DSRelation
          raise ADSLError, "#{rel_name} is not a member of class #{objset.type_sig} (line #{@lineno})"
        end
       
        create_objset = ASTCreateObjset.new(
          :class_name => ASTIdent.new(:text => relation.to_class.name)
        )
        
        if @empty_first
          assoc_builder = ASTMemberSet.new(:objset => @objset, :member_name => @rel_name, :expr => create_objset)
        else
          assoc_builder = ASTCreateTup.new(:objset1 => @objset, :rel_name => @rel_name, :objset2 => create_objset)
        end

        context.pre_stmts << assoc_builder.typecheck_and_resolve(context)

        create_objset.typecheck_and_resolve(context)
      end

      def to_adsl
        "create(#{@objset.to_adsl}.#{@rel_name.text})"
      end
    end

    class ASTEmptyObjset < ASTNode
      node_fields
      node_type :expr

      def typecheck_and_resolve(context)
        return ADSL::DS::DSEmptyObjset.new
      end

      def to_adsl
        "empty"
      end
    end

    class ASTCurrentUser < ASTNode
      node_fields
      node_type :expr

      def typecheck_and_resolve(context)
        auth_class_node, auth_class = context.auth_class
        raise ADSLError, "currentuser (line #{@lineno}) cannot be used in lack of an authclass" if auth_class_node.nil?
        return ADSL::DS::DSCurrentUser.new :type_sig => auth_class.to_sig.with_cardinality(1)
      end

      def to_adsl
        "currentuser"
      end
    end

    class ASTInUserGroup < ASTNode
      node_fields :objset, :groupname
      node_type :expr

      def typecheck_and_resolve(context)
        auth_class_node, auth_class = context.auth_class
        if auth_class.nil?
          raise ADSLError, "Inusergroup cannot be used without having defined an authenticable class (line #{@lineno})"
        end
        if @objset
          objset = @objset.typecheck_and_resolve context
          unless objset.type_sig <= auth_class.to_sig
            raise ADSLError, "Only instances of the authenticable class may belong to usergroups (line #{@lineno})"
          end
        else
          objset = ADSL::DS::DSCurrentUser.new
        end
        group = context.usergroups[@groupname.text]
        if group.nil?
          raise ADSLError, "No groupname found by name #{@groupname.text} on line #{@lineno}"
        end
        ADSL::DS::DSInUserGroup.new :objset => objset, :usergroup => group[1]
      end

      def to_adsl
        if @objset.nil? || @objset.is_a?(ASTCurrentUser)
          "inusergroup(#{@groupname.text})"
        else
          "inusergroup(#{@objset.to_adsl}, #{@groupname.text})"
        end
      end
    end

    class ASTAllOfUserGroup < ASTNode
      node_fields :groupname
      node_type :expr

      def typecheck_and_resolve(context)
        auth_class_node, auth_class = context.auth_class
        if auth_class.nil?
          raise ADSLError, "Inusergroup cannot be used without having defined an authenticable class (line #{@lineno})"
        end
        group = context.usergroups[@groupname.text]
        if group.nil?
          raise ADSLError, "No groupname found by name #{@groupname.text} on line #{@lineno}"
        end
        type_sig = auth_class.to_sig.with_cardinality(1)
        ADSL::DS::DSAllOfUserGroup.new :usergroup => group[1], :type_sig => type_sig
      end
    end

    class ASTPermitted < ASTNode
      node_fields :ops, :expr
      node_type :expr

      def typecheck_and_resolve(context)
        auth_class_node, auth_class = context.auth_class
        if auth_class.nil?
          raise ADSLError, "Permissions cannot be checked in a permissionless system (line #{@lineno})"
        end
        
        ops, expr = ADSL::Parser::Util.ops_and_expr_from_nodes context, @ops, @expr
        
        ADSL::DS::DSPermitted.new :ops => ops, :expr => expr
      end

      def to_adsl
        "permitted(#{@ops.map(&:to_s).join ', '} #{@expr.to_adsl})"
      end
    end

    class ASTPermit < ASTNode
      node_fields :group_names, :ops, :expr

      def typecheck_and_resolve(context)
        auth_class_node, auth_class = context.auth_class
        if auth_class.nil?
          raise ADSLError, "Inusergroup cannot be used without having defined an authenticable class (line #{@lineno})"
        end

        groups = @group_names.map do |gn|
          group_name = gn.text
          group = context.usergroups[group_name]
          raise ADSLError, "No groupname found by name #{gn.text} on line #{gn.lineno}" if group.nil?
          group[1]
        end
        groups << ADSL::DS::DSAllUsers.new if groups.empty?

        ops, expr = ADSL::Parser::Util.ops_and_expr_from_nodes context, @ops, @expr

        ADSL::DS::DSPermit.new :usergroups => groups, :ops => ops, :expr => expr
      end

      def to_adsl
        "permit #{ @group_names.map(&:text).join ', ' } #{ @ops.map(&:to_s).join ', ' } #{@expr.to_adsl}\n".gsub(/ +/, ' ')
      end
    end

    class ASTInvariant < ASTNode
      node_fields :name, :formula

      def typecheck_and_resolve(context)
        @formula.preorder_traverse do |node|
          if node.respond_to? :expr_has_side_effects?
            raise ADSLError, "Object set cannot have sideeffects at line #{node.lineno}" if node.expr_has_side_effects?
          end
          if node.class.is_a?(ASTBoolean)
            raise ADSLError, "Star cannot be used in invariants (line #{node.lineno})" if node.bool_value.nil?
          end
          node
        end
        
        formula = @formula.typecheck_and_resolve context
        unless formula.type_sig.is_bool_type?
          raise ADSLError, "Invariant formula is not boolean (type provided `#{formula.type_sig}` on line #{ @lineno })"
        end

        name = @name.nil? ? nil : @name.text
            
        return ADSL::DS::DSInvariant.new :name => name, :formula => formula
      end

      def to_adsl
        n = (@name.nil? || @name.text.nil?) ? "" : "#{ @name.text.gsub(/\s/, '_') }: "
        "invariant #{n}#{ @formula.to_adsl }\n"
      end
    end

    class ASTRule < ASTNode
      node_fields :formula

      def typecheck_and_resolve(context)
        @formula.preorder_traverse do |node|
          if node.respond_to? :expr_has_side_effects?
            raise ADSLError, "Object set cannot have sideeffects at line #{node.lineno}" if node.expr_has_side_effects?
          end
        end
        formula = @formula.typecheck_and_resolve context
        unless formula.type_sig.is_bool_type?
          raise ADSLError, "Rule formula is not boolean (type provided `#{formula.type_sig}` on line #{ @lineno })"
        end

        return ADSL::DS::DSRule.new :formula => formula
      end

      def to_adsl
        "rule #{@formula.to_adsl}\n"
      end
    end

    class ASTBoolean < ASTNode
      node_fields :bool_value
      node_type :expr

      def typecheck_and_resolve(context)
        case @bool_value
        when true;  ADSL::DS::DSConstant::TRUE
        when false; ADSL::DS::DSConstant::FALSE
        when nil;   ADSL::DS::DSConstant::BOOL_STAR
        else raise "Unknown bool value #{@bool_value}"
        end
      end

      def to_adsl
        @bool_value.nil? ? '*' : "#{ @bool_value }"
      end

      TRUE = ASTBoolean.new :bool_value => true
      FALSE = ASTBoolean.new :bool_value => false
    end

    class ASTNumber < ASTNode
      node_fields :value
      node_type :expr

      def typecheck_and_resolve(context)
        type = value.round? ? ADSL::DS::TypeSig::BasicType::INT : ADSL::DS::TypeSig::BasicType::DECIMAL
        return ADSL::DS::DSConstant.new :value => @value, :type_sig => type
      end

      def to_adsl
        value.to_s
      end
    end

    class ASTString < ASTNode
      node_fields :value
      node_type :expr

      def typecheck_and_resolve(context)
        ADSL::DS::DSConstant.new :value => @value, :type_sig => ADSL::DS::TypeSig::BasicType::STRING
      end

      def to_adsl
        "'#{value}'"
      end
    end

    class ASTForAll < ASTNode
      node_fields :vars, :subformula
      node_type :expr

      def typecheck_and_resolve(context)
        context.in_stack_frame do
          vars = []
          objsets = []
          @vars.each do |var_node, objset_node|
            objset = objset_node.typecheck_and_resolve context
            unless objset.type_sig.is_objset_type?
              raise ADSLError, "Quantification possible only over objset sets (type provided `#{objset.type_sig}` on line #{ @lineno })"
            end
        
            var = ADSL::DS::DSQuantifiedVariable.new :name => var_node.text, :type_sig => objset.type_sig
            context.define_var var, var_node

            vars << var
            objsets << objset
          end
          subformula = @subformula.typecheck_and_resolve context
          unless subformula.type_sig.is_bool_type?
            raise ADSLError, "Quantification formula is not boolean (type provided `#{subformula.type_sig}` on line #{ @lineno })"
          end

          return ADSL::DS::DSForAll.new :vars => vars, :objsets => objsets, :subformula => subformula
        end
      end

      def to_adsl
        v = @vars.map{ |var, objset| "#{ var.text } in #{ objset.to_adsl }" }.join ", " 
        "forall(#{v}: #{ @subformula.to_adsl })"
      end

      def optimize
        super

        quantified_vars = Set[]
        @subformula.preorder_traverse do |node|
          quantified_vars << node.var_name.text if node.is_a?(ASTQuantifiedVariable)
        end
        @vars.select! do |v|
          quantified_vars.include? v[0].var_name.text
        end
        return @subformula if @vars.empty?

        self
      end
    end

    class ASTExists < ASTNode
      node_fields :vars, :subformula
      node_type :expr

      def typecheck_and_resolve(context)
        context.in_stack_frame do
          vars = []
          objsets = []
          @vars.each do |var_node, objset_node|
            objset = objset_node.typecheck_and_resolve context
            unless objset.type_sig.is_objset_type?
              raise ADSLError, "Quantification possible only over objset sets (type provided `#{objset.type_sig}` on line #{ @lineno })"
            end
            
            var = ADSL::DS::DSQuantifiedVariable.new :name => var_node.text, :type_sig => objset.type_sig
            context.define_var var, var_node

            vars << var
            objsets << objset
          end
          subformula = @subformula.nil? ? ADSL::DS::DSConstant::TRUE : @subformula.typecheck_and_resolve(context)
          unless subformula && subformula.type_sig.is_bool_type?
            raise ADSLError, "Quantification formula is not boolean (type provided `#{subformula.type_sig}` on line #{ @lineno })"
          end

          return ADSL::DS::DSExists.new :vars => vars, :objsets => objsets, :subformula => subformula
        end
      end
      
      def to_adsl
        v = @vars.map{ |var, objset| "#{ var.text } in #{ objset.to_adsl }" }.join ", " 
        "exists(#{v}: #{ @subformula.nil? ? 'true' : @subformula.to_adsl })"
      end
    end

    class ASTNot < ASTNode
      node_fields :subformula 
      node_type :expr

      def typecheck_and_resolve(context)
        subformula = @subformula.typecheck_and_resolve context
        unless subformula.type_sig.is_bool_type?
          raise ADSLError, "Negation subformula is not boolean (type provided `#{subformula.type_sig}` on line #{ @lineno })"
        end
        return ADSL::DS::DSNot.new :subformula => subformula
      end

      def to_adsl
        "not(#{ @subformula.to_adsl })"
      end

      def optimize
        super

        return @subformula.subformula if @subformula.is_a?(ASTNot)
        if @subformula.is_a?(ASTBoolean)
          if [true, false].include?(@subformula.bool_value)
            return ASTBoolean.new :bool_value => !@subformula.bool_value
          end
        end

        self
      end
    end

    class ASTAnd < ASTNode
      node_fields :subformulae
      node_type :expr

      def typecheck_and_resolve(context)
        subformulae = @subformulae.map{ |o| o.typecheck_and_resolve context }
        subformulae.each do |subformula|
          unless subformula.type_sig.is_bool_type?
            raise ADSLError, "Negation subformula is not boolean (type provided `#{subformula.type_sig}` on line #{ @lineno })"
          end
        end
        return ADSL::DS::DSAnd.new :subformulae => subformulae
      end

      def optimize
        super
        
        @subformulae = @subformulae.map{ |subf| subf.is_a?(ASTAnd) ? subf.subformulae : [subf] }.flatten(1)
        @subformulae.delete ASTBoolean::TRUE
        return ASTBoolean::FALSE if @subformulae.include? ASTBoolean::FALSE
        return ASTBoolean::TRUE if @subformulae.empty?
        return @subformulae.first if @subformulae.length == 1

        self
      end

      def to_adsl
        if @subformulae.length == 1
          @subformulae.first.to_adsl
        elsif @subformulae.length == 2
          "(#{ @subformulae.first.to_adsl } and #{@subformulae.last.to_adsl})"
        else
          string = @subformulae[0].to_adsl
          @subformulae[1..-1].each do |f|
            string = "(#{ string } and #{ f.to_adsl })"
          end
          string
        end
      end
    end
    
    class ASTOr < ASTNode
      node_fields :subformulae
      node_type :expr

      def typecheck_and_resolve(context)
        subformulae = @subformulae.map{ |o| o.typecheck_and_resolve context }
        subformulae.each do |subformula|
          unless subformula.type_sig.is_bool_type?
            raise ADSLError, "Negation subformula is not boolean (type provided `#{subformula.type_sig}` on line #{ @lineno })"
          end
        end
        flattened_subformulae = []
        subformulae.each do |subformula|
          if subformula.is_a? ADSL::DS::DSOr
            flattened_subformulae += subformula.subformulae
          else
            flattened_subformulae << subformula
          end
        end
        return ADSL::DS::DSOr.new :subformulae => flattened_subformulae
      end
      
      def optimize
        super
        
        @subformulae = @subformulae.map{ |subf| subf.is_a?(ASTOr) ? subf.subformulae : [subf] }.flatten(1)
        @subformulae.delete ASTBoolean::FALSE
        return ASTBoolean::TRUE if @subformulae.include? ASTBoolean::TRUE
        return ASTBoolean::FALSE if @subformulae.empty?
        return @subformulae.first if @subformulae.length == 1

        self
      end

      def to_adsl
        if @subformulae.empty?
          return "(false)"
        elsif @subformulae.length == 1
          @subformulae.first.to_adsl
        elsif @subformulae.length == 2
          "(#{ @subformulae.first.to_adsl } or #{@subformulae.last.to_adsl})"
        else
          string = @subformulae[0].to_adsl
          @subformulae[1..-1].each do |f|
            string = "(#{ string } or #{ f.to_adsl })"
          end
          string
        end
      end
    end

    class ASTXor < ASTNode
      node_fields :subformulae
      node_type :expr

      def typecheck_and_resolve(context)
        subformulae = @subformulae.map{ |o| o.typecheck_and_resolve context }
        subformulae.each do |subformula|
          unless subformula.type_sig.is_bool_type?
            raise ADSLError, "Xor subformula is not boolean (type provided `#{subformula.type_sig}` on line #{ @lineno })"
          end
        end
        return ADSL::DS::DSXor.new :subformulae => subformulae
      end

      def optimize
        super
          
        @subformulae.delete ASTBoolean::FALSE
        if @subformulae.include? ASTBoolean::TRUE
          return ASTBoolean::FALSE if @subformulae.count(ASTBoolean::TRUE) >= 2
          return ASTAnd.new(:subformulae => @subformulae.reject(ASTBoolean::TRUE)).optimize
        end
        if @subformulae.empty
          return ASTBoolean::FALSE
        elsif @subformulae.length == 1
          return @subformulae.first
        end

        self
      end

      def to_adsl
        if @subformulae.length == 1
          @subformulae.first.to_adsl
        elsif @subformulae.length == 2
          "(#{ @subformulae[0].to_adsl } xor #{ @subformulae[1].to_adsl })"
        else
          string = @subformulae[0].to_adsl
          @subformulae[1..-1].each do |f|
            string = "(#{ string } xor #{ f.to_adsl })"
          end
          string
        end
      end
    end

    class ASTImplies < ASTNode
      node_fields :subformula1, :subformula2
      node_type :expr

      def typecheck_and_resolve(context)
        subformula1 = @subformula1.typecheck_and_resolve context
        subformula2 = @subformula2.typecheck_and_resolve context
        unless subformula1.type_sig.is_bool_type?
          raise ADSLError, "Implication subformula 1 is not boolean (type provided `#{subformula1.type_sig}` on line #{ @lineno })"
        end
        unless subformula2.type_sig.is_bool_type?
          raise ADSLError, "Implication subformula 2 is not boolean (type provided `#{subformula2.type_sig}` on line #{ @lineno })"
        end
        return ADSL::DS::DSImplies.new :subformula1 => subformula1, :subformula2 => subformula2
      end

      def to_adsl
        "implies(#{ @subformula1.to_adsl }, #{ @subformula2.to_adsl })"
      end
    end

    class ASTEqual < ASTNode
      node_fields :exprs
      node_type :expr
      
      def typecheck_and_resolve(context)
        exprs = @exprs.map{ |o| o.typecheck_and_resolve context }

        # will raise an error if no single common supertype exists
        if ADSL::DS::TypeSig.join(exprs.map(&:type_sig), false).is_invalid_type?
          raise ADSLError, "Comparison of incompatible types #{exprs.map(&:type_sig).map(&:to_s).join ' and '} on line #{@lineno}"
        end
          
        return ADSL::DS::DSEqual.new :exprs => exprs
      end
      
      def optimize
        super

        @exprs.uniq!
        if @exprs.include? ASTBoolean::TRUE
          return ASTAnd.new(:subformulae => @exprs).optimize
        end
        if @exprs.include? ASTBoolean::FALSE
          return ASTAnd.new(:subformulae => @exprs.map{ |sub| ASTNot.new(:subformula => sub) }).optimize
        end
        # if there are fewer than 2 elements, we had duplicates making 'equal' trivially true
        return ASTBoolean::TRUE if subs.length < 2

        self
      end
      
      def to_adsl
        "equal(#{ @exprs.map(&:to_adsl).join ", " })"
      end
    end

    class ASTIn < ASTNode
      node_fields :objset1, :objset2
      node_type :expr

      def typecheck_and_resolve(context)
        objset1 = @objset1.typecheck_and_resolve context
        objset2 = @objset2.typecheck_and_resolve context
        
        unless objset1.type_sig.is_objset_type?
          raise ADSLError, "In relation possible only on objset sets (type provided `#{objset1.type_sig}` on line #{ @lineno })"
        end
        unless objset2.type_sig.is_objset_type?
          raise ADSLError, "In relation possible only on objset sets (type provided `#{objset2.type_sig}` on line #{ @lineno })"
        end
        
        return ADSL::DS::Boolean::TRUE if objset1.type_sig.cardinality.empty?
        return ADSL::DS::Boolean::FALSE if objset1.type_sig.cardinality.min > objset2.type_sig.cardinality.max
        return ADSL::DS::DSEmpty.new :objset => objset1 if objset2.type_sig.cardinality.empty?

        unless objset1.type_sig <= objset2.type_sig
          raise ADSLError, "Object sets are not of compatible types: #{objset1.type_sig} and #{objset2.type_sig}"
        end
        return ADSL::DS::DSIn.new :objset1 => objset1, :objset2 => objset2
      end
      
      def to_adsl
        "#{ @objset1.to_adsl } in #{ @objset2.to_adsl }"
      end

      def optimize
        super

        return ASTBoolean::TRUE if @objset1.is_a? ASTEmptyObjset
        return ASTBoolean::FALSE if @objset2.is_a? ASTEmptyObjset

        self
      end
    end
    
    class ASTIsEmpty < ASTNode
      node_fields :objset
      node_type :expr

      def typecheck_and_resolve(context)
        objset = @objset.typecheck_and_resolve context
        unless objset.type_sig.is_objset_type?
          raise ADSLError, "IsEmpty possible only on objset sets (type provided `#{objset.type_sig}` on line #{ @lineno })"
        end
        return ADSL::DS::DSConstant::TRUE if objset.type_sig.cardinality.empty?
        return ADSL::DS::DSConstant::FALSE if objset.type_sig.cardinality.any?
        return ADSL::DS::DSIsEmpty.new :objset => objset
      end

      def optimize
        super
        return ASTBoolean::TRUE if @objset.is_a? ASTEmptyObjset
        return ASTBoolean::FALSE if @objset.is_a?(ASTOneOf) || @objset.is_a?(ASTCurrentUser)
        self
      end

      def to_adsl
        "isempty(#{ @objset.to_adsl })"
      end
    end
  end
end
