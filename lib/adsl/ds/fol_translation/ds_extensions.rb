require 'adsl/ds/fol_translation/ds_translator'
require 'adsl/ds/fol_translation/state/state'
require 'adsl/ds/fol_translation/util'
require 'adsl/ds/fol_translation/verification_problems'
require 'adsl/fol/first_order_logic'
require 'adsl/ds/data_store_spec'
require 'adsl/ds/type_sig'

module ADSL
  module DS

    class DSNode
      def replace_var(from, to); end
    end
    
    class DSSpec < DSNode

      def find_action_by_name(action_name)
        return nil if action_name.nil?
        actions = @actions.select{ |a| a.name == action_name }
        raise ArgumentError, "Action '#{action_name}' not found" if actions.empty?
        actions.first
      end

      def translate_classes(translation)
        done_classes = Set[]
        todo_classes = Set[*@classes]
        until todo_classes.empty?
          candidates = todo_classes.select do |klass|
            Set[*klass.parents].subset? done_classes
          end
          todo_classes -= candidates
          done_classes += candidates
          candidates.each do |klass|
            klass.translate translation
          end
        end
      end
      
      def translate_action(action_name, *problems)
        translation = ADSL::DS::FOLTranslation::DSTranslator.new self

        action = find_action_by_name action_name

        translate_classes translation

        relations = @classes.map{ |c| c.relations }.flatten
        # translate relations 
        relations.select{ |r| r.inverse_of.nil? }.each do |relation|
          relation.translate(translation)
        end
        relations.select{ |r| r.inverse_of }.each do |relation|
          relation.translate(translation)
        end

        # classes of the same sort have mutually exclusive precise_type_preds
        @classes.group_by(&:to_sort).each do |sort, klasses|
          children_rels = Hash.new{|hash, key| hash[key] = []}
          klasses.each do |klass|
            if klass.parents.empty?
              children_rels[nil] << klass
            else
              klass.parents.each do |parent|
                children_rels[parent] << klass
              end
            end
          end
          klasses.each do |klass|
            translation.create_formula FOL::ForAll.new(sort, :o, FOL::And.new(
              # define precise type pred
              FOL::Equiv.new(
                klass.precise_type_pred[:o],
                FOL::And.new(
                  klass[:o],
                  FOL::Not.new(*children_rels[klass].map{ |c| c[:o] })
                )
              ),
              # being of this class implies all parent classes
              FOL::Implies.new(
                klass[:o],
                FOL::And.new(*klass.parents.map{ |p| p[:o] })
              )
            ))
          end
          # define that existing in the initial state implies that the object exists
          translation.reserve sort, :o do |o|
            translation.create_formula FOL::ForAll.new(o, FOL::Implies.new(
              translation.initial_state[o],
              FOL::Or.new(*children_rels[nil].map{ |klass| klass[o] })
            ))
          end
        end

        relations = @classes.map{ |c| c.relations }.flatten
        relation_sorts = relations.map(&:to_sort).uniq
        
        # define authentication
        if auth_class
          @usergroups.each do |ug|
            ug.translate translation
          end
          translation.current_user = translation.create_function auth_class.to_sort, 'current_user'
          translation.create_formula ADSL::FOL::And.new(
            auth_class[translation.current_user[]],
            translation.initial_state[translation.current_user[]]
          )
        end

        @rules.each do |rule|
          translation.create_formula rule.formula.resolve_expr(translation, [])
        end

        translation.state = translation.initial_state
        # enforce cardinality in the first state
        relations.each do |rel|
          rel.enforce_cardinality translation
          rel.enforce_consistent_state translation
        end

        action.translate(translation) if action_name
      
        # make sure all create objs create mutually exclusive stuff
        action.create_objsets.each do |sort, creates|
          translation.reserve creates.map{ |s| s.loop_context.make_ps } do |pss|
            statement_ps_pairs = creates.zip pss
            translation.create_formula ADSL::FOL::ForAll.new(pss, ADSL::FOL::And.new(
              statement_ps_pairs.map{ |stmt, ps| ADSL::FOL::Not.new translation.initial_state[stmt.loop_context_creation_link[ps]] },
	            statement_ps_pairs.each_index.map do |i|
	              others = statement_ps_pairs[i+1..-1]
		            others.map{ |other, other_ps|
		              ADSL::FOL::Not.new(ADSL::FOL::Equal.new(
		                statement_ps_pairs[i][0].loop_context_creation_link[statement_ps_pairs[i][1]],
		                other.loop_context_creation_link[other_ps]
		              ))
		            }
	            end
	          ))
          end
        end

        # enforce cardinality in the final state too
        relations.each do |rel|
          rel.enforce_cardinality translation
        end

        problem_formulas = problems.map{ |p| p.generate_conjecture translation }
        if problem_formulas.include? nil
          raise "Problem #{ problems[problem_formulas.index nil] } not translated to a formula"
        end
        translation.set_conjecture ADSL::FOL::And[*problem_formulas].optimize

        return translation
      end

    end
    
    class DSAction < DSNode
      include FOL

      def translate(translation)
        translation.current_loop_context = translation.root_loop_context
        @block.migrate_state translation
        translation.final_state = translation.state
      end

      def create_objsets
        create_objsets = recursively_gather{ |r| r.is_a?(DSCreateObj) ? r : nil }.uniq
        create_objsets.group_by{ |co| co.klass.to_sort }
      end
    end

    module TypeSig
      class ObjsetType
        def to_sort
          @classes.first.to_sort
        end

        def [](arg)
          if arg.respond_to?(:to_sort) && arg.to_sort != self.to_sort
            raise "Invalid sort #{arg.to_sort.name} used for objset type #{self}"
          end
          ADSL::FOL::And.new(@classes.map(&:type_pred).map{ |a| a[arg] }).optimize
        end
      end
    end
    
    class DSClass < DSNode
      attr_accessor :type_pred, :precise_type_pred

      def to_sort
        @parents.empty? ? @sort : @parents.first.to_sort
      end

      def [](arg)
        type_pred[arg]
      end

      def translate(translation)
        @sort = translation.create_sort "#{@name}Sort" if @parents.empty?
        sort = to_sort
        @type_pred = translation.create_predicate @name, sort
        @precise_type_pred = translation.create_predicate "Precisely#{@name}", sort
      end

      def enforce_relation_consistency(translation)
        relations.each do |r|
          r.enforce_consistent_state translation
        end
      end
    end

    class DSRelation < DSNode
      include FOL
      attr_accessor :type_pred

      def [](variable)
        @type_pred[variable]
      end

      def to_sort
        @inverse_of.nil? ? @sort : @inverse_of.to_sort
      end
      
      def left_link
        @inverse_of.nil? ? @left_link : @inverse_of.right_link
      end
      
      def right_link
        @inverse_of.nil? ? @right_link : @inverse_of.left_link
      end

      def type_pred_sort
        @inverse_of.nil? ? @sort : @inverse_of.type_pred_sort
      end

      def translate(translation)
        if @inverse_of.nil?
          name = "Assoc#{@from_class.name}#{@name.camelize}"
          @sort = translation.create_sort "#{name}Sort"
          @type_pred = translation.create_predicate name, @sort
          @left_link = translation.create_function @from_class.to_sort, "#{name}_left", @sort
          @right_link = translation.create_function  @to_class.to_sort, "#{name}_right", @sort
          translation.create_formula ForAll[@sort, :t, And[
            @from_class[@left_link[:t]],
            @to_class[@right_link[:t]]
          ]]
        end
      end

      def enforce_cardinality(translation)
        translation.reserve @from_class, :o, to_sort, :t1, to_sort, :t2 do |o, t1, t2|
          if @cardinality.min > 0
            translation.create_formula ForAll[o, Implies[
              translation.state[o], Exists[t1, And[translation.state[t1], Equal[o, left_link[t1]]]]
            ]]
          end
          if @cardinality.max == 1
            translation.create_formula ForAll[o, t1, t2, Implies[
              And[
                translation.state[o], translation.state[t1], translation.state[t2],
                Equal[o, left_link[t1], left_link[t2]]
              ],
              Equal[t1, t2]
            ]]
          end
        end
      end

      def enforce_consistent_state(translation)
        translation.reserve translation.current_loop_context.make_ps, type_pred_sort, :t do |ps, t|
          translation.create_formula ForAll[ps, t, Implies[
            translation.state[ps, t],
            And[translation.state[ps, left_link[t]], translation.state[ps, right_link[t]]]
          ]]
        end
      end
    end

    class DSUserGroup < DSNode
      attr_accessor :pred

      def translate(translation)
        @pred = translation.create_predicate "UserGroup#{@name}", translation.auth_class.to_sort
        translation.create_formula ADSL::FOL::ForAll[translation.auth_class.to_sort, :o, ADSL::FOL::Implies[
          @pred[:o],
          translation.auth_class[:o]
        ]]
      end

      def [](o)
        @pred[o]
      end
    end

    class DSAllUsers < DSNode
      def translate(translation)
      end

      def [](o)
        true
      end
    end

    class DSInUserGroup < DSNode
      def resolve_expr(translation, ps, var = nil)
        if @objset.respond_to? :resolve_singleton_expr
          @usergroup[@objset.resolve_singleton_expr translation, ps]
        else
          translation.reserve translation.auth_class, :o do |o|
            return ADSL::FOL::ForAll[o, ADSL::FOL::Implies[
              @objset.resolve_expr(translation, ps, o),
              @usergroup[o]
            ]]
          end
        end
      end
    end

    class DSCurrentUser < DSNode
      def resolve_expr(translation, ps, var)
        ADSL::FOL::Equal.new(translation.current_user[], var)
      end

      def resolve_singleton_expr(translation, ps, var=nil)
        translation.current_user[]
      end
    end

    class DSAllOfUserGroup < DSNode
      def resolve_expr(translation, ps, var)
        @usergroup[var]
      end
    end

    class DSPermitted < DSNode
      def resolve_expr(translation, ps, var = nil)
        ADSL::FOL::And[*@ops.map do |op|
          translation.reserve @expr.type_sig, :o do |o|
            permitted = translation.spec.gen_is_permissible_formula(translation, op, ps, @expr.type_sig, o)
            ADSL::FOL::ForAll.new o, ADSL::FOL::Implies.new(
              @expr.resolve_expr(translation, ps, o),
              permitted
            )
          end
        end]
      end
    end

    class DSPermit < DSNode
      def gen_covers_formula(translation, op, ps, var_type_sig, var)
        return false unless @ops.include? op
        return false unless @expr.type_sig >= var_type_sig

        ADSL::FOL::And[
          ADSL::FOL::Or[*@usergroups.map{ |g| g[translation.current_user[]] }],
          @expr.resolve_expr(translation, ps, var)
        ]
      end
    end

    class DSInvariant < DSNode
    end
    
    class DSRule < DSNode
    end

    class DSCreateObj < DSNode
      include FOL
      attr_reader :loop_context_creation_link, :loop_context

      def migrate_state(translation)
        @loop_context = translation.current_loop_context
        
        @loop_context_creation_link = translation.create_function(
          @klass.to_sort,
          "created_#{@klass.name}_in_context", *@loop_context.sort_array
        )

        post_state = translation.create_state "post_create_#{@klass.name}"
        prev_state = translation.state
        translation.reserve @loop_context.make_ps do |ps|
          translation.reserve @klass.to_sort, :o do |o|
            translation.create_formula ForAll.new(ps, Implies.new(
              @loop_context.type_pred(ps),
              And[
                Not.new(prev_state[ps, @loop_context_creation_link[ps]]),
                @klass.precise_type_pred[@loop_context_creation_link[ps]],
                ForAll[o, Equiv.new(Or.new(prev_state[ps, o], Equal[o, @loop_context_creation_link[ps]]), post_state[ps, o])]
              ]
            ))
          end
 
          relations = @klass.to_sig.classes.map(&:relations).flatten.uniq
          relevant_relations = relations.map do |r|
            relevant_links = []
            relevant_links << r.left_link  if @klass.to_sig.classes.any?{ |klass| r.from_class >= klass }
            relevant_links << r.right_link if @klass.to_sig.classes.any?{ |klass| r.to_class >= klass }
            [r, relevant_links]
          end.select{ |r, links| links.any? }
          
          translation.create_formula ForAll.new(ps, Implies.new(
            @loop_context.type_pred(ps),
            And[relevant_relations.map do |rel, links|
              translation.reserve rel, :r do |r|
                ForAll[r, Not[And[
                  prev_state[ps, r],
                  Or[links.map{ |link| Equal[@loop_context_creation_link[ps], link[r]] }]
                ]]]
              end
            end]
          ))
        end
  
        post_state.link_to_previous_state prev_state
        translation.state = post_state
      end
    end

    class DSCreateObjset < DSNode
      include FOL

      def resolve_expr(translation, ps, var)
        Equal[@createobj.loop_context_creation_link[ps], var]
      end

      def resolve_singleton_expr(translation, ps, var=nil)
        @createobj.loop_context_creation_link[ps]
      end
    end

    class DSDeleteObj < DSNode
      include FOL

      def migrate_state(translation)
        type_sig = @objset.type_sig
        return if type_sig.cardinality.empty?

        pre_state = translation.state
        post_state = translation.create_state "post_delete_#{type_sig.underscore}"
        sort = type_sig.to_sort
        context = translation.current_loop_context
        
        translation.reserve context.make_ps do |ps|
          translation.reserve sort, :o do |o|
            deleted_pred = translation.create_predicate "deleted_objset", *context.sort_array, @objset.type_sig.to_sort

            translation.create_formula ForAll[ps, o, Equiv[
              deleted_pred[ps, o],
              @objset.resolve_expr(translation, ps, o)
            ]]

            translation.create_formula ForAll.new(ps, o,
              Equiv.new(
                post_state[ps, o],
                And.new(pre_state[ps, o], Not.new(deleted_pred[ps, o]))
              )
            )

            relations = type_sig.classes.map(&:relations).flatten.uniq
            relevant_relations = relations.map do |r|
              relevant_links = []
              relevant_links << r.left_link  if type_sig.classes.any?{ |klass| r.from_class >= klass }
              relevant_links << r.right_link if type_sig.classes.any?{ |klass| r.to_class >= klass }
              [r, relevant_links]
            end.select{ |r, links| links.any? }

            translation.create_formula ForAll.new(ps, Implies.new(
              translation.current_loop_context.type_pred(ps),
              And[relevant_relations.map do |rel, links|
                translation.reserve rel, :r do |r|
                  ForAll[r, Equiv[
                    post_state[ps, r],
                    And[
                      pre_state[ps, r],
                      links.map{ |link| Not[deleted_pred[ps, link[r]]] }
                    ]
                  ]]
                end
              end]
            ))
          end
        end

        post_state.link_to_previous_state pre_state
        translation.state = post_state
      end
    end

    class DSCreateTup < DSNode
      include FOL
     
      def migrate_state(translation)
        return if @objset1.type_sig.cardinality.empty? or @objset2.type_sig.cardinality.empty?

        state = translation.create_state "post_createref_#{@relation.from_class.name}_#{@relation.name}"
        prev_state = translation.state
        context = translation.current_loop_context

        translation.reserve context.make_ps, @relation.to_sort, :r, @objset1.type_sig, :o1, @objset2.type_sig, :o2 do |ps, r, o1, o2|
          objset1_predicate = translation.create_predicate('create_tup_objset1', *context.sort_array, @objset1.type_sig.to_sort)
          translation.create_formula ForAll[ps, o1, Equiv[
            objset1_predicate[ps, o1],
            @objset1.resolve_expr(translation, ps, o1)
          ]]
          objset2_predicate = translation.create_predicate('create_tup_objset2', *context.sort_array, @objset2.type_sig.to_sort)
          translation.create_formula ForAll[ps, o2, Equiv[
            objset2_predicate[ps, o2],
            @objset2.resolve_expr(translation, ps, o2)
          ]]
          
          links_match = 
          translation.create_formula FOL::ForAll.new(ps, r, FOL::Equiv.new(
            state[ps, r],
            Or.new(
              prev_state[ps, r],
              And.new(
                objset1_predicate[ps, @relation.left_link[r]],
                objset2_predicate[ps, @relation.right_link[r]]
              )
            )
          ))
          # this is needed because the quantification above does not force tuples to exist
          translation.create_formula FOL::ForAll.new(ps, o1, o2, FOL::Implies.new(
            And.new(
              objset1_predicate[ps, o1],
              objset2_predicate[ps, o2]
            ),
            FOL::Exists.new(r, And.new(
              state[ps, r],
              Equal.new(@relation.left_link[r], o1),
              Equal.new(@relation.right_link[r], o2),
            ))
          ))
        end
        state.link_to_previous_state prev_state
        translation.state = state
      end
    end

    class DSDeleteTup < DSNode
      include FOL

      def migrate_state(translation)
        return if @objset1.type_sig.cardinality.empty? or @objset2.type_sig.cardinality.empty?

        state = translation.create_state "post_deleteref_#{@relation.from_class.name}_#{@relation.name}"
        prev_state = translation.state
        context = translation.current_loop_context

        translation.reserve context.make_ps, @relation.to_sort, :r do |ps, r|
          translation.create_formula FOL::ForAll.new(ps, r, FOL::Equiv.new(
            state[ps, r],
            FOL::And.new(
              prev_state[ps, r],
              Not.new(And.new(
                @objset1.resolve_expr(translation, ps, @relation.left_link[r]),
                @objset2.resolve_expr(translation, ps, @relation.right_link[r])
              ))
            )
          ))
        end

        state.link_to_previous_state prev_state
        translation.state = state
      end
    end

    class DSIf < DSNode
      include FOL
      attr_reader :condition_state, :condition_pred

      def migrate_state(translation)
        context = translation.current_loop_context
        post_state = translation.create_state :post_if
        prev_state = translation.state
        @condition_state = prev_state

        @condition_pred = translation.create_predicate 'if_condition', *context.sort_array
        translation.reserve context.make_ps do |ps|
          translation.create_formula FOL::ForAll.new(ps, FOL::Equiv.new(
            @condition_pred[ps],
            @condition.resolve_expr(translation, ps)
          ))
        end
        
        blocks = [@then_block, @else_block]
   
        conditions  = [@condition_pred, @condition_pred.negate]
        pre_states  = [translation.create_state(:pre_then), translation.create_state(:pre_else)]
        
        post_states = []
        
        blocks.length.times do |i|
          translation.state = pre_states[i]
          blocks[i].migrate_state translation
          post_states << translation.state
        end
        
        affected_sorts = 2.times.map{ |i| pre_states[i].sort_difference(prev_state) }.flatten.uniq

        translation.state = @condition_state
        translation.reserve context.make_ps do |ps|
          translation.create_formula FOL::ForAll.new(ps, FOL::IfThenElse.new(
            @condition_pred[ps],
            FOL::And.new(
              affected_sorts.map do |sort|
                translation.reserve sort, :o do |o|
                  [
                    FOL::ForAll.new(o, FOL::Equiv.new(prev_state[ps, o], pre_states[0][ps, o])),
                    FOL::ForAll.new(o, FOL::Equiv.new(post_state[ps, o], post_states[0][ps, o]))
                  ]
                end
              end
            ),
            FOL::And.new(
              affected_sorts.map do |sort|
                translation.reserve sort, :o do |o|
                  [
                    FOL::ForAll.new(o, FOL::Equiv.new(prev_state[ps, o], pre_states[1][ps, o])),
                    FOL::ForAll.new(o, FOL::Equiv.new(post_state[ps, o], post_states[1][ps, o]))
                  ]
                end
              end
            )
          ))
        end

        post_state.link_to_previous_state prev_state
        translation.state = post_state
      end

      def check_branch_condition(translation, ps)
        @condition_pred[ps]
      end
    end

    class DSIfLambdaExpr < DSNode
      def resolve_expr(translation, ps, o = nil)
        actual_state = translation.state
        translation.state = @if.condition_state
        FOL::IfThenElse.new(
          @if.check_branch_condition(translation, ps),
          @then_expr.resolve_expr(translation, ps, o),
          @else_expr.resolve_expr(translation, ps, o)
        )
      ensure
        translation.state = actual_state
      end
    end

    class DSRaise < DSNode
      def migrate_state(translation)
        translation.reserve translation.current_loop_context.make_ps do |ps|
          translation.create_formula ADSL::FOL::ForAll.new(ps, false)
        end
      end
    end

    class DSAssertFormula < DSNode
      def migrate_state(translation)
        translation.reserve translation.current_loop_context.make_ps do |ps|
          translation.create_formula ADSL::FOL::ForAll.new(ps, @formula.resolve_expr(translation, ps))
        end
      end
    end

    class DSForEach < DSNode
      include FOL

      attr_reader :loop_context, :pre_iteration_state, :post_iteration_state, :pre_state, :post_state

      def migrate_state(translation)
        prepare_context translation

        return if @objset.type_sig.cardinality.empty?

        @pre_state = translation.state
        @post_state = translation.create_state :post_for_each
        
        translation.reserve @loop_context.parent.make_ps, @objset.type_sig, :o do |ps, o|
          translation.create_formula ForAll.new(ps, o, Equiv.new(
            And.new(@objset.resolve_expr(translation, ps, o), @pre_state[ps, o]),
            @loop_context.type_pred(ps, o)
          ))
        end

        translation.current_loop_context = @loop_context
        
        @pre_iteration_state = translation.create_state :pre_iteration
        translation.state = @pre_iteration_state
        @block.migrate_state translation
        @post_iteration_state = translation.state

        create_iteration_formulae translation

        translation.current_loop_context = @loop_context.parent

        post_state.link_to_previous_state @pre_state
        translation.state = post_state
      end

      def force_flat(flat)
        if flat
          singleton_class.include DSForEach::Coex
        else
          singleton_class.include DSForEach::Seq
        end
      end

      module Seq
        include FOL

        def prepare_context(translation)
          @loop_context = translation.create_loop_context "for_each_context", false, translation.current_loop_context, @objset.type_sig.to_sort
        end
  
        def create_iteration_formulae(translation)
          context = translation.current_loop_context
          affected_sorts = @post_iteration_state.sort_difference @pre_iteration_state
          translation.reserve context.make_ps, context.sort_array.last, :prev do |ps, prev|
            ps_without_last = ps[0..-2]
            translation.create_formula ForAll.new(ps_without_last,
              Implies.new(
                @loop_context.parent.type_pred(ps_without_last),
                IfThenElse.new(
                  # is the iterator objectset empty?
                  Not.new(Exists.new(ps.last, @loop_context.type_pred(ps))),
                  # if so, pre and post iterations are equivalent
                  translation.states_equivalent_formula(affected_sorts, ps_without_last, @pre_state, ps_without_last, @post_state),
                  # otherwise:
                  ForAll.new(ps.last, And.new(
                    IfThenElse.new(
                      # does there exist a previous context?
                      Exists.new(prev, context.before_pred[ps_without_last, prev, ps.last]),
                      # if so, its post is this one's pre
                      ForAll.new(prev, Implies.new(
                        context.just_before[ps_without_last, prev, ps.last],
                        translation.states_equivalent_formula(affected_sorts,
                          ps_without_last + [prev], @post_iteration_state,
                          ps, @pre_iteration_state
                        ),
                      )),
                      # otherwise, this is the first context
                      translation.states_equivalent_formula(affected_sorts,
                        ps_without_last, @pre_state,
                        ps, @pre_iteration_state
                      )
                    ),
                    Implies.new(
                      And.new(@loop_context.type_pred(ps), Not[Exists[prev, context.just_before[ps_without_last, ps.last, prev]]]),
                      translation.states_equivalent_formula(affected_sorts, ps, @post_iteration_state, ps_without_last, @post_state)
                    )
                  ))
                )
              )
            )
          end
        end
      end
  
      module Coex
        include FOL

        def prepare_context(translation)
          @loop_context = translation.create_loop_context "for_each_context", true, translation.current_loop_context, @objset.type_sig.to_sort
        end
  
        def create_iteration_formulae(translation)
          context = translation.current_loop_context
          affected_sorts = @pre_iteration_state.registered_sorts
          modified_sorts = @post_iteration_state.sort_difference @pre_iteration_state
          translation.reserve context.make_ps do |ps|
            ps_without_last = ps[0..-2]
            translation.create_formula ForAll.new(ps, Implies.new(
              @loop_context.type_pred(ps),
              translation.states_equivalent_formula(affected_sorts, ps_without_last, @pre_state, ps, @pre_iteration_state)
            ))
            translation.create_formula ForAll.new(ps_without_last, IfThenElse.new(
              Not.new(Exists.new(ps.last, @loop_context.type_pred(ps))),
              translation.states_equivalent_formula(modified_sorts, ps_without_last, @pre_state, ps_without_last, @post_state),
              Implies.new(
                @loop_context.parent.type_pred(ps_without_last),
                And.new(modified_sorts.map do |sort|
                  translation.reserve sort, :o do |o|
                    ForAll.new(o, Equiv.new(
                      @post_state[ps_without_last, o],
                      Or.new(
                        And.new(
                          @pre_state[ps_without_last, o],
                          ForAll.new(ps.last, Implies.new(
                            @loop_context.type_pred(ps),
                            @post_iteration_state[ps, o]
                          ))
                        ),
                        And.new(
                          Not.new(@pre_state[ps_without_last, o]),
                          Exists.new(ps.last, And.new(
                            @loop_context.type_pred(ps),
                            @post_iteration_state[ps, o]
                          ))
                        )
                      )
                    ))
                  end
                end)
              )
            ))
          end
        end
      end
    end

    class DSForEachIteratorObjset < DSNode
      def resolve_expr(translation, ps, o = nil)
        return FOL::Equal.new(o, ps[@for_each.loop_context.level-1])
      end
    end

    class DSForEachPreLambdaExpr < DSNode
      def resolve_expr(translation, ps, o = nil)
        raise "Not implemented for flexible arities"
      end
    end

    class DSForEachPostLambdaExpr < DSNode
      def resolve_expr(translation, ps, o = nil)
        raise "Not implemented for flexible arities"
      end
    end

    class DSBlock < DSNode
      def migrate_state(translation)
        @statements.each do |stat|
          stat.migrate_state translation
        end
      end
    end

    class DSAssignment < DSNode
      def migrate_state(translation)
        return if @expr.type_sig.cardinality.empty?
       
        @var.define_variable_pred translation

        context = translation.current_loop_context
        translation.reserve context.make_ps, @expr.type_sig, :o do |ps, o|
          translation.create_formula FOL::ForAll.new(ps, o, FOL::Equiv.new(
            @var.resolve_expr(translation, ps, o),
            FOL::And.new(
              context.type_pred(ps),
              translation.state[ps, o],
              @expr.resolve_expr(translation, ps, o)
            )
          ))
        end
      end
    end

    class DSVariable < DSNode
      def define_variable_pred(translation)
        @loop_context = translation.current_loop_context
        @pred = translation.create_predicate "var_#{@name}", @loop_context.sort_array, type_sig.to_sort
      end

      def resolve_expr(translation, ps, var)
        context = translation.current_loop_context
        raise "Variable #{self} does not have pred defined" if @pred.nil?
        @pred[*ps.first(@loop_context.level), var]
      end
    end

    class DSVariableRead < DSNode
      def resolve_expr(translation, ps, var = nil)
        return false if type_sig.cardinality.empty?
        @variable.resolve_expr(translation, ps, var)
      end
    end

    class DSAllOf < DSNode
      def resolve_expr(translation, ps, var)
        FOL::And.new(translation.state[ps, var], @klass[var])
      end
    end

    class DSDereference < DSNode
      def resolve_expr(translation, ps, var)
        translation.reserve @relation.to_sort, :r do |r|
          return FOL::Exists.new(r, FOL::And.new(
            translation.state[ps, r],
            @objset.resolve_expr(translation, ps, @relation.left_link[r]),
            FOL::Equal.new(@relation.right_link[r], var)
          ))
        end
      end
    end

    class DSSubset < DSNode
      def resolve_expr(translation, ps, var)
        context = translation.current_loop_context
        sort = @objset.type_sig.to_sort
        @pred = translation.create_predicate :objset_subset, context.sort_array, sort

        translation.reserve sort, :o do |o|
          translation.create_formula FOL::ForAll.new(ps, o,
            FOL::Implies.new(@pred[ps, o], @objset.resolve_expr(translation, ps, o))
          )
        end
        @pred[ps, var]
      end
    end

    class DSUnion < DSNode
      def resolve_expr(translation, ps, var)
        FOL::Or.new(@objsets.map{ |objset| objset.resolve_expr translation, ps, var })
      end
    end

    class DSEmptyObjset < DSNode
      def resolve_expr(translation, ps, var)
        false
      end
    end
    
    class DSConstant < DSNode
      def resolve_expr(translation, ps, var = nil)
        case @type_sig
        when TypeSig::BasicType::BOOL
          unless @value.nil?
            @value
          else
            @bool_star_pred = translation.create_predicate('bool_star', translation.current_loop_context.sort_array)
            @bool_star_pred[ps]
          end
        else
          raise "Cannot resolve expr #{self}"
        end
      end
    end

    class DSOr < DSNode
      def resolve_expr(translation, ps, val = nil)
        FOL::Or.new(@subformulae.map{ |sub| sub.resolve_expr translation, ps })
      end
    end
    
    class DSAnd < DSNode
      def resolve_expr(translation, ps, val = nil)
        FOL::And.new(@subformulae.map{ |sub| sub.resolve_expr translation, ps })
      end
    end

    class DSImplies < DSNode
      def resolve_expr(translation, ps, val = nil)
        subformula1 = @subformula1.resolve_expr translation, ps
        subformula2 = @subformula2.resolve_expr translation, ps
        FOL::Implies.new(subformula1, subformula2)
      end
    end
    
    class DSTryOneOf < DSNode
      def resolve_expr(translation, ps, var)
        context = translation.current_loop_context
        sort = @objset.type_sig.to_sort
        @pred = translation.create_predicate :try_one_of, context.sort_array, sort
        translation.create_formula ADSL::DS::FOLTranslation::Util.gen_formula_for_unique_arg(
          @pred, context.level
        )
        translation.reserve context.make_ps, sort, :o do |subps, o|
          co_in_objset = @objset.resolve_expr(translation, subps, o)
          translation.create_formula FOL::ForAll.new(subps, FOL::Equiv.new(
            FOL::Exists.new(o, FOL::And.new(translation.state[subps, o], @pred[subps, o])),
            FOL::Exists.new(o, FOL::And.new(translation.state[subps, o], co_in_objset))
          ))
          translation.create_formula FOL::ForAll.new(subps, o,
            FOL::Implies.new(@pred[subps, o], FOL::And.new(translation.state[subps, o], co_in_objset))
          )
        end
        @pred[ps, var]
      end
    end
    
    class DSOneOf < DSNode
      def resolve_expr(translation, ps, var)
        context = translation.current_loop_context
        sort = @objset.type_sig.to_sort
        @pred = translation.create_predicate :one_of, context.sort_array, sort
        translation.create_formula ADSL::DS::FOLTranslation::Util.gen_formula_for_unique_arg(
          @pred, context.level
        )
        translation.reserve context.make_ps, sort, :o do |subps, o|
          co_in_objset = @objset.resolve_expr(translation, subps, o)
          translation.create_formula FOL::ForAll.new(subps,
            FOL::Exists.new(o, @pred[subps, o])
          )
          translation.create_formula FOL::ForAll.new(subps, o,
            FOL::Implies.new(@pred[subps, o], FOL::And.new(translation.state[subps, o], co_in_objset))
          )
        end
        @pred[ps, var]
      end
    end

    class DSNot < DSNode
      def resolve_expr(translation, ps, val = nil)
        subformula = @subformula.resolve_expr translation, ps
        FOL::Not.new(subformula)
      end
    end

    class DSForAll < DSNode
      def resolve_expr(translation, ps, val = nil)
        translation.reserve @vars.map(&:type_sig) + @vars.map(&:name) do |var_names|
          subformula = @subformula.resolve_expr translation, ps
          constraints = []

          @vars.length.times do |index|
            constraints << @objsets[index].resolve_expr(translation, ps, var_names[index])
          end
          return FOL::ForAll.new(var_names, FOL::Implies.new(
            FOL::And.new(constraints),
            subformula
          ))
        end
      end
    end

    class DSExists < DSNode
      def resolve_expr(translation, ps, val = nil)
        translation.reserve @vars.map(&:type_sig) + @vars.map(&:name) do |var_names|
          subformula = @subformula.nil? ? true : @subformula.resolve_expr(translation, ps)

          constraints = []
          @vars.each_index do |index|
            constraints << @objsets[index].resolve_expr(translation, ps, var_names[index])
          end

          FOL::Exists.new(var_names, FOL::And.new(
            constraints,
            subformula
          ))
        end
      end
    end

    class DSQuantifiedVariable < DSNode
      attr_accessor :name

      def resolve_expr(translation, ps, var)
        FOL::Equal.new(
          var,
          @name
        )
      end

      def resolve_singleton_expr(translation, ps, var)
        @name
      end
    end

    class DSEqual < DSNode
      def resolve_expr(translation, ps)
        shared_type = TypeSig.join(@exprs.map &:type_sig)
        return false if shared_type.is_invalid_type?

        if shared_type.is_basic_type?
          exprs = @exprs.map{ |e| e.resolve_expr translation, ps }
          if shared_type.is_bool_type?
            FOL::Equiv.new(*exprs)
          else
            # other basic types not supported yet
            raise "Basic type #{ shared_type } unsupported"
          end
        else
          translation.reserve @exprs.map(&:type_sig).inject(&:|), :o do |o|
            exprs = @exprs.map{ |e| e.resolve_expr translation, ps, o }
            return FOL::ForAll.new(ps, o, FOL::Implies.new(
              translation.state[ps, o],
              FOL::Equiv.new(exprs)
            ))
          end
        end
      end
    end

    class DSXor < DSNode
      def resolve_expr(translation, ps)
        FOL::Xor.new(*@subformulae.map{ |f| f.resolve_expr translation, ps })
      end
    end

    class DSIn < DSNode
      def resolve_expr(translation, ps, var = nil)
        return true if @objset1.type_sig.cardinality.empty?
        translation.reserve @objset1.type_sig, :o do |o|
          return FOL::ForAll.new(o, FOL::Implies.new(
            FOL::And.new(
              translation.state[ps, o],
              @objset1.type_sig[:o]
            ),
            FOL::Implies.new(
              @objset1.resolve_expr(translation, ps, o),
              @objset2.resolve_expr(translation, ps, o)
            )
          ))
        end
      end
    end
    
    class DSIsEmpty < DSNode
      def resolve_expr(translation, ps, var = nil)
        return true if @objset.type_sig.cardinality.empty?
        translation.reserve @objset.type_sig, :o do |o|
          return FOL::ForAll.new(o, FOL::Implies.new(
            FOL::And.new(
              translation.state[ps, o],
              @objset.type_sig[o]
            ),
            FOL::Not.new(@objset.resolve_expr(translation, ps, o))
          ))
        end
      end
    end
  end
end
