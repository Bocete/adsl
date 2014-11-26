require 'adsl/fol/first_order_logic'
require 'adsl/translation/typed_string'
require 'adsl/translation/context'
require 'adsl/translation/state'

module ADSL
  module Translation

    class DSTranslator
      attr_accessor :context
      attr_accessor :initial_state, :state, :final_state
      attr_reader :root_context
      attr_reader :create_obj_stmts, :all_contexts, :classes
      attr_reader :conjectures

      include FOL

      def initialize
        @classes = []
        # the pool of symbol names that are used
        @registered_names = []
        # the pool of variable names that are used
        @temp_vars = []
        @functions = []
        @predicates = []
        @sorts = []
        @formulae = [[]]
        @conjectures = []
        @all_contexts = []

        @root_context = create_context 'root_context', true, nil, nil
        @context = @root_context
        
        @initial_state = create_state :init_state
        # klass => Set[ [stmt] ]
        @create_obj_stmts = Hash.new{ |hash, klass| hash[klass] = [] }
        @state = @initial_state
      end

      def create_sort name
        sort = Sort.new *register_names(name)
        @sorts << sort
        sort
      end

      def create_state name
        state = ADSL::Translation::State.new self, name, @context.sort_array
        state
      end

      def create_context(name, flat, sort, parent)
        if flat
          context = FlatContext.new self, name, sort, parent
        else
          context = ChainedContext.new self, name, sort, parent
        end
        @all_contexts << context
        context
      end

      def push_formula_frame
        @formulae.push []
      end

      def pop_formula_frame
        @formulae.pop
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
        And.new(
          sorts.map do |s|
            reserve s, :o do |o|
              ForAll.new(o, Equiv.new(s1[ps1, o], s2[ps2, o]))
            end
          end
        )
      end

      def create_formula(formula)
        @formulae.last.push formula
      end

      def create_sort(name)
        sort = Sort.new register_name(name)
        @sorts << sort
        sort
      end

      def create_conjecture(formula)
        @conjectures.push formula
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

      def register_name(name)
        name = name.to_s
        name = name.increment_suffix while @registered_names.include? name
        @registered_names << name
        name
      end
      
      def to_fol
        additional_axioms = []

        @create_obj_stmts.each do |klass, stmts|
          reserve stmts.map{ |s| s.context.make_ps } do |pss|
            statement_ps_pairs = stmts.zip pss
            additional_axioms << ADSL::FOL::ForAll.new(pss, ADSL::FOL::And.new(
              statement_ps_pairs.map{ |stmt, ps| ADSL::FOL::Not.new @initial_state[stmt.context_creation_link[ps]] },
	            statement_ps_pairs.each_index.map do |i|
	              others = statement_ps_pairs[i+1..-1]
		            others.map{ |other, other_ps|
		              ADSL::FOL::Not.new(ADSL::FOL::Equal.new(
		                statement_ps_pairs[i][0].context_creation_link[statement_ps_pairs[i][1]],
		                other.context_creation_link[other_ps]
		              ))
		            }
	            end
	          ))
          end
        end

        return ADSL::FOL::Theorem.new(
          :sorts => @sorts,
          :predicates => @predicates,
          :functions => @functions,
          :axioms => @formulae.flatten + additional_axioms,
          :conjecture => And[@conjectures].optimize
        )
      end

    end
  end
end
