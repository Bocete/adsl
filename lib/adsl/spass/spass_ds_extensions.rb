require 'adsl/fol/first_order_logic'
require 'adsl/spass/spass_translator'

module ADSL
  module DS
    class DSNode
      def replace_var(from, to); end
    end
    
    class DSSpec < DSNode
      def translate_action(action_name, *listed_invariants)
        translation = ADSL::Spass::SpassTranslator::Translation.new

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

        translation.create_formula FOL::ForAll.new(:o, FOL::Equiv.new(
          translation.is_object[:o],
          FOL::Or.new(@classes.map{ |c| c[:o] })
        ))
        @classes.group_by{ |klass| klass.parent }.each do |common_parent, children|
          unless common_parent.nil?
            translation.create_formula FOL::ForAll.new(:o, FOL::Implies.new(
              FOL::Or.new(children.map{ |c| c[:o] }),
              common_parent[:o]
            ))
          end
          if children.length > 1
            children.each do |child|
              translation.create_formula FOL::ForAll.new(:o, FOL::Implies.new(
                child[:o],
                FOL::Not.new(children.select{ |c| c != child}.map{ |c| c[:o] })
              ))
            end
          end
        end

        relations = @classes.map{ |c| c.relations }.flatten.map{ |rel| rel.type_pred }.uniq
        translation.create_formula FOL::ForAll.new(:o, FOL::Equiv.new(
          translation.is_tuple[:o],
          FOL::Or.new(relations.map{ |r| r[:o] })
        ))
        if relations.length > 1
          relations.each do |relation|
            translation.create_formula FOL::ForAll.new(:o, FOL::Implies.new(
              relation[:o],
              FOL::Not.new(relations.select{ |c| c != relation}.map{ |c| c[:o] })
            ))
          end
        end

        translation.create_formula FOL::ForAll.new(:o, FOL::OneOf.new(
          translation.is_object[:o],
          translation.is_tuple[:o],
          translation.is_either_resolution[:o]
        ))
        translation.create_formula FOL::ForAll.new(:o, FOL::Implies.new(
          translation.existed_initially[:o],
          FOL::Or.new(translation.is_object[:o], translation.is_tuple[:o])
        ))
        translation.create_formula FOL::ForAll.new(:o, FOL::Equiv.new(
          translation.existed_initially[:o], 
          translation.prev_state[:o]
        ))

        action.translate(translation) if action_name

        if action_name
          translation.invariant_state = translation.existed_initially
          pre_invariants = @invariants.map{ |invariant| invariant.formula.resolve_invariant_formula(translation) }
        
          listed_invariants = @invariants if listed_invariants.empty?
          translation.invariant_state = translation.exists_finally
          post_invariants = listed_invariants.map{ |invariant| invariant.formula.resolve_invariant_formula(translation) }
          
          translation.create_conjecture FOL::Implies.new(
            FOL::And.new(pre_invariants),
            FOL::And.new(post_invariants)
          ).resolve_spass
        else
          # used to check for contradictions in the model
          invariants_formulae = invariants.map do |invariant|
            formula = invariant.formula
            dummy_state = translation.create_predicate 'always_true', 1
            translation.create_formula FOL::ForAll.new(:o, dummy_state[:o])
            translation.invariant_state = dummy_state
            formula.resolve_invariant_formula(translation)
          end
          translation.create_conjecture FOL::Not.new(FOL::And.new(invariants_formulae))
        end

        return translation.to_spass_string
      end
    end

    class DSAction < DSNode
      include FOL

      def prepare(translation)
        @args.each do |arg|
          arg.define_predicate translation
        end
        @block.prepare translation
      end

      def translate(translation)
        translation.context = translation.root_context
        
        @args.length.times do |i|
          cardinality = @cardinalities[i]
          arg = @args[i]

          translation.create_formula _for_all(:o, _implies(
            arg[:o],
            _and(translation.existed_initially[:o], arg.type[:o])
          ))

          translation.create_formula _exists(:o, arg[:o]) if cardinality[0] > 0
          if cardinality[1] == 1
            translation.create_formula _for_all(:o1, :o2, _implies(
              _and(arg[:o1], arg[:o2]),
              _equal(:o1, :o2)
            ))
          end
        end

        @block.migrate_state_spass translation
        
        translation.create_formula _for_all(:o, _equiv(
          translation.exists_finally[:o],
          translation.prev_state[:o]
        ))
      end
    end

    class DSClass < DSNode
      def [](variable)
        @type_pred[variable]
      end

      def translate(translation)
        @type_pred = translation.create_predicate "of_#{@name}_type", 1
      end
    end

    class DSRelation < DSNode
      include FOL
      attr_reader :type_pred, :left_link, :right_link

      def [](variable)
        @type_pred[variable]
      end

      def translate(translation)
        if @inverse_of
          @type_pred = @inverse_of.type_pred
          @left_link = @inverse_of.right_link
          @right_link = @inverse_of.left_link
        else
          @type_pred = translation.create_predicate "of_#{@from_class.name}_#{@name}_type", 1
          @left_link = translation.create_predicate "left_link_#{@from_class.name}_#{@name}", 2
          @right_link = translation.create_predicate "right_link_#{@from_class.name}_#{@name}", 2
          translation.create_formula _for_all(:t, :o, _implies(@left_link[:t, :o], _and(@from_class[:o], @type_pred[:t])))
          translation.create_formula _for_all(:t, :o, _implies(@right_link[:t, :o], _and(@to_class[:o], @type_pred[:t])))
          translation.create_formula _for_all(:t, :o1, :o2, _and(
            _implies(_and(@left_link[:t, :o1], @left_link[:t, :o2]), _equal(:o1, :o2)),
            _implies(_and(@right_link[:t, :o1], @right_link[:t, :o2]), _equal(:o1, :o2))
          ))
          translation.create_formula _for_all(:t, _implies(
            @type_pred[:t],
            _exists(:o1, :o2, _and(@left_link[:t, :o1], @right_link[:t, :o2]))
          ))
        end

        if @cardinality[0] > 0
          translation.create_formula _for_all(:o, _implies(@from_class[:o], _exists(:t, @left_link[:t, :o])))
        end
        if @cardinality[1] == 1
          translation.create_formula _for_all(:o, :t1, :t2, _implies(
            _and(@left_link[:t1, :o], @left_link[:t2, :o]),
            _equal(:t1, :t2)
          ))  
        end
      end
    end

    class DSCreateObj < DSNode
      include FOL
      attr_reader :context_creation_link, :context

      def prepare(translation)
        @context = translation.context
        translation.create_obj_stmts[@klass] << self
        @context_creation_link = translation.create_predicate "created_#{@klass.name}_in_context", context.level + 1
      end

      def migrate_state_spass(translation)
        state = translation.create_state "post_create_#{@klass.name}"
        prev_state = translation.prev_state
        translation.gen_formula_for_unique_arg(@context_creation_link, (0..@context.level-1), @context.level)
        translation.reserve_names @context.p_names, :o do |ps, o|
          created_by_other_create_stmts = translation.create_obj_stmts[@klass].select{|s| s != self}.map do |stmt|
            formula = nil
            translation.reserve_names stmt.context.p_names do |other_ps|
              formula = _exists(other_ps, stmt.context_creation_link[other_ps, o])
            end
            formula
          end
          created_by_other_create_stmts << translation.existed_initially[o]
          child_classes = translation.classes.select{ |c| c.parent == @klass }
          not_of_child_types = child_classes.empty? ? true : _and(child_classes.map{ |c| _not(c[o]) })
          translation.create_formula _for_all(ps, o, _implies(
            @context_creation_link[ps, o], _and(
              context.type_pred(ps),
              _not(created_by_other_create_stmts),
              @klass[o],
              not_of_child_types
            )
          ))
          translation.create_formula _for_all(ps, _implies(@context.type_pred(ps), _exists(o,
            @context_creation_link[ps, o]
          )))
          translation.create_formula _for_all(ps, o,
            _if_then_else_eq(
              @context_creation_link[ps, o],
              _and(_not(prev_state[ps, o]), state[ps, o]),
              _equiv(prev_state[ps, o], state[ps, o])
            )
          )

          relevant_from_relations = translation.classes.map{ |c| c.relations }.flatten.select{ |r| r.from_class == @klass }
          relevant_to_relations = translation.classes.map{ |c| c.relations }.flatten.select{ |r| r.to_class == @klass }
          translation.reserve_names :r do |r|
            translation.create_formula _for_all(ps, o, _implies(
              @context_creation_link[ps, o],
              _for_all(r, _not(_and(
                state[ps, r],
                _or(
                  relevant_from_relations.map{ |rel| rel.left_link[r, o] },
                  relevant_to_relations.map{ |rel| rel.right_link[r, o] }
                )
              )))
            ))
          end
        end

        translation.prev_state = state
      end
    end

    class DSCreateObjset < DSNode
      include FOL
      
      def prepare_action(translation); end

      def resolve_action_objset(translation, ps, var)
        return @createobj.context_creation_link[ps, var]
      end
    end

    class DSDeleteObj < DSNode
      include FOL
      attr_accessor :context_deletion_link

      def prepare(translation)
        @objset.prepare_action translation
      end

      def migrate_state_spass(translation)
        state = translation.create_state "post_delete_#{@objset.type.name}"
        prev_state = translation.prev_state
        context = translation.context
        
        translation.reserve_names context.p_names, :o do |ps, o|
          translation.create_formula _for_all(ps, o,
            _if_then_else_eq(_and(@objset.resolve_action_objset(translation, ps, o), prev_state[ps, o]),
              _and(prev_state[ps, o], _not(state[ps, o])),
              _equiv(prev_state[ps, o], state[ps, o])
            )
          )
        end

        translation.prev_state = state
      end
    end

    class DSCreateTup < DSNode
      include FOL
     
      def prepare(translation)
        @objset1.prepare_action translation
        @objset2.prepare_action translation
      end

      def migrate_state_spass(translation)
        return if @objset1.type.nil? or @objset2.type.nil?

        state = translation.create_state "post_create_#{@relation.from_class.name}_#{@relation.name}"
        prev_state = translation.prev_state
        context = translation.context

        translation.reserve_names context.p_names, :r, :o1, :o2 do |ps, r, o1, o2|
          objset1 = @objset1.resolve_action_objset(translation, ps, o1)
          objset2 = @objset2.resolve_action_objset(translation, ps, o2)
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
        translation.prev_state = state
      end
    end

    class DSDeleteTup < DSNode
      include FOL

      def prepare(translation)
        @objset1.prepare_action translation
        @objset2.prepare_action translation
      end

      def migrate_state_spass(translation)
        return if @objset1.type.nil? or @objset2.type.nil?

        state = translation.create_state "post_deleteref_#{@relation.from_class.name}_#{@relation.name}"
        prev_state = translation.prev_state
        context = translation.context

        translation.reserve_names context.p_names, :r, :o1, :o2 do |ps, r, o1, o2|
          objset1 = @objset1.resolve_action_objset(translation, ps, o1)
          objset2 = @objset2.resolve_action_objset(translation, ps, o2)
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

        translation.prev_state = state
      end
    end

    class DSEither < DSNode
      include FOL
      attr_reader :resolution_link, :is_trues
      
      def prepare(translation)
        context = translation.context
        @resolution_link = translation.create_predicate :resolution_link, context.level+1
        translation.reserve_names context.p_names, :r do |ps, r|
          translation.gen_formula_for_unique_arg(@resolution_link, (0..ps.length-1), ps.length)
          translation.create_formula _for_all(ps, r, _implies(@resolution_link[ps, r], _and(
            translation.context.type_pred(ps),
            translation.is_either_resolution[r]
          )))
        end
        @is_trues = []
        @blocks.length.times do |i|
          is_trues << translation.create_predicate("either_resolution_#{i}_is_true", 1)
        end
        @blocks.each do |block|
          block.prepare(translation)
        end
      end

      def migrate_state_spass(translation)
        post_state = translation.create_state :post_either
        prev_state = translation.prev_state
        context = translation.context

        pre_states = []
        post_states = []
        @blocks.length.times do |i|
          pre_states << translation.create_state(:pre_of_either)
        end
        translation.create_formula FOL::ForAll.new(:r, FOL::Implies.new(
          translation.is_either_resolution[:r],
          FOL::OneOf.new(is_trues.map{ |pred| pred[:r] })
        ))

        translation.reserve_names context.p_names, :resolution, :o do |ps, resolution, o|
          translation.create_formula FOL::ForAll.new(ps, FOL::Implies.new(
            translation.context.type_pred(ps),
            FOL::Exists.new(resolution, FOL::And.new(
              @resolution_link[ps, resolution],
              FOL::And.new((0..@blocks.length-1).map { |i|
                FOL::Equiv.new(is_trues[i][resolution], FOL::ForAll.new(o, FOL::Equiv.new(prev_state[ps, o], pre_states[i][ps, o])))
              })
            ))
          ))
        end

        @blocks.length.times do |i|
          translation.prev_state = pre_states[i]
          @blocks[i].migrate_state_spass translation
          post_states << translation.prev_state
        end
          
        translation.reserve_names context.p_names, :resolution, :o do |ps, resolution, o|
          translation.create_formula FOL::ForAll.new(ps, FOL::Implies.new(
            translation.context.type_pred(ps),
            FOL::Exists.new(resolution, FOL::And.new(
              @resolution_link[ps, resolution],
              FOL::And.new((0..@blocks.length-1).map { |i|
                FOL::Equiv.new(is_trues[i][resolution], FOL::ForAll.new(o, FOL::Equiv.new(post_state[ps, o], post_states[i][ps, o])))
              })
            ))
          ))
        end
        
        translation.prev_state = post_state
      end
    end

    class DSEitherLambdaObjset < DSNode
      def prepare_action(translation); end

      def resolve_action_objset(translation, ps, o)
        translation.reserve_names :r do |r|
          implications = []
          @either.blocks.length.times do |i|
            implications << FOL::Implies.new(@either.is_trues[i][r], @vars[i].resolve_action_objset(translation, ps, o))
          end
          
          return FOL::ForAll.new(:r, FOL::Implies.new(
            @either.resolution_link[ps, r],
            FOL::And.new(implications)
          ))
        end
      end
    end

    class DSForEachCommon < DSNode
      include FOL

      attr_reader :context, :pre_iteration_state, :post_iteration_state, :pre_state, :post_state

      def prepare_with_context(translation, flat_context)
        @context = translation.create_context "for_each_context", flat_context, translation.context
        @objset.prepare_action translation
        translation.context = @context
        @block.prepare translation
        translation.context = @context.parent
      end

      def migrate_state_spass(translation)
        return if @objset.type.nil?

        @pre_state = translation.prev_state
        @post_state = translation.create_state :post_for_each
        
        translation.reserve_names @context.parent.p_names, :o do |ps, o|
          translation.create_formula _for_all(ps, o, _equiv(
            _and(@objset.resolve_action_objset(translation, ps, o), @pre_state[ps, o]),
            @context.type_pred(ps, o)
          ))
        end

        translation.context = @context
        
        @pre_iteration_state = translation.create_state :pre_iteration
        @post_iteration_state = translation.create_state :post_iteration
        
        translation.prev_state = @pre_iteration_state
        @block.migrate_state_spass translation
        
        translation.reserve_names @context.p_names, :o do |ps, o|
          translation.create_formula _for_all(ps, o, _equiv(
            translation.prev_state[ps, o],
            @post_iteration_state[ps, o]
          ))
        end

        create_iteration_formulae translation
        translation.context = @context.parent
        translation.prev_state = post_state
      end
    end

    class DSForEach < DSForEachCommon
      def prepare(translation)
        prepare_with_context(translation, false)
      end

      def create_iteration_formulae(translation)
        raise "Not implemented for flexible arities"
        translation.create_formula _if_then_else_eq(
          _exists(:c, :o, _and(old_state[:c, :o], @objset.resolve_action_objset(translation, :c, :o))),
          _for_all(:parent, :c, :o, _implies(@context.parent_of_link[:parent, :c], _and(
            _if_then_else(
              @context.first[:parent, :c],
              _equiv(old_state[:parent, :o], @pre_iteration_state[:c, :o]),
              _for_all(:prev, _implies(
                @context.just_before[:prev, :c],
                _equiv(@post_iteration_state[:prev, :o], @pre_iteration_state[:c, :o])
              ))
            ),
            _implies(
              @context.last[:parent, :c],
              _equiv(@post_state[:parent, :o], @post_iteration_state[:c, :o])
            )
          ))),
          _for_all(:c, :o, _equiv(@pre_state[:c, :o], @post_state[:c, :o]))
        )
      end
    end

    class DSForEachIteratorObjset < DSNode
      def prepare_action(translation); end

      def resolve_action_objset(translation, ps, o)
        return FOL::Equal.new(o, ps[@for_each.context.level-1])
      end
    end

    class DSForEachPreLambdaObjset < DSNode
      def prepare_action(translation); end

      def resolve_action_objset(translation, ps, o)
        raise "Not implemented for flexible arities"
        translation.reserve_names :parent, :prev_context do |parent, prev_context|
          return FOL::ForAll.new(parent, FOL::Implies.new(@context.parent_of_pred[parent, :c],
            FOL::IfThenElseEq.new(
              @context.first[parent, c],
              @before_var[c, o],
              FOL::Exists.new( prev_context, FOL::And.new(
                @context.just_before[prev_context, c],
                @inside_var[prev_context, o]
              ))
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
        translation.reserve_names context.p_names, :o, :c1, :c2 do |ps, o, c1, c2|
          ps_without_last = ps.first(ps.length - 1)
          translation.create_formula _for_all(ps, o, _implies(
            @context.type_pred(ps),
            _equiv(@pre_state[ps_without_last, o], @pre_iteration_state[ps, o])
          ))
          translation.create_formula _for_all(ps_without_last, o, _if_then_else(
            _not(_exists(ps.last, @context.type_pred(ps))),
            _equiv(@pre_state[ps_without_last, o], @post_state[ps_without_last, o]),
            _implies(
              @context.parent.type_pred(ps_without_last),
              _equiv(
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
              )
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

      def migrate_state_spass(translation)
        @statements.each do |stat|
          stat.migrate_state_spass translation
        end
      end
    end

    class DSAssignment < DSNode
      def prepare(translation)
        @var.define_predicate translation
        @objset.prepare_action translation
      end

      def migrate_state_spass(translation)
        context = translation.context
        translation.reserve_names context.p_names, :o do |ps, o|
          translation.create_formula FOL::ForAll.new(ps, o, FOL::Equiv.new(
            var.resolve_action_objset(translation, ps, o),
            FOL::And.new(
              translation.prev_state[ps, o],
              objset.resolve_action_objset(translation, ps, o)
            )
          ))
        end
      end
    end

    class DSVariable < DSNode
      attr_accessor :context, :pred

      def action_name
        "var_#{@name}"
      end
      
      # The predicate is not defined in prepare_action
      # as we want the predicate to be defined only when assigning to the variable
      # not when using it
      # a nil check does not work because it makes the translation non-reusable
      def prepare_action(translation); end
      def define_predicate(translation)
        @context = translation.context
        @pred = translation.create_predicate action_name, context.level + 1
      end

      def resolve_action_objset(translation, ps, var)
        return @pred[ps.first(@context.level), var]
      end

      def invariant_name
        "invariant_var_#{@name}"
      end

      def resolve_invariant_objset(translation, var)
        FOL::Equal.new(invariant_name, var)
      end

      def [](*args)
        @pred[args]
      end
    end

    class DSAllOf < DSNode
      def prepare_action(translation); end
      
      def resolve_action_objset(translation, ps, var)
        return @klass[var]
      end

      def resolve_invariant_objset(translation, var)
        return @klass[var]
      end
    end

    class DSDereference < DSNode
      def prepare_action(translation)
        @objset.prepare_action translation
      end

      def resolve_action_objset(translation, ps, var)
        translation.reserve_names :temp, :r do |temp, r|
          return FOL::Exists.new(temp, r, FOL::And.new(
            translation.prev_state[ps, r],
            translation.prev_state[ps, temp],
            @objset.resolve_action_objset(translation, ps, temp),
            @relation.left_link[r, temp],
            @relation.right_link[r, var]
          ))
        end
      end

      def resolve_invariant_objset(translation, var)
        translation.reserve_names :temp, :r do |temp, r|
          return FOL::Exists.new(temp, r, FOL::And.new(
            translation.invariant_state[temp],
            translation.invariant_state[r],
            @objset.resolve_invariant_objset(translation, temp),
            @relation.left_link[r, temp],
            @relation.right_link[r, var]
          ))
        end
      end
    end

    class DSSubset < DSNode
      def prepare_action(translation)
        @objset.prepare_action translation
      end

      def resolve_action_objset(translation, ps, var)
        context = translation.context
        pred = translation.create_predicate :subset, context.level + 1
        translation.reserve_names context.p_names do |ps|
          translation.create_formula FOL::ForAll.new(ps, :o,
            FOL::Implies.new(pred[ps, :o], @objset.resolve_action_objset(translation, ps, :o))
          )
        end
        return pred[ps, var]
      end
      
      def resolve_invariant_objset(translation, var)
        pred = translation.create_predicate :subset, 1
        translation.create_formula FOL::ForAll.new(:o, 
          FOL::Implies.new(pred[:o], @objset.resolve_invariant_objset(translation, :o))
        )
        return pred[var]
      end
    end

    class DSEmptyObjset < DSNode
      def prepare_action(translation)
      end

      def resolve_action_objset(translation, ps, var)
        # nothing is in the objset
        return false
      end
      
      def resolve_invariant_objset(translation, var)
        return false
      end
    end

    class DSOr < DSNode
      def resolve_invariant_formula(translation)
        FOL::Or.new(@subformulae.map{ |sub| sub.resolve_invariant_formula translation })
      end
    end
    
    class DSAnd < DSNode
      def resolve_invariant_formula(translation)
        FOL::And.new(@subformulae.map{ |sub| sub.resolve_invariant_formula translation })
      end
    end

    class DSEquiv < DSNode
      def resolve_invariant_formula(translation)
        FOL::Equiv.new(@subformulae.map{ |sub| sub.resolve_invariant_formula translation })
      end
    end
    
    class DSImplies < DSNode
      def resolve_invariant_formula(translation)
        subformula1 = @subformula1.resolve_invariant_formula translation
        subformula2 = @subformula2.resolve_invariant_formula translation
        FOL::Implies.new(subformula1, subformula2)
      end
    end
    
    class DSOneOf < DSNode
      def prepare_action(translation)
        @objset.prepare_action translation
      end

      def resolve_action_objset(translation, ps, var)
        context = translation.context
        pred = translation.create_predicate :one_of, context.level + 1
        translation.gen_formula_for_unique_arg(pred, context.level)
        translation.reserve_names context.p_names, :o do |subps, o|
          co_in_objset = @objset.resolve_action_objset(translation, subps, o)
          translation.create_formula FOL::ForAll.new(subps, FOL::Equiv.new(
            FOL::Exists.new(o, FOL::And.new(translation.prev_state[subps, o], pred[subps, o])),
            FOL::Exists.new(o, FOL::And.new(translation.prev_state[subps, o], co_in_objset))
          ))
          translation.create_formula FOL::ForAll.new(subps, o,
            FOL::Implies.new(pred[subps, o], FOL::And.new(translation.prev_state[subps, o], co_in_objset))
          )
        end
        return pred[ps, var]
      end
    end

    class DSNot < DSNode
      def resolve_invariant_formula(translation)
        subformula = @subformula.resolve_invariant_formula translation
        return FOL::Not.new(subformula)
      end
    end
    
    class DSBoolean < DSNode
      def resolve_invariant_formula(translation)
        return @bool_value.resolve_spass
      end
    end

    class DSForAll < DSNode
      def resolve_invariant_formula(translation)
        subformula = @subformula.resolve_invariant_formula translation
        var_constraints = []
        @vars.length.times do |index|
          var_constraints << @objsets[index].resolve_invariant_objset(translation, @vars[index].invariant_name)
        end
        return FOL::ForAll.new(@vars.map{ |v| v.invariant_name }, FOL::Implies.new(
          FOL::And.new(
            @vars.map{ |v| translation.invariant_state[v.invariant_name] },
            var_constraints
          ),
          subformula
        )).resolve_spass
      end
    end

    class DSExists < DSNode
      def resolve_invariant_formula(translation)
        subformula = @subformula.nil? ? true : @subformula.resolve_invariant_formula(translation)
        subformula ||= true
        return FOL::Exists.new(@vars.map{ |v| v.invariant_name }, FOL::And.new(
          @vars.map{ |v| translation.invariant_state[v.invariant_name] },
          @vars.map{ |v| v.type[v.invariant_name] },
          @vars.map{ |v| v.resolve_invariant_objset(translation, v.invariant_name) },
          subformula
        )).resolve_spass
      end
    end

    class DSEqual < DSNode
      def resolve_invariant_formula(translation)
        translation.reserve_names :temp do |temp|
          objsets = @objsets.map{ |o| o.resolve_invariant_objset translation, temp }
          return FOL::ForAll.new(temp, FOL::Implies.new(
            translation.invariant_state[temp],
            FOL::Equiv.new(objsets)
          )).resolve_spass
        end
      end
    end

    class DSIn < DSNode
      def resolve_invariant_formula(translation)
        translation.reserve_names :temp do |temp|
          return FOL::ForAll.new(temp, FOL::Implies.new(
            translation.invariant_state[temp],
            FOL::Implies.new(
              @objset1.resolve_invariant_objset(translation, temp),
              @objset2.resolve_invariant_objset(translation, temp)
            )
          ))
        end
      end
    end
    
    class DSEmpty < DSNode
      def resolve_invariant_formula(translation)
        translation.reserve_names :temp do |temp|
          return FOL::ForAll.new(temp, FOL::Implies.new(
            translation.invariant_state[temp],
            FOL::Not.new(@objset.resolve_invariant_objset(translation, temp))
          ))
        end
      end
    end
  end
end
