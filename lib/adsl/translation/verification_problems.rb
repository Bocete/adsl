require 'set'
require 'adsl/ds/data_store_spec'

module ADSL
  module DS
    class DSSpec < DSNode
      def generate_problems(action_name)
        action = @actions
        problems = []

        problems += @invariants.map{ |inv| ADSL::Translation::InvariantVerificationProblem.new self, inv }

        action = find_action_by_name action_name
        if auth_class && action
          # creates
          sigs = action.recursively_gather do |elem|
            elem.klass.to_sig if elem.is_a? DSCreateObj
          end
          problems += sigs.uniq.map{ |sig| ADSL::Translation::AccessControlCreateProblem.new self, sig }

          # deletes
          sigs = action.recursively_gather do |elem|
            elem.objset.type_sig if elem.is_a? DSDeleteObj
          end
          problems += sigs.uniq.map{ |sig| ADSL::Translation::AccessControlDeleteProblem.new self, sig }
          
          # reads
          assignments = action.recursively_gather{ |elem|
            elem if elem.is_a?(DSAssignment)
          }.reverse.uniq{ |asgn| asgn.var.name }
          problems += assignments.map{ |asgn| ADSL::Translation::AccessControlReadProblem.new self, asgn }

          # assocs
          rels = action.recursively_gather do |elem|
            elem.relation if elem.is_a?(DSCreateTup)
          end
          problems += rels.uniq.map{ |rel| ADSL::Translation::AccessControlAssocProblem.new self, rel }
          
          # deassocs
          rels = action.recursively_gather do |elem|
            elem.relation if elem.is_a?(DSDeleteTup)
          end
          problems += rels.uniq.map{ |rel| ADSL::Translation::AccessControlDeassocProblem.new self, rel }
        end

        problems
      end
    end

    class DSPermit < DSNode
      def relevant_to?(op, type_sig)
        return false unless @ops.include?(op)
        if op == :assoc || op == :deassoc
          @expr.relation == type_sig
        else
          @expr.type_sig >= type_sig
        end
      end
    end
  end
  
  module Translation  
    module VerificationProblemUtil
      def relevant_permits(op)
        @spec.ac_rules.select{ |ac_rule| ac_rule.relevant_to? op, domain }
      end
    end

    class FOLVerificationProblem
      attr_accessor :spec, :fol

      def initialize(spec, fol)
        @spec = spec
        @fol = fol
      end

      def generate_conjecture(translation)
        @fol
      end
    end

    class InvariantVerificationProblem
      attr_accessor :spec

      def initialize(spec, *listed_invariants)
        @spec = spec
        @listed_invariants = listed_invariants.empty? ? spec.invariants : listed_invariants
      end

      def generate_conjecture(translation)
        translation.state = translation.initial_state
        pre_invariants = @spec.invariants.map{ |invariant| invariant.formula.resolve_expr(translation, []) }
        
        translation.state = translation.final_state
        post_invariants = @listed_invariants.map{ |invariant| invariant.formula.resolve_expr(translation, []) }
        
        FOL::Implies.new(
          FOL::And.new(pre_invariants),
          FOL::And.new(post_invariants)
        )
      end
    end
    
    class AccessControlCreateProblem
      include FOL
      include VerificationProblemUtil
      attr_accessor :spec, :domain

      def initialize(spec, domain)
        @spec = spec
        @domain = domain
      end

      def generate_conjecture(translation)
        translation.reserve @domain, :o do |o|
          permit_applicables = relevant_permits(:create).map do |permit|
            translation.state = translation.final_state
            post_expr = permit.expr.resolve_expr translation, [], o
            group_applicable = Or[*permit.usergroups.map{ |g| g[translation.current_user[]] }]
            And[
              post_expr,
              group_applicable
            ]
          end
          return ForAll[o, Implies[
            And[
              Not[translation.initial_state[o]],
              translation.final_state[o]
            ],
            Or[
              *permit_applicables
            ]
          ]].optimize
        end
      end
    end

    class AccessControlDeleteProblem
      include FOL
      include VerificationProblemUtil
      attr_accessor :spec, :domain

      def initialize(spec, domain)
        @spec = spec
        @domain = domain
      end

      def generate_conjecture(translation)
        translation.reserve @domain, :o do |o|
          permit_applicables = relevant_permits(:delete).map do |permit|
            translation.state = translation.initial_state
            pre_expr = permit.expr.resolve_expr translation, [], o
            group_applicable = Or[*permit.usergroups.map{ |g| g[translation.current_user[]] }]
            And[
              pre_expr,
              group_applicable
            ]
          end
          return ForAll[o, Implies[
            And[
              translation.initial_state[o],
              Not[translation.final_state[o]]
            ],
            Or[*permit_applicables]
          ]].optimize
        end
      end
    end

    class AccessControlReadProblem
      include FOL
      include VerificationProblemUtil
      
      attr_accessor :spec, :asgn

      def initialize(spec, asgn)
        @spec = spec
        @asgn = asgn
      end

      def domain
        @asgn.expr.type_sig
      end

      def generate_conjecture(translation)
        return true if @asgn.var.context.level > 0
        translation.reserve @asgn.expr.type_sig, :o do |o|
          permit_applicables = relevant_permits(:read).map do |permit|
            translation.state = translation.final_state
            expr = permit.expr.resolve_expr translation, [], o
            group_applicable = Or[*permit.usergroups.map{ |g| g[translation.current_user[]] }]
            And[expr, group_applicable]
          end

          translation.reserve @asgn.var.context.make_ps do |ps|
            return ForAll[o, Implies[
              @asgn.expr.resolve_expr(translation, ps, o),
              Or[*permit_applicables]
            ]].optimize
          end
        end
      end
    end

    require 'adsl/prover/spass/fol_extensions'

    class AccessControlAssocProblem
      include FOL
      include VerificationProblemUtil

      attr_accessor :spec, :relation

      def initialize(spec, relation)
        @spec = spec
        @relation = relation
      end

      def domain
        @relation
      end

      def generate_conjecture(translation)
        translation.reserve @relation.type_pred_sort, :t do |t|
          permit_applicables = relevant_permits(:assoc).map do |permit|
            translation.state = translation.final_state
            deref = permit.expr
            expr = deref.objset
            post_expr = And[
              expr.resolve_expr(translation, [], @relation.left_link[t]),
              translation.final_state[t],
              translation.final_state[@relation.right_link[t]]
            ]
            group_applicable = Or[*permit.usergroups.map{ |g| g[translation.current_user[]] }]
            And[
              post_expr,
              group_applicable
            ]
          end
          return ForAll[t, Implies[
            And[
              Not[translation.initial_state[t]],
              translation.final_state[t]
            ],
            Or[*permit_applicables]
          ]].optimize
        end
      end
    end

    class AccessControlDeassocProblem
      include FOL
      include VerificationProblemUtil

      attr_accessor :spec, :relation

      def initialize(spec, relation)
        @spec = spec
        @relation = relation
      end

      def domain
        @relation
      end

      def generate_conjecture(translation)
        translation.reserve @relation.type_pred_sort, :t do |t|
          permit_applicables = relevant_permits(:deassoc).map do |permit|
            translation.state = translation.initial_state
            deref = permit.expr
            expr = deref.objset
            pre_expr = And[
              expr.resolve_expr(translation, [], @relation.left_link[t]),
              translation.initial_state[t],
              translation.initial_state[@relation.right_link[t]]
            ]
            group_applicable = Or[*permit.usergroups.map{ |g| g[translation.current_user[]] }]
            And[
              pre_expr,
              group_applicable
            ]
          end
          return ForAll[t, Implies[
            And[
              translation.initial_state[t],
              Not[translation.final_state[t]]
            ],
            Or[*permit_applicables]
          ]].optimize
        end
      end
    end

  end
end
