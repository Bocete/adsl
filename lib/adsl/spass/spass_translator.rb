require 'adsl/spass/ruby_extensions'
require 'adsl/fol/first_order_logic'

module ADSL
  module Spass
    module SpassTranslator

      def replace_conjecture(input, conjecture)
        input.gsub(/list_of_formulae\s*\(\s*conjectures\s*\)\s*\..*?end_of_list\./m, <<-SPASS)
        list_of_formulae(conjectures).
          formula(#{conjecture.resolve_spass}).
        end_of_list.
        SPASS
      end

      class Predicate
        attr_accessor :name, :arity
        
        include FOL

        def initialize(name, arity)
          @name = name
          @arity = arity
        end

        def [](*args)
          args = args.flatten
          return "#{@name}(#{ (1..@arity).map{ |i| "${#{i}}"}.join(", ") })".resolve_params(*args)
        end
      end
      
      class ContextCommon
        attr_accessor :parent, :level

        def type_pred(*args)
          return @level == 0 ? 'true' : @type_pred[*args.flatten]
        end

        def initialize(translation, name, parent)
          @level = parent.nil? ? 0 : parent.level + 1
          @translation = translation
          @parent = parent
          
          unless parent.nil?
            @type_pred = translation.create_predicate(name, @level)
            
            translation.reserve_names @parent.p_names do |ps|
              translation.create_formula FOL::ForAll.new(ps, :c, FOL::Implies.new(
                type_pred(ps, :c), @parent.type_pred(ps)
              ))
            end
            translation.reserve_names @parent.p_names, @parent.p_names, :c do |p1s, p2s, c|
              translation.create_formula FOL::ForAll.new(p1s, p2s, :c, FOL::Implies.new(
                FOL::And.new(type_pred(p1s, c), type_pred(p2s, c)),
                FOL::PairwiseEqual.new(p1s, p2s)
              ))
            end
          end
        end

        def same_level_before_formula(parents, c1, c2)
          raise 'To be implemented'
        end

        def p_names(num = level)
          num.times.map{ |i| "p#{i+1}".to_sym }
        end

        def self.get_common_context(c1, c2)
          while c1.level > c2.level
            c1 = c1.parent
          end
          while c2.level > c1.level
            c2 = c2.parent
          end
          while c1 != c2
            c1 = c1.parent
            c2 = c2.parent
          end
          return c1
        end

        def before(c2, c1var, c2var, executed_before)
          c1 = self
          @translation.reserve_names((1..c1.level-1).map{|i| "parent_a#{i}"}) do |context1_names|
            @translation.reserve_names((1..c2.level-1).map{|i| "parent_b#{i}"}) do |context2_names|
              context1_names << c1var
              context2_names << c2var
              common_context = ContextCommon.get_common_context c1, c2
              prereq_formulae = FOL::And.new(c1.type_pred(context1_names), c2.type_pred(context2_names))

              solution = executed_before
              parent_args = context1_names.first(common_context.level)
              parent_args.pop
              while common_context.parent
                c1_name = context1_names[common_context.level-1]
                c2_name = context2_names[common_context.level-1]
                solution = FOL::And.new(
                  FOL::Implies.new(common_context.same_level_before_formula(parent_args, c1_name, c2_name), true),
                  FOL::Implies.new(common_context.same_level_before_formula(parent_args, c2_name, c1_name), false),
                  FOL::Implies.new(
                    FOL::Not.new(
                      common_context.same_level_before_formula(parent_args, c1_name, c2_name),
                      common_context.same_level_before_formula(parent_args, c2_name, c1_name)
                    ),
                    solution
                  )
                )
                common_context = common_context.parent
                parent_args.pop
              end
              solution = FOL::Implies.new(FOL::And.new(prereq_formulae), solution)
              if context1_names.length > 1 or context2_names.length > 1
                solution = FOL::ForAll.new([context1_names[0..-2], context2_names[0..-2]], solution)
              end
              return solution
            end
          end
        end
      end

      class FlatContext < ContextCommon
        def initialize(translation, name, parent)
          super
        end

        def same_level_before_formula(ps, c1, c2)
          false
        end
      end

      class ChainedContext < ContextCommon
        attr_accessor :before_pred, :just_before, :first, :last
        include FOL

        def initialize(translation, name, parent)
          super

          @before_pred = translation.create_predicate "#{@type_pred.name}_before", @type_pred.arity + 1
          @just_before = translation.create_predicate "#{@type_pred.name}_just_before", @type_pred.arity + 1
          @first = translation.create_predicate "#{@type_pred.name}_first", @type_pred.arity
          @last = translation.create_predicate "#{@type_pred.name}_last", @type_pred.arity

          ps = []
          (@type_pred.arity-1).times{ |i| ps << "p#{i}" }
          translation.create_formula _for_all(ps, :c, _not(@before_pred[ps, :c, :c]))
          translation.create_formula _for_all(ps, :c1, :c2, _implies(@before_pred[ps, :c1, :c2], _and(
            @type_pred[ps, :c1],
            @type_pred[ps, :c2],
            _not(@before_pred[ps, :c2, :c1]),
            _implies(
              _and(@type_pred[ps, :c1], @type_pred[ps, :c2]),
              _or(_equal(:c1, :c2), @before_pred[ps, :c1, :c2], @before_pred[ps, :c2, :c1])
            )
          )))
          translation.create_formula _for_all(ps, :c1, :c2, :c3, _implies(
            _and(@before_pred[ps, :c1, :c2], @before_pred[ps, :c2, :c3]),
            @before_pred[ps, :c1, :c3]
          ))
          translation.create_formula _for_all(ps, :c1, :c2, _equiv(
            @just_before[ps, :c1, :c2],
            _and(
              @before_pred[ps, :c1, :c2],
              _not(_exists(:mid, _and(@before_pred[ps, :c1, :mid], @before_pred[ps, :mid, :c2])))
            )
          ))
          translation.create_formula _for_all(ps, _and(
            _equiv(
              _exists(:c, @type_pred[ps, :c]),
              _exists(:c, @first[ps, :c]),
              _exists(:c, @last[ps, :c])
            ),
            _for_all(ps, :c, _implies(
              @type_pred[ps, :c],
              _one_of(@last[ps, :c], _exists(:next, @just_before[ps, :c, :next]))
            )),
            _for_all(ps, :c, _equiv(@first[ps, :c],
              _and(@type_pred[ps, :c], _not(_exists(:pre, @before_pred[ps, :pre, :c])))
            )),
            _for_all(ps, :c, _equiv(@last[ps, :c],
              _and(@type_pred[ps, :c], _not(_exists(:post, @before_pred[ps, :c, :post])))
            ))
          ))
        end

        def same_level_before_formula(ps, c1, c2)
          @before_pred[ps, c1, c2]
        end
      end

      class Translation
        attr_accessor :context, :state
        attr_reader :existed_initially, :exists_finally, :root_context
        attr_reader :is_object, :is_tuple, :is_either_resolution, :resolved_as_true
        attr_reader :create_obj_stmts, :delete_obj_stmts, :all_contexts, :classes
        attr_reader :conjectures

        include FOL

        def initialize
          @classes = []
          @temp_vars = []
          @functions = []
          @predicates = []
          @formulae = [[]]
          @conjectures = []
          @all_contexts = []
          @existed_initially = create_predicate :existed_initially, 1
          @exists_finally = create_predicate :exists_finally, 1
          @is_object = create_predicate :is_object, 1
          @is_tuple = create_predicate :is_tuple, 1
          @is_either_resolution = create_predicate :is_either_resolution, 1
          @root_context = create_context 'root_context', true, nil
          @context = @root_context
          # {class => [[before_stmt, context], [after_stmt, context]]}
          @create_obj_stmts = Hash.new{ |hash, klass| hash[klass] = [] }
          @delete_obj_stmts = Hash.new{ |hash, klass| hash[klass] = [] }
          @state = create_state :init_state
        end

        def create_state name
          state = create_predicate name, @context.level + 1
          reserve_names([:c_1] * @context.level, :o) do |cs, o|
            create_formula FOL::ForAll.new(cs, o, FOL::Implies.new(
              state[cs, o],
              FOL::And.new(@context.type_pred(cs), FOL::Or.new(@is_object[o], @is_tuple[o]))
            ))
          end
          state
        end

        def create_context(name, flat, parent)
          context = nil
          if flat
            context = FlatContext.new self, name, parent
          else
            context = ChainedContext.new self, name, parent
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

        def create_formula(formula)
          raise ArgumentError, 'Formula not resolveable to Spass' unless formula.class.method_defined? :resolve_spass
          @formulae.last.push formula
        end

        def create_conjecture(formula)
          raise ArgumentError, 'Formula not resolveable to Spass' unless formula.class.method_defined? :resolve_spass
          @conjectures.push formula
        end

        def create_function(name, arity)
          function = Predicate.new get_pred_name(name.to_s), arity
          @functions << function
          function
        end

        def create_predicate(name, arity)
          pred = Predicate.new get_pred_name(name.to_s), arity
          @predicates << pred
          pred
        end
        
        def get_pred_name common_name
          registered_names = (@functions + @predicates).map{ |a| a.name }
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
          names.flatten.length.times do
            @temp_vars.pop
          end 
        end

        def gen_formula_for_unique_arg(pred, *args)
          individuals = []
          args.each do |arg|
            arg = arg.is_a?(Range) ? arg.to_a : [arg].flatten
            next if arg.empty?
            vars1 = (1..pred.arity).map{ |i| "e#{i}" }
            vars2 = vars1.dup
            as = []
            bs = []
            arg.each do |index|
              a = "a#{index+1}".to_sym
              vars1[index] = a
              b = "b#{index+1}".to_sym
              vars2[index] = b
              as << a
              bs << b
            end
            reserve_names (vars1 | vars2) do
              individuals << _for_all(vars1 | vars2, _implies(_and(pred[vars1], pred[vars2]), _pairwise_equal(as, bs)))
            end
          end
          return true if individuals.empty?
          formula = _and(individuals)
          create_formula formula
          return formula
        end

        def spass_wrap(with, what)
          return "" if what.length == 0
          return with % what
        end

        def spass_list_of(what, *content)
          spass_wrap "list_of_#{what.to_s}.%s\nend_of_list.", content.flatten.map{ |c| "\n  " + c.to_s }.join("")
        end

        def to_spass_string
          functions = @functions.map{ |f| "(#{f.name}, #{f.arity})" }.join(", ")
          predicates = @predicates.map{ |p| "(#{p.name}, #{p.arity})" }.join(", ")
          formulae = @formulae.first.map do |f|
            begin
              next "formula(#{f.resolve_spass})."
            rescue => e
              pp f
              raise e
            end
          end
          conjectures = @conjectures.map{ |f| "formula(#{f.resolve_spass})." }
          <<-SPASS
          begin_problem(Blahblah).
          list_of_descriptions.
            name({* *}).
            author({* *}).
            status(satisfiable).
            description( {* *} ).
          end_of_list.
          #{spass_list_of( :symbols,
            spass_wrap("functions[%s].", functions),
            spass_wrap("predicates[%s].", predicates)
          )}
          #{spass_list_of( "formulae(axioms)",
            formulae
          )}
          #{spass_list_of( "formulae(conjectures)",
            conjectures
          )}
          end_problem.
          SPASS
        end

      end
    end

  end
end
