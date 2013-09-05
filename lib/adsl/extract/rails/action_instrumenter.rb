require 'active_support'
require 'active_record'
require 'adsl/parser/ast_nodes'
require 'adsl/extract/instrumenter'
require 'adsl/extract/sexp_utils'
require 'adsl/extract/rails/other_meta'
require 'adsl/extract/rails/action_block_builder'
require 'adsl/extract/rails/active_record_metaclass_generator'

module Kernel
  def ins_stmt(expr = nil, options = {})
    if expr.is_a? Array
      expr.each do |subexpr|
        ins_stmt subexpr, options
      end
    else
      stmt = ::ADSL::Extract::Rails::ActionInstrumenter.extract_stmt_from_expr expr
      if stmt.is_a? ::ADSL::Parser::ASTNode and stmt.class.is_statement?
        ::ADSL::Extract::Instrumenter.get_instance.abb.append_stmt stmt, options
      end
    end
    expr
  end

  def ins_mark_render_statement()
    ::ADSL::Parser::ASTDummyStmt.new :type => :render
  end

  def ins_optional_assignment(outer_binding, names, values)
    result = ins_multi_assignment(outer_binding, names, values, '||=')
    mapped = result.map do |return_value|
      if return_value.is_a? ::ADSL::Parser::ASTNode
        ::ADSL::Parser::ASTEither.new :blocks => [
          ::ADSL::Parser::ASTBlock.new(:statements => [return_value]),
          ::ADSL::Parser::ASTBlock.new(:statements => [])
        ]
      else
        return_value
      end
    end
    mapped
  end

  def ins_multi_assignment(outer_binding, names, values, operator = '=')
    values_to_be_returned = []
    names.length.times do |index|
      name = names[index]
      value = values[index]

      adsl_ast_name = if /^@@[^@]+$/ =~ name.to_s
        "atat__#{ name.to_s[2..-1] }"
      elsif /^@[^@]+$/ =~ name.to_s
        "at__#{ name.to_s[1..-1] }"
      elsif /^\$.*$/ =~ name.to_s
        "global__#{ name.to_s[1..-1] }"
      else
        name.to_s
      end
      
      if value.nil?
        outer_binding.eval "#{name} #{operator} nil"
        
        values_to_be_returned << ::ADSL::Parser::ASTAssignment.new(
          :var_name => ::ADSL::Parser::ASTIdent.new(:text => adsl_ast_name),
          :objset => ::ADSL::Parser::ASTEmptyObjset.new
        )
      elsif value.is_a? ActiveRecord::Base
        variable = value.class.new(:adsl_ast =>
          ::ADSL::Parser::ASTVariable.new(:var_name => ::ADSL::Parser::ASTIdent.new(:text => adsl_ast_name))
        )
        str = "#{name} #{operator} ObjectSpace._id2ref(#{variable.object_id})"
        outer_binding.eval str
        
        values_to_be_returned << ::ADSL::Parser::ASTAssignment.new(
          :var_name => ::ADSL::Parser::ASTIdent.new(:text => adsl_ast_name),
          :objset => value.adsl_ast
        )
      else
        outer_binding.eval "#{name} #{operator} ObjectSpace._id2ref(#{value.object_id})"
        values_to_be_returned << value
      end
    end
    values_to_be_returned
  end

  def ins_do_return(*return_values)
    ::ADSL::Extract::Instrumenter.get_instance.abb.do_return *return_values
  end

  def ins_do_raise(*args)
    ::ADSL::Extract::Instrumenter.get_instance.abb.do_raise *args
  end

  def ins_branch_choice(condition, branch_id)
    ins_stmt condition
    ::ADSL::Extract::Instrumenter.get_instance.abb.branch_choice branch_id 
  end

  def ins_explore_all(method_name, &block)
    instrumenter = ::ADSL::Extract::Instrumenter.get_instance

    return_value = instrumenter.abb.explore_all_choices &block

    block_adsl_ast = instrumenter.abb.adsl_ast
    instrumenter.prev_abb << block_adsl_ast

    # are we at the root level? if so, wrap everything around in an action/callback
    if instrumenter.stack_depth == 2
      Array.wrap(return_value).each do |final_return|
        adsl_ast = ::ADSL::Extract::Rails::ActionInstrumenter.extract_stmt_from_expr final_return
        block_adsl_ast.statements << adsl_ast if !adsl_ast.nil? and adsl_ast.class.is_statement?
      end
      instrumenter.prev_abb << ::ADSL::Parser::ASTDummyStmt.new(:type => method_name)
    end
    
    return_value
  end

  def ins_push_frame
    instrumenter = ::ADSL::Extract::Instrumenter.get_instance
    instrumenter.abb.push_frame
  end
  
  def ins_pop_frame
    instrumenter = ::ADSL::Extract::Instrumenter.get_instance
    instrumenter.abb.pop_frame
  end

  def ins_if(condition, arg1, arg2)
    ins_stmt condition
    push_frame_expr1, frame1_ret_value, frame1_stmts = arg1
    push_frame_expr2, frame2_ret_value, frame2_stmts = arg2

    if frame1_stmts.length <= 1 && frame2_stmts.length <= 1 &&
        frame1_ret_value.respond_to?(:adsl_ast) && frame1_ret_value.adsl_ast.class.is_objset? &&
        frame2_ret_value.respond_to?(:adsl_ast) && frame2_ret_value.adsl_ast.class.is_objset?

      return nil if frame1_ret_value.nil? && frame2_ret_value.nil?
      
      result_type = if frame1_ret_value.nil?
        frame2_ret_value.class
      elsif frame2_ret_value.nil?
        frame1_ret_value.class
      elsif frame1_ret_value.class <= frame2_ret_value.class
        frame2_ret_value.class
      elsif frame2_ret_value.class <= frame1_ret_value.class
        frame1_ret_value.class
      else
        # objset types are incompatible
        # but MRI cannot parse return statements inside an if that's being assigned
        nil
      end

      if result_type.nil?
        block1 = ::ADSL::Parser::ASTBlock.new :statements => frame1_stmts
        block2 = ::ADSL::Parser::ASTBlock.new :statements => frame2_stmts
        return ::ADSL::Parser::ASTEither.new :blocks => [block1, block2]
      end

      result_type.new(:adsl_ast => ::ADSL::Parser::ASTOneOfObjset.new(
        :objsets => [frame1_ret_value.adsl_ast, frame2_ret_value.adsl_ast]
      ))
    else
      block1 = ::ADSL::Parser::ASTBlock.new :statements => frame1_stmts
      block2 = ::ADSL::Parser::ASTBlock.new :statements => frame2_stmts
      ::ADSL::Parser::ASTEither.new :blocks => [block1, block2]
    end
  end
end

module ADSL
  module Extract
    module Rails

      class ActionInstrumenter < ::ADSL::Extract::Instrumenter
        def self.extract_stmt_from_expr(expr, method_name=nil)
          adsl_ast = expr
          adsl_ast = expr.adsl_ast if adsl_ast.respond_to? :adsl_ast
          return nil unless adsl_ast.is_a? ::ADSL::Parser::ASTNode
          return adsl_ast if adsl_ast.class.is_statement?
          return ::ADSL::Parser::ASTObjsetStmt.new :objset => adsl_ast if adsl_ast.class.is_objset?
          nil
        end

        attr_accessor :action_block

        def abb
          method_locals[:abb]
        end

        def prev_abb
          previous_locals[:abb]
        end

        def create_locals
          { :abb => ActionBlockBuilder.new }
        end

        def make_returns_explicit(sexp, last_stmt_index = -1)
          last_stmt = sexp[last_stmt_index]
          case last_stmt.sexp_type
          when :block
            make_returns_explicit last_stmt, -1
          when :if
            if last_stmt[2].nil?
              last_stmt[2] = s(:return)
            else
              make_returns_explicit last_stmt, 2
            end
            if last_stmt[3].nil?
              last_stmt[3] = s(:return)
            else
              make_returns_explicit last_stmt, 3
            end
          when :ensure
            make_returns_explicit last_stmt, 1
          when :rescue
            make_returns_explicit last_stmt, 1
          else
            sexp[last_stmt_index] = s(:return, last_stmt) unless last_stmt.sexp_type == :return
          end
        end

        def initialize(ar_class_names, instrument_domain = Dir.pwd)
          super instrument_domain

          @branch_index = 0

          # remove respond_to and render
          render_stmts = [:respond_to, :render, :redirect_to, :respond_with]
          replace :call do |sexp|
            next sexp unless sexp.length >= 3 and sexp[1].nil? and render_stmts.include?(sexp[2])
            s(:call, nil, :ins_mark_render_statement)
          end
          replace :iter do |sexp|
            next sexp unless sexp[1].length >= 3 and sexp[1][0] == :call and sexp[1][1].nil? and render_stmts.include?(sexp[1][2])
            s(:call, nil, :ins_mark_render_statement)
          end

          # surround the entire method with a call to abb.explore_all_choices
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

            if sexp.sexp_type == :op_asgn_or
              prepare_assignment = s(:op_asgn_or, sexp[1].dup, s(sexp[2][0], sexp[2][1], s(:nil)))
              var_names = s(:array, s(:str, sexp[1][1].to_s))
              values = s(:array, sexp[2][2])

              s(:block,
                prepare_assignment,
                s(:call, nil, :ins_optional_assignment, s(:call, nil, :binding), var_names, values),
              )
            else
              variables_and_prefixes = if sexp.sexp_type == :masgn
                sexp[1].sexp_body.map{ |asgn_type, var| [asgn_type.to_s[0..-5], var] }
              else
                [[sexp[0].to_s[0..-5], sexp[1]]]
              end

              prepare_assignments = variables_and_prefixes.map{ |prefix, var|
                s(:op_asgn_or, s("#{prefix}var".to_sym, var), s("#{prefix}asgn".to_sym, var, s(:nil)))
              }
              
              var_names = if sexp.sexp_type == :masgn
                sexp[1].sexp_body.map{ |var| s(:str, var[1].to_s) }.to_a
              else
                [s(:str, sexp[1].to_s)]
              end

              values = if sexp.sexp_type == :masgn
                sexp[2]
              else
                s(:array, sexp[2])
              end

              s(:block,
                *prepare_assignments,
                s(:call, nil, :ins_multi_assignment, s(:call, nil, :binding), s(:array, *var_names), values)
              )
            end
          end

          # prepend ins_stmt to every non-return or non-if statement
          replace :defn, :defs, :block, :iter do |sexp|
            first_stmt_index = case sexp.sexp_type
              when :defn; 3
              when :defs; 4
              when :iter; 3
              when :block; 1
            end
            (first_stmt_index..sexp.length-1).each do |index|
              unless [:if, :return].include?(sexp[index].sexp_type) ||
                  (sexp[index][1].nil? && [:ins_push_frame, :ins_pop_frame].include?(sexp[index][2]))
                sexp[index] = s(:call, nil, :ins_stmt, sexp[index])
              end
            end
            sexp
          end
          
          # instrument branches
          replace :if do |sexp|
            if sexp.may_return_or_raise?
              sexp[1] = s(:call, nil, :ins_branch_choice, sexp[1], s(:lit, @branch_index += 1))
              sexp[2] = s(:block, sexp[2]) unless sexp[2].nil? or sexp[2].sexp_type == :block
              sexp[3] = s(:block, sexp[3]) unless sexp[3].nil? or sexp[3].sexp_type == :block
              sexp
            else
              block1_sexp = sexp[2] || s(:nil)
              block1 = block1_sexp.sexp_type == :block ? block1_sexp : s(:block, block1_sexp)
              block2_sexp = sexp[3] || s(:nil)
              block2 = block2_sexp.sexp_type == :block ? block2_sexp : s(:block, block2_sexp)
              s(:call, nil, :ins_if,
                sexp[1],
                s(:array,
                  s(:call, nil, :ins_push_frame),
                  s(:splat, s(:rescue,
                    s(:array, block1, s(:call, nil, :ins_pop_frame)),
                    s(:resbody,
                      s(:array, s(:const, :Exception)),
                      s(:array, s(:nil), s(:call, nil, :ins_pop_frame))
                    )
                  ))
                ),
                s(:array,
                  s(:call, nil, :ins_push_frame),
                  s(:splat, s(:rescue,
                    s(:array, block2, s(:call, nil, :ins_pop_frame)),
                    s(:resbody,
                      s(:array, s(:const, :Exception)),
                      s(:array, s(:nil), s(:call, nil, :ins_pop_frame))
                    )
                  ))
                )
              )
            end
          end

          # change rescue into a branch statement
          replace :rescue do |sexp|
            resbody = sexp.sexp_body.select{ |a| a.sexp_type == :resbody }.first
            exception_type_array = s(:array, *resbody[1].sexp_body)
            res_block = resbody[2..-1]
            res_block = res_block.length > 1 ? s(:block, *res_block) : res_block.first
            s(:if, s(:nil), sexp[1], res_block)
          end

          # change attrasgn into a normal call
          replace :attrasgn do |sexp|
            s(:call, *sexp.sexp_body)
          end

          # make the implicit return explicit
          replace :defn, :defs do |sexp|
            make_returns_explicit sexp
            sexp
          end

          # replace calls to collection_action, member_action or page_action with a def
          # these represent code sugar for defining actions with the activeadmin gem
          replace :iter do |sexp|
            next sexp unless (
              sexp[1].sexp_type == :call &&
              sexp[1][1] == nil &&
              [:collection_action, :member_action, :page_action].include?(sexp[1][2])
            )
            s(:defn, sexp[1][3][1], sexp[2], sexp[3])
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
