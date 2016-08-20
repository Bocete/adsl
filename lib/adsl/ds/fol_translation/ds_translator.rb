require 'adsl/fol/first_order_logic'
require 'adsl/ds/fol_translation/typed_string'
require 'adsl/ds/fol_translation/state/state_manager'
require 'adsl/ds/fol_translation/loop_context/loop_context_manager'

module ADSL
  module DS
    module FOLTranslation

      class DSTranslator
        attr_accessor :initial_state, :state, :final_state, :non_state
        attr_accessor :current_user
        attr_reader :create_obj_stmts
        attr_reader :spec
        attr_reader :conjectures, :formulae
        attr_reader :return_guard_stack
        attr_reader :branch_conditions
  
        include LoopContext::LoopContextManager
        include State::StateManager
        
        include FOL
  
        def initialize(spec)
          @spec = spec
          # the pool of symbol names that are used
          @registered_names = []
          # the pool of variable names that are used
          @temp_vars = []
          @functions = []
          @predicates = []
          @sorts = []
          @formulae = []
          @conjectures = []

          initialize_loop_context_manager
          initialize_state_manager
          
          # klass => Set[ [stmt] ]
          @return_guard_stack = []
          @branch_conditions = []
        end
  
        def create_sort name
          sort = Sort.new *register_names(name)
          @sorts << sort
          sort
        end
  
        def for_all(*args, &block)
          _quantify ADSL::FOL::ForAll, *args, block
        end
  
        def exists(*args, &block)
          _quantify ADSL::FOL::ForAll, *args, block
        end
  
        def _quantify(klass, *args, block)
          reserve *args do |*reserved|
            formula = block[*reserved]
            klass.new *reserved.flatten.map(&:unroll), formula
          end
        end
  
        def reserve(*args)
          flat = args.flatten
          flat.try_map!(:unroll).flatten!
          flat.try_map!(:to_sort)
          types, names = flat.select_reject{ |a| a.is_a? ADSL::FOL::Sort }
          if types.length != names.length
            raise ArgumentError, "Number of types and names mismatched (#{types.length} and #{names.length})"
          end
          vars = _create_vars types, args
          begin
            yield *vars
          ensure
            @temp_vars.pop names.length
          end
        end
  
        def _create_vars(sorts, names)
          result = []
          names.each do |name|
            if name.is_a? Array
              result << _create_vars(sorts, name)
            elsif name.is_a?(String) || name.is_a?(Symbol) || name.is_a?(TypedString)
              name = name.to_s
              name = name.increment_suffix while @registered_names.include?(name) or @temp_vars.include?(name)
              @temp_vars.push name
              var = TypedString.new sorts.shift, name 
              result << var
            end
          end
          result
        end
        
        def states_equivalent_formula(sorts, ps1, s1, ps2, s2)
          And[*sorts.map{ |s|
            reserve(s, :o){ |o|
              ForAll[o, Equiv[s1[ps1, o], s2[ps2, o]]]
            }
          }]
        end
  
        def create_formula(formula)
          @formulae.push formula
        end
  
        def create_sort(name)
          sort = Sort.new register_name(name)
          @sorts << sort
          sort
        end
  
        def create_conjecture(formula)
          @conjectures.push formula
        end
  
        def set_conjecture(formula)
          @conjectures = [formula]
        end
  
        def create_function(ret_sort, name, *sorts)
          function = Function.new ret_sort, register_name(name), *sorts
          @functions << function
          function
        end
  
        def create_predicate(name, *sorts)
          pred = Predicate.new register_name(name), sorts
          @predicates << pred
          pred
        end
  
        def auth_class
          @spec.classes.select(&:authenticable?).first
        end
  
        def register_name(name)
          name = name.to_s
          name = name.increment_suffix while @registered_names.include? name
          @registered_names << name
          name
        end
  
        def with_state(state)
          old_state = @state
          @state = state
          return yield
        ensure
          @state = old_state
        end

        def to_fol
          return ADSL::FOL::Theorem.new(
            :sorts => @sorts,
            :predicates => @predicates,
            :functions => @functions,
            :axioms => @formulae,
            :conjecture => And[@conjectures].optimize
          ).optimize!
        end

      end
    end
  end
end
