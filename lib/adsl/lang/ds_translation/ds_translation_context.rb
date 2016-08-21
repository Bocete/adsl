require 'adsl/lang/ds_translation/stack_frame'

module ADSL
  module Lang
    module DSTranslation
      class DSTranslationContext
        attr_accessor :classes, :usergroups, :members, :actions, :invariants, :ac_rules, :rules, :stack_frame_stack
  
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
          @stack_frame_stack = []
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
          @stack_frame_stack = source.stack_frame_stack.map{ |frame| frame.dup }
        end
        
        def on_var_write(&block)
          @stack_frame_stack.last.on_var_write(&block)
        end
        
        def on_var_read(&block)
          @stack_frame_stack.last.on_var_read(&block)
        end
  
        def in_stack_frame
          push_frame
          yield
        ensure
          pop_frame
        end
  
        def push_frame
          @stack_frame_stack.push StackFrame.new
        end
  
        def pop_frame
          @stack_frame_stack.pop
        end
  
        def add_ds_statement(ds_node)
          @stack_frame_stack.last << ds_node
        end
  
        def define_var(var, node)
          raise ADSLError, "Defining variables on a stack with no stack frames" if @stack_frame_stack.empty?
          prev_var_node, prev_var = lookup_var var.name
          raise ADSLError, "Duplicate identifier '#{var.name}' on line #{node.lineno}; previous definition on line #{prev_var_node.lineno}" unless prev_var.nil?
          @stack_frame_stack.last[var.name] = [node, var]
          @stack_frame_stack.last.fire_write_event var.name
          return var
        end
  
        def redefine_var(var, node)
          @stack_frame_stack.length.times do |frame_index|
            frame = @stack_frame_stack[frame_index]
            next unless frame.include? var.name
            
            old_var = frame[var.name][1]
            type_sig = old_var.type_sig & var.type_sig
            if type_sig.is_invalid_type?
              raise ADSLError, "Unmatched type signatures '#{ old_var.type_sig }' and  '#{ var.type_sig }' for variable '#{var.name}' on line #{node.lineno}"
            end
            var.type_sig = type_sig
            
            frame[var.name][1] = var

            @stack_frame_stack[frame_index..-1].reverse.each do |subframe|
              subframe.fire_write_event var.name
            end
            
            return var
          end
          return define_var var, node
        end
  
        def lookup_var(name, fire_read_event=true)
          @stack_frame_stack.length.times do |index|
            frame = @stack_frame_stack[index]
            next if frame[name].nil?
            node, var = frame[name]
  
            if fire_read_event
              @stack_frame_stack[index..-1].reverse.each do |subframe|
                subframe.fire_read_event name
              end
            end

            # handle events here, none defined atm
            return node, var
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
      
        def relations_around(*classes)
          classes = classes.flatten.map do |c|
            c.respond_to?(:to_a) ? c.to_a : c
          end
          classes = Set[*classes.flatten]
          Set[*@members.values.map(&:values).flatten(1).map(&:last).select do |rel|
            rel.is_a?(ADSL::DS::DSRelation) && (classes.include?(rel.from_class) || classes.include?(rel.to_class))
          end]
        end
        
        def self.context_vars_that_differ(*contexts)
          vars_per_context = []
          contexts.each do |context|
            vars_per_context << context.stack_frame_stack.inject(ActiveSupport::OrderedHash.new) { |so_far, frame| so_far.merge! frame }
          end
          all_vars = vars_per_context.map{ |c| c.keys }.flatten.uniq
          packed = ActiveSupport::OrderedHash.new
          all_vars.each do |v|
            packed[v] = vars_per_context.select{ |vpc| vpc.include? v }.map{ |vpc| vpc[v][1] }
          end
          packed.delete_if { |v, vars| vars.uniq.length == 1 }
          packed
        end
      end
    end
  end
end
