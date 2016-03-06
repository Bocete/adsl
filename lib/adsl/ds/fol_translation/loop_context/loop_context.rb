require 'adsl/util/general'
require 'adsl/fol/first_order_logic'
require 'adsl/ds/fol_translation/typed_string'

module ADSL
  module DS
    module FOLTranslation
      module LoopContext
        class LoopContextCommon
          include ADSL::FOL

          attr_accessor :parent, :level, :context_sort

          def type_pred(*args)
            return @level == 0 ? true : @type_pred[args]
          end

          def context_for_level(level)
            raise ArgumentError, "Your level is too damn high (#{level} for #{@level})" if level > @level
            return self if level == @level
            return @parent.context_for_level level
          end

          def sort_array
            return [] if @level == 0
            [@context_sort] if @level == 1
            parent.sort_array << context_sort
          end

          def initialize(translation, name, parent, context_sort)
            @level = parent.nil? ? 0 : parent.level + 1
            @translation = translation
            @parent = parent
            @context_sort = context_sort
            
            unless parent.nil?
              @type_pred = translation.create_predicate(name, parent.sort_array, context_sort)
              # ps includes the context object of this context
              translation.reserve make_ps do |ps|
                translation.create_formula ForAll.new(ps, Implies.new(
                  @type_pred[ps],
                  @parent.type_pred(ps[0..-2])
                ))
              end
              translation.create_formula ADSL::DS::FOLTranslation::Util.gen_formula_for_unique_arg(@type_pred, 0..@level-2)
            end
          end

          def same_level_before_formula(parents, c1, c2)
            raise 'To be implemented by a specific context class'
          end

          def make_ps(prefix = 'p')
            sort_array.map_index{ |sort, index| TypedString.new sort, "#{ prefix }#{ index + 1 }" }
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
            if @parent.nil?
              # this is the root context
              return executed_before
            end
            @translation.reserve(@parent.make_ps "parent_a") do |context1_names|
              @translation.reserve(c2.parent.make_ps "parent_b") do |context2_names|
                context1_names << c1var
                context2_names << c2var
                common_context = LoopContextCommon.get_common_context c1, c2

                before_options = Or.new(
                  (1..common_context.level).map{ |index|
                    And.new(
                      (index <= 1 ? true : Equal.new(context1_names[index-2], context2_names[index-2])),
                      common_context.context_for_level(index).same_level_before_formula(
                        context1_names.first(index-1),
                        context1_names[index-1],
                        context2_names[index-1]
                      )
                    )
                  },
                  And.new(
                    Equal.new(context1_names[common_context.level-1], context2_names[common_context.level-1]),
                    executed_before
                  )
                )
                return ForAll.new(context1_names[0..-2], context2_names[0..-2], Implies.new(
                  And.new(
                    (c1.level <= 1 ? true : c1.type_pred(context1_names)),
                    (c2.level <= 1 ? true : c2.type_pred(context2_names))
                  ),
                  before_options
                )).optimize
              end
            end
          end
        end

        class FlatLoopContext < LoopContextCommon
          def initialize(translation, name, parent, sort)
            super
          end

          def same_level_before_formula(ps, c1, c2)
            false
          end
        end

        class ChainedLoopContext < LoopContextCommon
          attr_accessor :before_pred, :just_before, :first, :last
          include FOL

          def initialize(translation, name, parent, sort)
            super

            @before_pred = translation.create_predicate "#{@type_pred.name}_before", sort_array, @context_sort
            @just_before = translation.create_predicate "#{@type_pred.name}_just_before", sort_array, @context_sort
            @first = translation.create_predicate "#{@type_pred.name}_first", sort_array
            @last = translation.create_predicate "#{@type_pred.name}_last", sort_array

            translation.reserve(
                @parent.make_ps,
                @context_sort, :c,
                @context_sort, :c1,
                @context_sort, :c2,
                @context_sort, :c3) do |ps, c, c1, c2, c3|

              translation.create_formula ForAll[ps, c, Not[@before_pred[ps, c, c]]]
              translation.create_formula ForAll[ps, c1, c2, Implies[
                @before_pred[ps, c1, c2],
                And[
                  @type_pred[ps, c1],
                  @type_pred[ps, c2],
                  Not[@before_pred[ps, c2, c1]]
                ]
              ]]
              translation.create_formula ForAll[ps, c1, c2,
                Implies[
                  And[@type_pred[ps, c1], @type_pred[ps, c2]],
                  Or[
                    Equal[c1, c2],
                    @before_pred[ps, c1, c2],
                    @before_pred[ps, c2, c1]
                  ]
                ]
              ]
              translation.create_formula ForAll[ps, c1, c2, c3, Implies[
                And[@before_pred[ps, c1, c2], @before_pred[ps, c2, c3]],
                @before_pred[ps, c1, c3]
              ]]
              translation.create_formula ForAll[ps, c1, c2, Equiv[
                @just_before[ps, c1, c2],
                And[
                  @before_pred[ps, c1, c2],
                  Not[Exists[c, And[
                    @before_pred[ps, c1, c],
                    @before_pred[ps, c, c2]
                  ]]]
                ]
              ]]
              translation.create_formula ForAll[ps, And[
                Equiv[
                  Exists[c, @type_pred[ps, c]],
                  Exists[c, @first[ps, c]],
                  Exists[c, @last[ps, c]]
                ],
                ForAll[ps, c, Implies[
                  @type_pred[ps, c],
                  Xor[
                    @last[ps, c],
                    Exists[c2, @just_before[ps, c, c2]
                  ]]
                ]],
                ForAll[ps, c, Equiv[
                  @first[ps, c],
                  And[
                    @type_pred[ps, c],
                    Not[Exists[c2, @before_pred[ps, c2, c]]]
                  ]
                ]],
                ForAll[ps, c, Equiv[
                  @last[ps, c],
                  And[
                    @type_pred[ps, c],
                    Not[Exists[c2, @before_pred[ps, c, c2]]]
                  ]
                ]]
              ]]
            end
          end

          def same_level_before_formula(ps, c1, c2)
            @before_pred[ps, c1, c2]
          end
        end
      end
    end
  end
end

