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
      attr_reader :create_obj_stmts, :delete_obj_stmts, :all_contexts, :classes
      attr_reader :conjectures

      include FOL

      def initialize
        @classes = []
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
        @either_resolution = create_sort :EitherResolution
        # {class => [[before_stmt, context], [after_stmt, context]]}
        @create_obj_stmts = Hash.new{ |hash, klass| hash[klass] = [] }
        @delete_obj_stmts = Hash.new{ |hash, klass| hash[klass] = [] }
        @state = @initial_state
      end

      def create_sort name
        sort = Sort.new *_reserve_names(name)
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
            name = name.to_s if name.is_a? TypedString
            while @temp_vars.include? name
              name = name.to_s.increment_suffix.to_sym
            end
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
        sort = Sort.new get_pred_name(name)
        @sorts << sort
        sort
      end

      def create_conjecture(formula)
        @conjectures.push formula
      end

      def create_function(ret_sort, name, *sorts)
        function = Function.new ret_sort, get_pred_name(name.to_s), *sorts
        @functions << function
        function
      end

      def create_predicate(name, *sorts)
        pred = Predicate.new get_pred_name(name.to_s), sorts
        @predicates << pred
        pred
      end
      
      def get_pred_name common_name
        registered_names = (@functions + @predicates + @sorts).map &:name
        prefix = common_name
        prefix = common_name.scan(/^(.+)_\d+$/).first.first if prefix =~ /^.+_\d+$/
        regexp = /^#{ Regexp.escape prefix }(?:_(\d+))?$/

        already_registered = registered_names.select{ |a| a =~ regexp }
        return common_name if already_registered.empty?
        
        rhs_numbers = already_registered.map{ |a| [a, a.scan(regexp).first.first] }
        
        rhs_numbers.each do |a|
          a[1] = a[1].nil? ? -1 : a[1].to_i
        end

        max_name = rhs_numbers.max_by{ |a| a[1] }
        return max_name[0].increment_suffix
      end

      def _reserve_names(*names)
        result = []
        names.each do |name|
          if name.is_a? Array
            result << _reserve_names(*name)
          else
            while @temp_vars.include? name
              name = name.to_s.increment_suffix.to_sym
            end
            @temp_vars.push name
            result << name
          end
        end
        result
      end

      def reserve_names(*names)
        result = _reserve_names(*names)
        yield *result
      ensure
        @temp_vars.pop names.flatten.length
      end
    
      def to_fol
        return ADSL::FOL::Theorem.new(
          :sorts => @sorts,
          :predicates => @predicates,
          :functions => @functions,
          :axioms => @formulae.flatten,
          :conjecture => And[@conjectures].optimize
        )
      end

    end
  end
end
