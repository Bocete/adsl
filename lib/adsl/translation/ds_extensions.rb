require 'adsl/translation/ds_translator'
require 'adsl/translation/state'
require 'adsl/translation/util'
require 'adsl/fol/first_order_logic'
require 'adsl/ds/data_store_spec'
require 'adsl/ds/type_sig'

module ADSL
  module DS

    class DSNode
      def replace_var(from, to); end
    end
    
    class DSSpec < DSNode
      def translate_action(action_name, *listed_invariants)
        translation = ADSL::Translation::DSTranslator.new

        if action_name
          action = @actions.select{ |a| a.name == action_name }
          raise ArgumentError, "Action '#{action_name}' not found" if action.empty?
          action = action.first
        end

        translation.classes.concat @classes
        @classes.each do |klass|
          klass.translate(translation)
        end

        relations = @classes.map{ |c| c.relations }.flatten
        relations.select{ |r| r.inverse_of.nil? }.each do |relation|
          relation.translate(translation)
        end
        relations.select{ |r| r.inverse_of }.each do |relation|
          relation.translate(translation)
        end

        action.prepare(translation) if action_name

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
              FOL::Equiv.new(
                klass.precise_type_pred[:o],
                FOL::And.new(
                  klass[:o],
                  FOL::Not.new(*children_rels[klass].map{ |c| c[:o] })
                )
              ),
              FOL::Implies.new(
                klass[:o],
                FOL::And.new(*klass.parents.map{ |p| p[:o] })
              )
            ))
          end
        end

        relations = @classes.map{ |c| c.relations }.flatten
        relation_sorts = relations.map(&:to_sort).uniq

        # enforce cardinality in the first state
        relations.each do |rel|
          rel.enforce_cardinality translation
        end

        action.translate(translation) if action_name
        
        # enforce cardinality in the final state too
        relations.each do |rel|
          rel.enforce_cardinality translation
        end

        @invariants.each do |inv|
          inv.formula.prepare_formula translation
        end

        if action_name
          translation.state = translation.initial_state
          pre_invariants = @invariants.map{ |invariant| invariant.formula.resolve_formula(translation, []) }
        
          listed_invariants = @invariants if listed_invariants.empty?
          translation.state = translation.final_state
          post_invariants = listed_invariants.map{ |invariant| invariant.formula.resolve_formula(translation, []) }
          
          translation.create_conjecture FOL::Implies.new(
            FOL::And.new(pre_invariants),
            FOL::And.new(post_invariants)
          )
        else
          # used to check for contradictions in the model
          invariants_formulae = invariants.map do |invariant|
            formula = invariant.formula
            dummy_state = translation.create_predicate 'always_true', 1
            translation.create_formula FOL::ForAll.new(:o, dummy_state[:o])
            translation.state = dummy_state
            formula.resolve_formula(translation, [])
          end
          translation.create_conjecture FOL::Not.new(FOL::And.new(invariants_formulae))
        end

        return translation
      end
    end
    
    class DSAction < DSNode
      include FOL

      def prepare(translation)
        @args.each do |arg|
          arg.define_predicate translation, arg.type_sig
        end
        @block.prepare translation
      end

      def translate(translation)
        translation.context = translation.root_context
        
        @args.length.times do |i|
          cardinality = @cardinalities[i]
          arg = @args[i]

          translation.reserve arg.type_sig.to_sort, :o do |o|
            translation.create_formula ForAll[o, Implies[
              arg[o],
              And[
                translation.initial_state[o],
                arg.type_sig[o]
              ]
            ]]
            
            translation.create_formula Exists[o, arg[o]] if cardinality[0] > 0
          end
            
          if cardinality[1] == 1
            translation.reserve arg.type_sig, :o1, arg.type_sig, :o2 do |o1, o2|
              translation.create_formula ForAll[o1, o2, Implies[
                And[arg[o1], arg[o2]],
                Equal[o1, o2]
              ]]
            end
          end

        end

        @block.migrate_state translation
        
        translation.final_state = translation.state
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
    end

    class DSRelation < DSNode
      include FOL

      def [](variable)
        @sort[variable]
      end

      def to_sort
        @inverse_of.nil? ? @sort : @inverse_of.sort
      end
      
      def left_link
        @inverse_of.nil? ? @left_link : @inverse_of.right_link
      end
      
      def right_link
        @inverse_of.nil? ? @right_link : @inverse_of.left_link
      end

      def translate(translation)
        if @inverse_of.nil?
          name = "Assoc#{@from_class.name}#{@name.camelize}"
          @sort = translation.create_sort name
          @left_link = translation.create_function @from_class.to_sort, "#{name}_left", @sort
          @right_link = translation.create_function  @to_class.to_sort, "#{name}_right", @sort
          translation.create_formula ForAll[@sort, :t, And[
            @from_class[@left_link[:t]],
            @to_class[@right_link[:t]]
          ]]
          translation.create_formula ForAll[@sort, :t1, @sort, :t2, Implies[
            PairwiseEqual[@left_link[:t1], @left_link[:t2], @right_link[:t1], @right_link[:t2]],
            Equal[:t1, :t2]
          ]]
        end
      end

      def enforce_cardinality(translation)
        translation.reserve @from_class, :o, to_sort, :t, to_sort, :t2 do |o, t, t2|
          if @cardinality[0] > 0
            translation.create_formula ForAll[o, Implies[
              translation.state[o], Exists[t, And[translation.state[t], Equal[o, left_link[t]]]]
            ]]
          end
          if @cardinality[1] == 1
            translation.create_formula ForAll[o, t1, t2, Implies[
              And[
                translation.state[o], translation.state[t], translation.state[t2],
                Equal[o, left_link[:t1], left_link[:t2]]
              ],
              Equal[t1, t2]
            ]]
          end
        end
      end
    end

    class DSCreateObj < DSNode
      include FOL
      attr_reader :context_creation_link, :context

      def prepare(translation)
        @context = translation.context
        translation.create_obj_stmts[@klass] << self
        @context_creation_link = translation.create_function(
          @klass.to_sort,
          "created_#{@klass.name}_in_context", *context.sort_array
        )
      end

      def migrate_state(translation)
        post_state = translation.create_state "post_create_#{@klass.name}"
        prev_state = translation.state
        translation.reserve @context.make_ps do |ps|
          created_by_other_create_stmts = translation.create_obj_stmts[@klass].reject{ |s| s == self }.map do |stmt|
            formula = nil
            translation.reserve stmt.context.make_ps do |other_ps|
              formula = Exists[other_ps, Equal[@context_creation_link[ps], stmt.context_creation_link[other_ps]]]
            end
            formula
          end
          translation.create_formula ForAll[ps, Implies[
            context.type_pred(ps),
            And[
              Not.new(
                created_by_other_create_stmts,
                translation.initial_state[@context_creation_link[ps]]
              ),
              @klass.precise_type_pred[@context_creation_link[ps]]
            ]
          ]]

          translation.reserve @klass.to_sort, :o do |o|
            translation.create_formula ForAll.new(ps, Implies.new(
              @context.type_pred(ps),
              And[
                Not.new(prev_state[ps, @context_creation_link[ps]]),
                ForAll[o, Equiv.new(Or.new(prev_state[ps, o], Equal[o, @context_creation_link[ps]]), post_state[ps, o])]
              ]
            ))
          end

          relevant_from_relations = translation.classes.map{ |c| c.relations }.flatten.select{ |r| r.from_class >= @klass }
          relevant_to_relations   = translation.classes.map{ |c| c.relations }.flatten.select{ |r| r.to_class >= @klass }
          
          translation.create_formula ForAll.new(ps, Implies.new(
            @context.type_pred(ps),
            And.new(
              relevant_from_relations.map do |rel|
                translation.reserve rel, :r do |r|
                  Not.new(Exists.new r, post_state[rel.left_link[r]])
                end
              end,
              relevant_to_relations.map do |rel|
                translation.reserve rel, :r do |r|
                  Not.new(Exists.new r, post_state[rel.right_link[r]])
                end
              end
            )
          ))
        end

        post_state.link_to_previous_state prev_state
        translation.state = post_state
      end
    end

    class DSCreateObjset < DSNode
      include FOL
      
      def prepare_expr(translation); end

      def resolve_expr(translation, ps, var)
        Equal[@createobj.context_creation_link[ps], var]
      end
    end

    class DSDeleteObj < DSNode
      include FOL
      attr_accessor :context_deletion_link

      def prepare(translation)
        @objset.prepare_expr translation
      end

      def migrate_state(translation)
        return if @objset.type_sig.unknown_sig?
        state = translation.create_state "post_delete_#{@objset.type_sig.underscore}"
        sort = @objset.type_sig.to_sort
        prev_state = translation.state
        context = translation.context
        
        translation.reserve context.make_ps, sort, :o do |ps, o|
          translation.create_formula _for_all(ps, o,
            _if_then_else_eq(_and(@objset.resolve_expr(translation, ps, o), prev_state[ps, o]),
              _and(prev_state[ps, o], _not(state[ps, o])),
              _equiv(prev_state[ps, o], state[ps, o])
            )
          )
        end

        state.link_to_previous_state prev_state
        translation.state = state
      end
    end

    class DSCreateTup < DSNode
      include FOL
     
      def prepare(translation)
        @objset1.prepare_expr translation
        @objset2.prepare_expr translation
      end

      def migrate_state(translation)
        return if @objset1.type_sig.card_none? or @objset2.type_sig.card_none?
        sort1 = @objset1.to_sort
        sort2 = @objset2.to_sort
        rel_sort = @relation.to_sort

        state = translation.create_state "post_create_#{@relation.from_class.name}_#{@relation.name}"
        prev_state = translation.state
        context = translation.context

        translation.reserve context.make_ps, rel_sort, :r, sort1, :o1, sort2, :o2 do |ps, r, o1, o2|
          objset1 = @objset1.resolve_expr(translation, ps, o1)
          objset2 = @objset2.resolve_expr(translation, ps, o2)
          translation.create_formula FOL::ForAll.new(ps, r, FOL::Implies.new(
            context.type_pred(ps),
            FOL::Equiv.new(
              state[ps, r],
              FOL::Or.new(
                prev_state[ps, r],
                FOL::Exists.new(o1, o2, FOL::And.new(
                  prev_state[ps, o1], prev_state[ps, o2],
                  @relation.left_link[r, o1], @relation.right_link[r, o2],
                  objset1, objset2
                ))
              )
            )
          ))
          translation.create_formula FOL::ForAll.new(ps, o1, o2, FOL::Implies.new(
            FOL::And.new(prev_state[ps, o1], prev_state[ps, o2], objset1, objset2),
            FOL::Exists.new(r, FOL::And.new(state[ps, r], @relation.left_link[r, o1], @relation.right_link[r, o2]))
          ))
        end
        state.link_to_previous_state prev_state
        translation.state = state
      end
    end

    class DSDeleteTup < DSNode
      include FOL

      def prepare(translation)
        @objset1.prepare_expr translation
        @objset2.prepare_expr translation
      end

      def migrate_state(translation)
        return if @objset1.type_sig.card_none? or @objset2.type_sig.card_none?
        sort1 = @objset1.to_sort
        sort2 = @objset2.to_sort
        rel_sort = @relation.to_sort

        state = translation.create_state "post_deleteref_#{@relation.from_class.name}_#{@relation.name}"
        prev_state = translation.state
        context = translation.context

        translation.reserve context.make_ps, rel_sort, :r, sort1, :o1, sort2, :o2 do |ps, r, o1, o2|
          objset1 = @objset1.resolve_expr(translation, ps, o1)
          objset2 = @objset2.resolve_expr(translation, ps, o2)
          translation.create_formula FOL::ForAll.new(ps, r, FOL::Equiv.new(
            state[ps, r],
            FOL::And.new(
              prev_state[ps, r],
              FOL::ForAll.new(o1, o2, FOL::Not.new(FOL::And.new(
                objset1, objset2,
                prev_state[ps, o1], prev_state[ps, o2],
                @relation.left_link[r, o1], @relation.right_link[r, o2]
              )))
            )
          ))
        end

        translation.state = state
      end
    end

    class DSEither < DSNode
      include FOL
      attr_reader :resolution_link, :res_sort, :is_trues
      
      def prepare(translation)
        context = translation.context
        @res_sort = translation.create_sort :resolution_sort
        @resolution_link = translation.create_predicate res_sort, :resolution_link, context.sort_array
        @is_trues = []
        @blocks.length.times do |i|
          is_trues << translation.create_predicate("either_resolution_#{i}_is_true", res_sort)
        end
        @blocks.each do |block|
          block.prepare(translation)
        end
      end

      def migrate_state(translation)
        post_state = translation.create_state :post_either
        prev_state = translation.state
        context = translation.context

        pre_states = []
        post_states = []
        @blocks.each_index do |block, i|
          pre_state = translation.create_state(:pre_of_either)
          pre_states << pre_state
          translation.state = pre_state
          block.migrate_state translation
          post_states << translation.state
        end

        translation.create_formula FOL::ForAll.new(@res_sort, :r, FOL::Implies.new(
          FOL::OneOf.new(@is_trues.map{ |pred| pred[:r] })
        ))

        affected_sorts = @blocks.each_index{ |i| pre_states[i].sort_difference(post_states[i]) }.flatten.uniq

        translation.reserve_names context.p_names do |resolution|
          translation.create_formula FOL::ForAll.new(ps, FOL::Implies.new(
            translation.context.type_pred(ps),
            FOL::And.new(@blocks.each_index do |i|
              FOL::Implies.new(
                @is_trues[i][@resolution_link[ps]],
                transition_to_the_outside = FOL::And.new(
                  affected_sorts.map do |sort|
                    translation.reserve sort, :o do |o|
                      [
                        FOL::ForAll.new(sort, o, FOL::Equiv.new(prev_state[ps, o], pre_states[i][ps, o])),
                        FOL::ForAll.new(sort, o, FOL::Equiv.new(post_state[ps, o], post_states[i][ps, o]))
                      ]
                    end
                  end
                )
              )
            end)
          ))
        end

        post_state.link_to_previous_state prev_state
        translation.state = post_state
      end
    end

    class DSEitherLambdaExpr < DSNode
      def prepare_expr(translation); end

      def resolve_expr(translation, ps, o)
        FOL::Or.new(@either.blocks.each_index.map do |i|
          FOL::Implies.new(
            @either.is_trues[i][@either.resolution_link[ps]],
            @exprs[i].resolve_expr(translation, ps, o)
          )
        end)
      end
    end

    class DSIf < DSNode
      include FOL
      attr_reader :condition_state
      
      def prepare(translation)
        @condition.prepare_formula(translation)
        @then_block.prepare(translation)
        @else_block.prepare(translation)
      end

      def migrate_state(translation)
        post_state = translation.create_state :post_if
        prev_state = translation.state
        @condition_state = prev_state
        context = translation.context
        blocks = [@then_block, @else_block]
      
        pre_states  = [translation.create_state(:pre_then), translation.create_state(:pre_else)]
        post_states = []
        
        blocks.length.times do |i|
          translation.state = pre_states[i]
          blocks[i].migrate_state translation
          post_states << translation.state
        end
        
        affected_sorts = 2.times.map{ |i| pre_states[i].sort_difference(post_states[i]) }.flatten.uniq

        translation.state = @condition_state
        translation.reserve context.make_ps do |ps|
          translation.create_formula FOL::ForAll.new(ps, FOL::IfThenElse.new(
            @condition.resolve_formula(translation, ps),
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
                    FOL::ForAll.new(o, FOL::Equiv.new(post_state[ps, o], post_states[0][ps, o]))
                  ]
                end
              end
            )
          ))
        end

        post_state.link_to_previous_state prev_state
        translation.state = post_state
      end
    end

    class DSIfLambdaExpr < DSNode
      def prepare_expr(translation); end

      def resolve_expr(translation, ps, o)
        actual_state = translation.state
        translation.state = @if.condition_state
        FOL::IfThenElse.new(
          @if.condition.resolve_formula(translation, ps),
          @then_expr.resolve_expr(translation, ps, o),
          @else_expr.resolve_expr(translation, ps, o)
        )
      ensure
        translation.state = actual_state
      end
    end


    class DSForEachCommon < DSNode
      include FOL

      attr_reader :context, :pre_iteration_state, :post_iteration_state, :pre_state, :post_state

      def prepare_with_context(translation, flat_context)
        @context = translation.create_context "for_each_context", flat_context, translation.context, @objset.to_sort
        @objset.prepare_expr translation
        translation.context = @context
        @block.prepare translation
        translation.context = @context.parent
      end

      def migrate_state(translation)
        return if @objset.type_sig.card_none?

        @pre_state = translation.state
        @post_state = translation.create_state :post_for_each
        
        translation.reserve @context.parent.make_ps, @objset.to_sort, :o do |ps, o|
          translation.create_formula ForAll.new(ps, o, Equiv.new(
            And.new(@objset.resolve_expr(translation, ps, o), @pre_state[ps, o]),
            @context.type_pred(ps, o)
          ))
        end

        translation.context = @context
        
        @pre_iteration_state = translation.create_state :pre_iteration
        translation.state = @pre_iteration_state
        @block.migrate_state translation
        @post_iteration_state = translation.state

        create_iteration_formulae translation

        translation.context = @context.parent
        translation.state = post_state
      end
    end

    class DSForEachIteratorObjset < DSNode
      def prepare_expr(translation); end

      def resolve_expr(translation, ps, o)
        return Equal.new(o, ps[@for_each.context.level-1])
      end
    end

    class DSForEachPreLambdaExpr < DSNode
      def prepare_expr(translation); end

      def resolve_expr(translation, ps, o)
        raise "Not implemented for flexible arities"
        translation.reserve_names :parent, :prev_context do |parent, prev_context|
          return ForAll.new(parent, Implies.new(@context.parent_of_pred[parent, :c],
            IfThenElseEq.new(
              @context.first[parent, c],
              @before_var[c, o],
              Exists.new( prev_context, And.new(
                @context.just_before[prev_context, c],
                @inside_var[prev_context, o]
              ))
            )
          ))
        end
      end
    end

    class DSForEach < DSForEachCommon
      def prepare(translation)
        prepare_with_context(translation, false)
      end

      def create_iteration_formulae(translation)
        context = translation.context
        affected_sorts = @post_state.sort_difference @pre_state
        translation.reserve context.make_ps, context.sort_array.last, :prev do |ps|
          ps_without_last = ps[0..-2]
          translation.create_formula ForAll.new(ps_without_last,
            Implies.new(
              @context.parent.type_pred(ps_without_last),
              IfThenElse.new(
                # is the iterator objectset empty?
                Not.new(Exists.new(ps.last, @context.type_pred(ps))),
                # if so, pre and post iterations are equivalent
                translation.states_equivalent_formula(affected_sorts, ps_without_last, @pre_state, ps_without_last, @post_state),
                # otherwise:
                And.new(
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
                      ps, @pre_iteration_state)
                    )
                  ),
                  Implies.new(
                    And.new(@context.type_pred(ps), Not[Exists[prev, context.just_before[ps_without_last, ps.last, prev]]]),
                    ForAll.new(o, Equiv.new(@post_iteration_state[ps, o], @post_state[ps_without_last, o]))
                  )
                )
              )
            )
          ))
        end
      end
    end

    class DSFlatForEach < DSForEachCommon
      def prepare(translation)
        prepare_with_context(translation, true)
      end

      def create_iteration_formulae(translation)
        context = translation.context
        translation.reserve_names context.p_names, :o do |ps, o|
          ps_without_last = ps.first(ps.length - 1)
          translation.create_formula _for_all(ps, _implies(
            @context.type_pred(ps),
            _for_all(o, _equiv(@pre_state[ps_without_last, o], @pre_iteration_state[ps, o]))
          ))
          translation.create_formula _for_all(ps_without_last, _if_then_else(
            _not(_exists(ps.last, @context.type_pred(ps))),
            _for_all(o, _equiv(@pre_state[ps_without_last, o], @post_state[ps_without_last, o])),
            _implies(
              @context.parent.type_pred(ps_without_last),
              _for_all(o, _equiv(
                @post_state[ps_without_last, o],
                _or(
                  _and(
                    @pre_state[ps_without_last, o],
                    _for_all(ps.last, _implies(
                      @context.type_pred(ps),
                      @post_iteration_state[ps, o]
                    ))
                  ),
                  _and(
                    _not(@pre_state[ps_without_last, o]),
                    _exists(ps.last, @post_iteration_state[ps, o])
                  )
                )
              ))
            )
          ))
        end
      end
    end

    class DSBlock < DSNode
      def prepare(translation)
        @statements.each do |stat|
          stat.prepare translation
        end
      end

      def migrate_state(translation)
        @statements.each do |stat|
          stat.migrate_state translation
        end
      end
    end

    class DSAssignment < DSNode
      def prepare(translation)
        @expr.prepare_expr translation
        @var.define_predicate translation, @expr.type_sig
      end

      def migrate_state(translation)
        context = translation.context
        unless @expr.type_sig.unknown_sig?
          translation.reserve context.make_ps, @expr.type_sig, :o do |ps, o|
            translation.create_formula FOL::ForAll.new(ps, o, FOL::Equiv.new(
              var.resolve_expr(translation, ps, o),
              FOL::And.new(
                translation.state[ps, o],
                @expr.resolve_expr(translation, ps, o)
              )
            ))
          end
        end
      end
    end

    class DSVariable < DSNode
      attr_accessor :context, :pred
      
      # The predicate is not defined in prepare_action
      # as we want the predicate to be defined only when assigning to the variable
      # not when using it
      # @pred ||= would not work because it makes the translation non-reusable
      def prepare_expr(translation)
      end

      def define_predicate(translation, type_sig)
        @context = translation.context
        @type_sig = type_sig
        @pred = translation.create_predicate "var_#{@name}", context.sort_array, type_sig.to_sort unless type_sig.unknown_sig?
      end

      def resolve_expr(translation, ps, var)
        @type_sig.unknown_sig? ? false : @pred[ps.first(@context.level), var]
      end

      def [](*args)
        @type_sig.unknown_sig? ? false : @pred[args]
      end
    end

    class DSAllOf < DSNode
      def prepare_expr(translation); end
      
      def resolve_expr(translation, ps, var)
        FOL::And.new(translation.state[ps, var], @klass[var])
      end
    end

    class DSDereference < DSNode
      def prepare_expr(translation)
        @objset.prepare_expr translation
      end

      def resolve_expr(translation, ps, var)
        translation.reserve_names :temp, :r do |temp, r|
          return FOL::Exists.new(temp, r, FOL::And.new(
            translation.state[ps, r],
            translation.state[ps, temp],
            @objset.resolve_expr(translation, ps, temp),
            @relation.left_link[r, temp],
            @relation.right_link[r, var]
          ))
        end
      end
    end

    class DSSubset < DSNode
      def prepare_expr(translation)
        @objset.prepare_expr translation
      end

      def resolve_expr(translation, ps, var)
        context = translation.context
        sort = @objset.to_sort
        pred = translation.create_predicate :subset, context.sort_array, sort
        translation.reserve context.make_ps do |ps|
          translation.create_formula FOL::ForAll.new(ps, sort, :o,
            FOL::Implies.new(pred[ps, :o], @objset.resolve_expr(translation, ps, :o))
          )
        end
        return pred[ps, var]
      end
    end

    class DSUnion < DSNode
      def prepare_expr(translation)
        @objsets.each{ |objset| objset.prepare_expr translation }
      end

      def resolve_expr(translation, ps, var)
        FOL::Or.new(@objsets.map{ |objset| objset.resolve_expr translation, ps, var })
      end
    end

    class DSPickOneObjset < DSNode
      def prepare_expr(translation)
        context = translation.context
        @objsets.each{ |objset| objset.prepare_expr translation }
        
        @predicates = @objsets.map do |objset|
          translation.create_predicate :one_of_subset, context.sort_array, @objset.to_sort
        end
        translation.reserve context.make_ps do |ps|
          translation.create_formula FOL::ForAll.new(ps,
            FOL::OneOf.new(@predicates.map{ |p| p[ps] })
          )
        end
      end

      def resolve_expr(translation, ps, var)
        context = translation.context
        subformulae = []
        @objsets.length.times do |index|
          subformulae << FOL::And.new(@predicates[index][ps], @objsets[index].resolve_expr(translation, ps, var))
        end
        FOL::Or.new(subformulae)
      end
    end

    class DSEmptyObjset < DSNode
      def prepare_expr(translation)
      end

      def resolve_expr(translation, ps, var)
        false
      end
    end

    class DSOr < DSNode
      def prepare_formula(translation)
        @subformulae.each do |sub|
          sub.prepare_formula translation
        end
      end

      def resolve_formula(translation, ps)
        FOL::Or.new(@subformulae.map{ |sub| sub.resolve_formula translation, ps })
      end
    end
    
    class DSAnd < DSNode
      def prepare_formula(translation)
        @subformulae.each do |sub|
          sub.prepare_formula translation
        end
      end
      
      def resolve_formula(translation, ps)
        FOL::And.new(@subformulae.map{ |sub| sub.resolve_formula translation, ps })
      end
    end

    class DSEquiv < DSNode
      def prepare_formula(translation)
        @subformulae.each do |sub|
          sub.prepare_formula translation
        end
      end
      
      def resolve_formula(translation, ps)
        FOL::Equiv.new(@subformulae.map{ |sub| sub.resolve_formula translation, ps })
      end
    end
    
    class DSImplies < DSNode
      def prepare_formula(translation)
        @subformula1.prepare_formula translation
        @subformula2.prepare_formula translation
      end
      
      def resolve_formula(translation, ps)
        subformula1 = @subformula1.resolve_formula translation, ps
        subformula2 = @subformula2.resolve_formula translation, ps
        FOL::Implies.new(subformula1, subformula2)
      end
    end
    
    class DSTryOneOf < DSNode
      def prepare_expr(translation)
        @objset.prepare_expr translation
      end

      def resolve_expr(translation, ps, var)
        context = translation.context
        sort = @objset.to_sort
        pred = translation.create_predicate :try_one_of, context.sort_array, sort
        translation.create_formula ADSL::Translation::Util.gen_formula_for_unique_arg(
          pred, context.level
        )
        translation.reserve context.make_ps, sort, :o do |subps, o|
          co_in_objset = @objset.resolve_expr(translation, subps, o)
          translation.create_formula FOL::ForAll.new(subps, FOL::Equiv.new(
            FOL::Exists.new(o, FOL::And.new(translation.state[subps, o], pred[subps, o])),
            FOL::Exists.new(o, FOL::And.new(translation.state[subps, o], co_in_objset))
          ))
          translation.create_formula FOL::ForAll.new(subps, o,
            FOL::Implies.new(pred[subps, o], FOL::And.new(translation.state[subps, o], co_in_objset))
          )
        end
        pred[ps, var]
      end
    end
    
    class DSOneOf < DSNode
      def prepare_expr(translation)
        @objset.prepare_expr translation
      end

      def resolve_expr(translation, ps, var)
        context = translation.context
        sort = @objset.type_sig.to_sort
        pred = translation.create_predicate :one_of, context.sort_array, sort
        translation.create_formula ADSL::Translation::Util.gen_formula_for_unique_arg(
          pred, context.level
        )
        translation.reserve context.make_ps, sort, :o do |subps, o|
          co_in_objset = @objset.resolve_expr(translation, subps, o)
          translation.create_formula FOL::ForAll.new(subps,
            FOL::Exists.new(o, pred[subps, o])
          )
          translation.create_formula FOL::ForAll.new(subps, o,
            FOL::Implies.new(pred[subps, o], FOL::And.new(translation.state[subps, o], co_in_objset))
          )
        end
        pred[ps, var]
      end
    end

    class DSNot < DSNode
      def prepare_formula(translation)
        @subformula.prepare_formula translation
      end

      def resolve_formula(translation, ps)
        subformula = @subformula.resolve_formula translation, ps
        FOL::Not.new(subformula)
      end
    end
    
    class DSBoolean < DSNode
      def prepare_formula(translation)
      end

      def resolve_formula(translation, ps)
        @bool_value
      end
    end

    class DSForAll < DSNode
      def prepare_formula(translation)
        @subformula.prepare_formula translation
      end

      def resolve_formula(translation, ps)
        subformula = @subformula.resolve_formula translation, ps
        constraints = []
        translation.reserve @vars.map(&:type_sig) + @vars.map(&:name) do |var_names|
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
      def prepare_formula(translation)
        @subformula.prepare_formula translation unless @subformula.nil?
      end
      
      def resolve_formula(translation, ps)
        subformula = @subformula.nil? ? true : @subformula.resolve_formula(translation, ps)
        constraints = []
        translation.reserve @vars.map(&:type_sig) + @vars.map(&:name) do |var_names|
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
 
      def prepare_expr(translation)
      end

      def resolve_expr(translation, ps, var)
        FOL::Equal.new(
          var,
          @name
        )
      end
    end

    class DSEqual < DSNode
      def prepare_formula(translation)
        @exprs.each do |expr|
          expr.prepare_expr translation
        end
      end

      def resolve_formula(translation, ps)
        translation.reserve @exprs.map(&:type_sig).inject(&:union), :o do |o|
          exprs = @exprs.map{ |e| e.resolve_expr translation, ps, o }
          return FOL::ForAll.new(ps, o, FOL::Implies.new(
            translation.state[ps, o],
            FOL::Equiv.new(exprs)
          ))
        end
      end
    end

    class DSIn < DSNode
      def prepare_formula(translation)
        @objset1.prepare_expr translation
        @objset2.prepare_expr translation
      end

      def resolve_formula(translation, ps)
        return true if @objset1.type_sig.card_none?
        translation.reserve @objset1.type_sig, :o do |o|
          return FOL::ForAll.new(o, FOL::Implies.new(
            translation.state[ps, o],
            FOL::Implies.new(
              @objset1.resolve_expr(translation, ps, o),
              @objset2.resolve_expr(translation, ps, o)
            )
          ))
        end
      end
    end
    
    class DSIsEmpty < DSNode
      def prepare_formula(translation)
        @objset.prepare_expr translation
      end

      def resolve_formula(translation, ps)
        return true if @objset.type_sig.card_none?
        translation.reserve @objset.type_sig, :o do |o|
          return FOL::ForAll.new(o, FOL::Implies.new(
            translation.state[ps, o],
            FOL::Not.new(@objset.resolve_expr(translation, ps, o))
          ))
        end
      end
    end
  end
end
