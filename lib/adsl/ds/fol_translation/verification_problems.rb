require 'set'
require 'adsl/ds/data_store_spec'
require 'adsl/fol/first_order_logic'

module ADSL
  module DS
    class DSSpec < DSNode
      def generate_problems(action_name, invariants = nil, access_control = true)
        action = @actions
        problems = []

        problems += (invariants || @invariants).map{ |inv| ADSL::Translation::InvariantVerificationProblem.new inv }

        if access_control
          action = find_action_by_name action_name
          if auth_class && action && @ac_rules.any?
            # creates
            sigs = action.recursively_gather do |elem|
              elem.klass.to_sig if elem.is_a? DSCreateObj
            end
            problems += sigs.uniq.map{ |sig| ADSL::Translation::AccessControlCreateProblem.new sig }

            # deletes
            sigs = action.recursively_gather do |elem|
              elem.objset.type_sig if elem.is_a? DSDeleteObj
            end
            problems += sigs.uniq.map{ |sig| ADSL::Translation::AccessControlDeleteProblem.new sig }
            
            # reads
            assignments = action.recursively_gather{ |elem|
              elem if elem.is_a?(DSAssignment)
            }
            assignments = assignments.group_by{ |asgn| asgn.var.name }.map do |name, assignments|
              next unless name.start_with?('at__')
              assignments.reverse.find{ |asgn| asgn.expr.type_sig.is_objset_type? && !asgn.expr.type_sig.cardinality.empty? }
            end.compact
            problems += assignments.map do |asgn|
              ADSL::Translation::AccessControlReadProblem.new ADSL::DS::DSVariableRead.new(:variable => asgn.var)
            end

            # assocs
            # rels = action.recursively_gather do |elem|
            #   elem.relation if elem.is_a?(DSCreateTup)
            # end
            # problems += rels.uniq.map{ |rel| ADSL::Translation::AccessControlAssocProblem.new rel }

            # deassocs
            # rels = action.recursively_gather do |elem|
            #   elem.relation if elem.is_a?(DSDeleteTup)
            # end
            # problems += rels.uniq.map{ |rel| ADSL::Translation::AccessControlDeassocProblem.new rel }
          end
        end
        
        problems
      end

      def gen_is_permissible_formula(translation, op, ps, var_type_sig, var)
        ADSL::FOL::Or[*@ac_rules.map{ |rule| rule.gen_covers_formula translation, op, ps, var_type_sig, var }]
      end
    end
  end
  
  module Translation  
    class FOLVerificationProblem
      attr_accessor :fol

      def initialize(fol, name = nil)
        @fol = fol
        @name = name
      end

      def generate_conjecture(translation)
        @fol
      end

      def name
        "custom formula #{@name}".strip
      end

      def to_adsl
        "problem(#{ @fol.to_adsl })"
      end
    end

    class InvariantVerificationProblem
      def initialize(*listed_invariants)
        @listed_invariants = (listed_invariants.empty? ? spec.invariants : listed_invariants).dup
      end

      def generate_conjecture(translation)
        translation.state = translation.initial_state
        pre_invariants = translation.spec.invariants.map do |invariant|
          invariant.formula.resolve_expr(translation, [])
        end
        
        translation.state = translation.final_state
        post_invariants = @listed_invariants.map do |invariant|
          invariant.formula.resolve_expr(translation, [])
        end
        
        FOL::Implies.new(
          FOL::And.new(pre_invariants),
          FOL::And.new(post_invariants)
        )
      end

      def name
        if @listed_invariants.length == 1
          "invariant #{ @listed_invariants.first.name }"
        else
          "invariants #{ @listed_invariants.map(&:name).join ', ' }"
        end
      end

      def to_adsl
        "invariantproblem(#{ @listed_invariants.map(&:name).join ', '}"
      end
    end
    
    class AccessControlCreateProblem
      include FOL
      attr_accessor :domain

      def initialize(domain)
        @domain = domain
      end

      def generate_conjecture(translation)
        translation.reserve @domain, :o do |o|
          translation.state = translation.final_state
          permitted_formula = translation.spec.gen_is_permissible_formula(translation, :create, [], @domain, o)
          ForAll[o, Implies[
            And[
              Not[translation.initial_state[o]],
              translation.final_state[o]
            ],
            permitted_formula
          ]]
        end
      end

      def name
        "ac creation #{@domain}"
      end

      def to_adsl
        "ac_create_problem(#{@domain})"
      end
    end

    class AccessControlDeleteProblem
      include FOL
      attr_accessor :domain

      def initialize(domain)
        @domain = domain
      end

      def generate_conjecture(translation)
        translation.reserve @domain, :o do |o|
          translation.state = translation.initial_state
          permitted_formula = translation.spec.gen_is_permissible_formula(translation, :delete, [], @domain, o)
          return ForAll[o, Implies[
            And[
              translation.initial_state[o],
              Not[translation.final_state[o]]
            ],
            permitted_formula
          ]].optimize
        end
      end

      def name
        "ac deletion #{@domain}"
      end
      
      def to_adsl
        "ac_delete_problem(#{@domain})"
      end
    end

    class AccessControlReadProblem
      include FOL
      attr_accessor :expr

      def initialize(expr)
        @expr = expr
      end

      def generate_conjecture(translation)
        translation.reserve @expr.type_sig, :o do |o|
          translation.state = translation.final_state
          permitted_formula = translation.spec.gen_is_permissible_formula(translation, :read, [], @expr.type_sig, o)

          translation.reserve translation.current_loop_context.make_ps do |ps|
            return ForAll[o, Implies[
              And[translation.final_state[o], @expr.resolve_expr(translation, ps, o)],
              permitted_formula
            ]].optimize
          end
        end
      end

      def name
        "ac read #{@expr.variable.name}"
      end
      
      def to_adsl
        "ac_read_problem(#{@expr.to_adsl})"
      end
    end

    class AccessControlAssocProblem
      include FOL

      attr_accessor :relation

      def initialize(relation)
        @relation = relation
      end

      def generate_conjecture(translation)
        translation.reserve @relation.type_pred_sort, :t do |t|
          translation.state = translation.final_state
          from_create_formula = translation.spec.gen_is_permissible_formula translation, :create, [], @relation.from_class.to_sig, @relation.left_link[t]
          from_read_formula   = translation.spec.gen_is_permissible_formula translation, :read,   [], @relation.from_class.to_sig, @relation.left_link[t]
          to_create_formula   = translation.spec.gen_is_permissible_formula translation, :create, [], @relation.to_class.to_sig,   @relation.right_link[t]
          to_read_formula     = translation.spec.gen_is_permissible_formula translation, :read,   [], @relation.to_class.to_sig,   @relation.right_link[t]
          return ForAll[t, Implies[
            And[
              Not[translation.initial_state[t]],
              translation.final_state[t]
            ],
            Or[
              And[from_create_formula, to_read_formula],
              And[from_read_formula,   to_create_formula],
              And[from_create_formula, to_create_formula]
            ]
          ]].optimize
        end
      end

      def name
        "ac assoc #{@relation}"
      end

      def to_adsl
        "ac_assoc_problem(#{@relation})"
      end
    end

    class AccessControlDeassocProblem
      include FOL

      attr_accessor :relation

      def initialize(relation)
        @relation = relation
      end

      def generate_conjecture(translation)
        translation.reserve @relation.type_pred_sort, :t do |t|
          translation.state = translation.initial_state
          from_delete_formula = translation.spec.gen_is_permissible_formula translation, :delete, [], @relation.from_class.to_sig, @relation.left_link[t]
          from_read_formula   = translation.spec.gen_is_permissible_formula translation, :read,   [], @relation.from_class.to_sig, @relation.left_link[t]
          to_delete_formula   = translation.spec.gen_is_permissible_formula translation, :delete, [], @relation.to_class.to_sig,   @relation.right_link[t]
          to_read_formula     = translation.spec.gen_is_permissible_formula translation, :read,   [], @relation.to_class.to_sig,   @relation.right_link[t]
          return ForAll[t, Implies[
            And[
              translation.initial_state[t],
              Not[translation.final_state[t]]
            ],
            Or[
              And[from_delete_formula, to_read_formula],
              And[from_read_formula,   to_delete_formula],
              And[from_delete_formula, to_delete_formula]
            ]
          ]].optimize
        end
      end

      def name
        "ac deassoc #{@relation}"
      end

      def to_adsl
        "ac_deassoc_problem(#{@relation})"
      end
    end

  end
end
