require 'active_support'
require 'active_record'
require 'adsl/lang/ast_nodes'
require 'adsl/extract/instrumenter'
require 'adsl/extract/sexp_utils'
require 'adsl/extract/rails/other_meta'
require 'adsl/extract/rails/kernel_extensions'
require 'adsl/extract/rails/method'
require 'adsl/extract/rails/active_record_metaclass_generator'

module ADSL
  module Extract
    module Rails

      class ActionInstrumenter < ::ADSL::Extract::Instrumenter
        attr_accessor :ex_method, :action_name

        def initialize(ar_class_names, instrument_domain = Dir.pwd)
          super instrument_domain

          @branch_index = 0

          # remove respond_to and render
          render_stmts = [:respond_to, :render, :redirect_to, :respond_with]
          replace :call do |sexp|
            next sexp unless sexp.length >= 3 and sexp[1].nil? and render_stmts.include?(sexp[2])
            s(:call, nil, :ins_do_render)
          end
          replace :iter do |sexp|
            next sexp unless sexp[1].length >= 3 and sexp[1][0] == :call and sexp[1][1].nil? and render_stmts.include?(sexp[1][2])
            s(:call, nil, :ins_do_render)
          end

          # surround the entire method with a call to abb.explore_all
          replace :defn, :defs do |sexp|
            header_elem_count = sexp.sexp_type == :defn ? 3 : 4
            stmts = sexp.pop(sexp.length - header_elem_count)
            
            single_stmt = stmts.length > 1 ? s(:block, *stmts) : stmts.first

            explore_all = s(:iter,
                s(:call, nil, :ins_explore_all, s(:lit, sexp[header_elem_count - 2])),
                s(:args),
                single_stmt)
            
            sexp.push explore_all
            sexp
          end

          # replace raise with ins_do_raise
          replace :call do |sexp|
            next sexp unless sexp[2] == :raise
            s(:call, nil, :ins_do_raise)
          end

          # replace returns with ins_do_return
          replace :return do |sexp|
            s(:call, nil, :ins_do_return, *sexp.sexp_body)
          end
          
          # instrument assignments
          replace :lasgn, :iasgn, :cvasgn, :cvdecl, :gasgn, :masgn, :op_asgn_or, :unless_in => [:args, :op_asgn_or] do |sexp|
            next sexp if sexp.length <= 2

            variables_and_prefixes = if sexp.sexp_type == :masgn
              sexp[1].sexp_body.map{ |asgn_type, var| [asgn_type.to_s[0..-5], var] }
            elsif sexp.sexp_type == :op_asgn_or
              []
            else
              [[sexp[0].to_s[0..-5], sexp[1]]]
            end

            prepare_assignments = variables_and_prefixes.map{ |prefix, var|
              s(:op_asgn_or, s("#{prefix}var".to_sym, var), s("#{prefix}asgn".to_sym, var, s(:nil)))
            }
            
            var_names = if sexp.sexp_type == :masgn
              sexp[1].sexp_body.map{ |var| s(:str, var[1].to_s) }.to_a
            elsif sexp.sexp_type == :op_asgn_or
              [s(:str, sexp[1][1].to_s)]
            else
              [s(:str, sexp[1].to_s)]
            end

            values = if sexp.sexp_type == :masgn
              sexp[2]
            elsif sexp.sexp_type == :op_asgn_or
              s(:array, sexp[2][2])
            else
              s(:array, sexp[2])
            end

            operator = sexp.sexp_type == :op_asgn_or ? s(:str, '||=') : s(:str, '=')

            s(:block,
              *prepare_assignments,
              s(:call, nil, :ins_multi_assignment, s(:call, nil, :binding), s(:array, *var_names), values, operator)
            )
          end

          # prepend wrap blocks in ins_block
          replace :defn, :defs, :block, :iter do |sexp|
            first_stmt_index = case sexp.sexp_type
              when :defn; 3
              when :defs; 4
              when :iter; 3
              when :block; 1
            end

            block_sexp = s(:call, nil, :ins_block, *sexp[first_stmt_index..-1])

            s(*sexp.first(first_stmt_index), block_sexp)
          end
          
          # instrument branches
          replace :if do |sexp|
            block1_sexp = sexp[2] || s(:nil)
            block1 = block1_sexp.sexp_type == :block ? block1_sexp : s(:block, block1_sexp)
            block2_sexp = sexp[3] || s(:nil)
            block2 = block2_sexp.sexp_type == :block ? block2_sexp : s(:block, block2_sexp)
            s(:call, nil, :ins_if,
              sexp[1],
            #  s(:rescue,
                s(:call, nil, :ins_block, block1),
            #    s(:resbody,
            #      s(:array, s(:const, :Exception)),
            #      s(:nil)
            #    )
            #  ),
            #  s(:rescue,
                s(:call, nil, :ins_block, block2),
            #    s(:resbody,
            #      s(:array, s(:const, :Exception)),
            #      s(:nil)
            #    )
            #  )
            )
          end

          # change rescue into a branch statement
          replace :rescue do |sexp|
            resbody = sexp.sexp_body.select{ |a| a.sexp_type == :resbody }.first
            exception_type_array = s(:array, *resbody[1].sexp_body)
            res_block = resbody[2..-1]
            res_block = res_block.length > 1 ? s(:block, *res_block) : res_block.first
            s(:if, s(:lit, :symbols_get_translated_as_star_conditions), res_block, sexp[1])
          end

          # replace try with ins_try
          replace :call do |sexp|
            next sexp if sexp.sexp_body[1] != :try

            original_object = sexp.sexp_body[0] || s(:self)
            original_method_name = sexp.sexp_body[2]
            original_args = sexp.sexp_body[3..-1]

            s(:call, nil, :ins_try, original_object, original_method_name, *original_args)
          end

          # change attrasgn into a normal call
          replace :attrasgn do |sexp|
            s(:call, *sexp.sexp_body)
          end

          # replace calls to collection_action, member_action or page_action with a def
          # these represent code sugar for defining actions with the activeadmin gem
          replace :iter do |sexp|
            next sexp unless (
              sexp[1].sexp_type == :call &&
              sexp[1][1] == nil &&
              [:collection_action, :member_action, :page_action].include?(sexp[1][2])
            )
            args = sexp[2]
            args = s(:args) if args == 0
            s(:defn, sexp[1][3][1], args, sexp[3])
          end
        end

        def should_instrument?(object, method_name)
          return false unless super

          klass = object.is_a?(Class) ? object : object.class
          method = object.method method_name

          klass.name.match(/^ADSL::.*$/).nil? && !(method.source_location[0] =~ /.*lib\/adsl\/.*/)
        end
      end

    end
  end
end
