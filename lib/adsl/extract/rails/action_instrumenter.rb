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

  def ins_optional_assignment(outer_binding, name, value)
    result = ins_multi_assignment(outer_binding, [name], value, '||=')
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
    values = [values] unless values.is_a? Array

    values_to_be_returned = []
    names.length.times do |index|
      name = names[index]
      value = values[index]

      adsl_ast_name = if /^@@[^@]+$/ =~ name.to_s
        "atat__#{ name.to_s[2..-1] }"
      elsif /^@[^@]+$/ =~ name.to_s
        "at__#{ name.to_s[1..-1] }"
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
        outer_binding.eval "#{name} #{operator} ObjectSpace._id2ref(#{variable.object_id})"
        
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

  def ins_branch_choice(branch_id)
    ::ADSL::Extract::Instrumenter.get_instance.abb.branch_choice branch_id
  end

  def ins_explore_all(method_name = nil, &block)
    instrumenter = ::ADSL::Extract::Instrumenter.get_instance
    return_value = instrumenter.abb.explore_all_choices &block
    
    instrumenter.prev_abb << instrumenter.abb.adsl_ast
    instrumenter.prev_abb << ::ADSL::Parser::ASTDummyStmt.new(:type => method_name) unless method_name.nil?
    return_value
  end

  def ins_if(lambda1, lambda2)
    instrumenter = ::ADSL::Extract::Instrumenter.get_instance

    stmts = instrumenter.abb.in_stmt_frame &lambda1
    block1 = ::ADSL::Parser::ASTBlock.new :statements => stmts

    stmts = instrumenter.abb.in_stmt_frame &lambda2
    block2 = ::ADSL::Parser::ASTBlock.new :statements => stmts

    ::ADSL::Parser::ASTEither.new :blocks => [block1, block2]
  end

  def ins_root_lvl_push_expr(expr = nil)
    Array.wrap(expr).each do |final_return|
      adsl_ast = ::ADSL::Extract::Rails::ActionInstrumenter.extract_stmt_from_expr final_return
      if adsl_ast and adsl_ast.class.is_statement?
        instrumenter = ::ADSL::Extract::Instrumenter.get_instance
        instrumenter.abb.root_paths.each do |root_path|
          root_path << adsl_ast unless instrumenter.abb.included_already? root_path, adsl_ast
        end
      end
    end
    expr
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
          {
            :abb => ActionBlockBuilder.new 
          }
        end

        def initialize(ar_class_names, instrument_domain = Dir.pwd)
          super instrument_domain

          @branch_index = 0

          ar_class_names = ar_class_names.map{ |n| n.split('::').last }

          # replace all ActiveRecord classes with their meta-variants
          replace :const do |sexp|
            if ar_class_names.include? sexp[1].to_s
              sexp[1] = ActiveRecordMetaclassGenerator.target_classname(sexp[1].to_s).to_sym
            end
            sexp
          end
          replace :colon2 do |sexp|
            if ar_class_names.include? sexp[2].to_s
              sexp[2] = ActiveRecordMetaclassGenerator.target_classname(sexp[2].to_s).to_sym
            end
            sexp
          end

          # remove respond_to and render
          [:respond_to, :render, :redirect_to].each do |stmt|
            replacer = lambda{ |sexp|
              next sexp unless sexp.length >= 3 and sexp[0] == :call and sexp[1].nil? and sexp[2] == stmt
              s(:call, nil, :ins_mark_render_statement)
            }

            replace :iter, &replacer
            replace :call, &replacer
          end

          # surround the entire method with a call to abb.explore_all_choices
          replace :defn, :defs do |sexp|
            header_elem_count = sexp.sexp_type == :defn ? 3 : 4
            stmts = sexp.pop(sexp.length - header_elem_count)
            single_stmt = stmts.length > 1 ? s(:block, *stmts) : stmts.first

            explore_all = s(:iter, s(:call, nil, :ins_explore_all), s(:args), single_stmt)
            
            if @stack_depth == 0
              explore_all[1] << s(:lit, sexp[header_elem_count - 2])
              # ins_stmt explore_all on root call, since the caller will not handle it
              explore_all = s(:call, nil, :ins_root_lvl_push_expr, explore_all)
            end
            
            sexp.push explore_all
            sexp
          end

          # replace returns with ins_do_return
          replace :return do |sexp|
            s(:call, nil, :ins_do_return, *sexp.sexp_body)
          end

          # instrument ||= assignments
          replace :op_asgn_or do |sexp|
            prepare_assignment = s(:op_asgn_or, sexp[1].dup, s(sexp[2][0], sexp[2][1], s(:nil)))
            var_name = sexp[1][1].to_s

            s(:block,
              prepare_assignment,
              s(:call, nil, :ins_optional_assignment, s(:call, nil, :binding), s(:str, var_name.to_s), sexp[2][2]),
            )
          end
          
          # instrument assignments
          replace :lasgn, :iasgn, :cvasgn, :masgn, :unless_in => [:args, :op_asgn_or] do |sexp|
            next sexp if sexp.length <= 2

            prepare_assignment = if sexp.sexp_type == :masgn
              nils = s(:array, *([s(:nil)] * sexp[1].sexp_body.length))
              s(:masgn, sexp[1], nils)
            else
              s(sexp[0], sexp[1], s(:nil))
            end
            
            var_names = if sexp.sexp_type == :masgn
              sexp[1].sexp_body.map{ |var| s(:str, var[1].to_s) }.to_a
            else
              [s(:str, sexp[1].to_s)]
            end

            s(:block,
              prepare_assignment,
              s(:call, nil, :ins_multi_assignment, s(:call, nil, :binding), s(:array, *var_names), sexp[2])
            )
          end

          # prepend ins_stmt to every non-return or non-if statement
          replace :defn, :defs, :block do |sexp|
            first_stmt_index = case sexp.sexp_type
              when :defn; 3
              when :defs; 4
              when :block; 1
            end
            (first_stmt_index..sexp.length-1).each do |index|
              unless [:if, :return].include? sexp[index].sexp_type
                sexp[index] = s(:call, nil, :ins_stmt, sexp[index])
              end
            end
            sexp
          end

          # make the implicit return explicit
          replace :defn, :defs do |sexp|
            container = sexp
            return_stmt_index = -1
            while [:ensure, :rescue, :block].include? container[return_stmt_index].sexp_type
              container = container[return_stmt_index]
              return_stmt_index = container.sexp_type == :block ? -1 : 1
            end
            container[return_stmt_index] = s(:return, container[return_stmt_index]) unless container[return_stmt_index].sexp_type == :return
            sexp
          end
          
          # instrument branches
          replace :if do |sexp|
            if sexp.may_return?
              sexp[1] = s(:call, nil, :ins_branch_choice, s(:lit, @branch_index += 1))
              sexp[2] = s(:block, sexp[2]) unless sexp[2].nil? or sexp[2].sexp_type == :block
              sexp[3] = s(:block, sexp[3]) unless sexp[3].nil? or sexp[3].sexp_type == :block
              sexp
            else
              block1 = sexp[2].nil? || sexp[2].sexp_type == :block ? sexp[2] : s(:block, sexp[2])
              block2 = sexp[3].nil? || sexp[3].sexp_type == :block ? sexp[3] : s(:block, sexp[3])
              s(:call, nil, :ins_if, 
                s(:iter, s(:call, nil, :lambda), s(:args), block1),
                s(:iter, s(:call, nil, :lambda), s(:args), block2)
              )
            end
          end
        end

        def should_instrument?(object, method_name)
          klass = object.class != Class ? object.class : object
          method = object.method method_name
          
          klass.name.match(/^ADSL::.*$/).nil? &&
            !method.owner.respond_to?(:adsl_ast_class_name) &&
            !method.owner.method_defined?(:adsl_ast_class_name) &&
            super
        end
      end

    end
  end
end
