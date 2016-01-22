require 'adsl/extract/instrumenter'
require 'adsl/extract/rails/action_instrumenter'
require 'adsl/extract/rails/basic_type_extensions'

module Kernel
  alias_method :old_ins_call, :ins_call

  def ins_call(object, method_name, *args, &block)
    # if the object is a basic type, and either the object or any of the args are unknown basic values,
    # return an unknown basic value
    if object.respond_to?(:ds_type) && object.ds_type.is_basic_type?
      unknowns = ([object] + args).map{ |a| a.is_a? ADSL::Extract::Rails::UnknownOfBasicType }
      if unknowns.include? true
        object_example = object.respond_to?(:type_example) ? object.type_example : object
        arg_examples = args.map{ |a| a.respond_to?(:type_example) ? a.type_example : a }
        result = old_ins_call object_example, method_name, *arg_examples, &block
        return ADSL::Extract::Rails::UnknownOfBasicType.new result.ds_type
      end
    end
    old_ins_call object, method_name, *args, &block
  end

  def ins_stmt(expr = nil, options = {})
    if expr.is_a? Array
      expr.each do |subexpr|
        ins_stmt subexpr, options
      end
    else
      instrumenter = ::ADSL::Extract::Instrumenter.get_instance
      stmt = ::ADSL::Extract::Rails::ActionInstrumenter.extract_stmt_from_expr expr
      if stmt.is_a?(::ADSL::Parser::ASTNode) && stmt.class.is_statement?
        instrumenter.ex_method.append_stmt stmt, options
      end
    end
    expr
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
      
      if value.respond_to?(:adsl_ast) && (value.nil? || value.is_a?(ActiveRecord::Base)) #value.adsl_ast.class.is_expr?
        assignment = ::ADSL::Parser::ASTExprStmt.new(:expr => ::ADSL::Parser::ASTAssignment.new(
          :var_name => ::ADSL::Parser::ASTIdent.new(:text => adsl_ast_name),
          :expr => value.adsl_ast
        ))
        if operator == '||='
          old_value = outer_binding.eval name rescue nil
          if old_value.respond_to?(:adsl_ast) && old_value.adsl_ast.class.is_expr?
            assignment = ::ADSL::Parser::ASTIf.new(
              :condition => ::ADSL::Parser::ASTIsEmpty.new(:objset => old_value.adsl_ast),
              :then_block => ::ADSL::Parser::ASTBlock.new(:statements => [assignment]),
              :else_block => ::ADSL::Parser::ASTBlock.new(:statements => []),
            )
          end
        end
        ins_stmt assignment

        new_value = !value.is_a?(ActiveRecord::Base) ? value.dup : value.class.new(
          :adsl_ast => ::ADSL::Parser::ASTVariable.new(:var_name => ::ADSL::Parser::ASTIdent.new(:text => adsl_ast_name)
        ))

        outer_binding.eval "#{name} #{operator} ObjectSpace._id2ref(#{new_value.object_id})"
        
        values_to_be_returned << new_value
      else
        outer_binding.eval "#{name} #{operator} ObjectSpace._id2ref(#{value.object_id})"
        values_to_be_returned << value
      end
    end
    names.length == 1 ? values_to_be_returned.first : values_to_be_returned
  end

  def ins_do_return(return_value = nil)
    instrumenter = ::ADSL::Extract::Instrumenter.get_instance

    return_asts = [return_value].flatten.map{ |r| r.respond_to?(:adsl_ast) ? r.adsl_ast : r }
    all_asts = return_asts.map{ |r| r.is_a? ADSL::Parser::ASTNode }.uniq == [true]

    if all_asts
      all_exprs = return_asts.map(&:class).map(&:is_expr?).uniq == [true]
    end

    if all_asts && all_exprs 
      instrumenter.ex_method.set_return_types [return_value].flatten.map(&:class)
      ins_stmt ::ADSL::Parser::ASTReturn.new(:exprs => return_asts)
    else
      instrumenter.ex_method.cancel_return_stmt
      [return_value].flatten.each do |returned_value|
        ins_stmt returned_value
      end
    end
    nil
  end

  def ins_do_raise(*args)
    ::ADSL::Parser::ASTRaise.new
  end

  def ins_do_render
    instrumenter = ::ADSL::Extract::Instrumenter.get_instance
    if instrumenter.action_name.to_s == instrumenter.ex_method.name.to_s
      ins_stmt ::ADSL::Parser::ASTDummyStmt.new(:label => :render)
    else
      ins_stmt ::ADSL::Parser::ASTRaise.new 
    end
  end

  def ins_explore_all(method_name, &block)
    instrumenter = ::ADSL::Extract::Instrumenter.get_instance
    old_method = instrumenter.ex_method
    method = ::ADSL::Extract::Rails::Method.new :name => method_name, :action_or_callback => old_method.name == :root
    instrumenter.ex_method = method

    block, return_val = method.extract_from &block

    old_method << block
    if method.action_or_callback?
      old_method << ::ADSL::Parser::ASTDummyStmt.new(:label => method_name)
    end

    return return_val
  rescue Exception => e
    if TEST_ENV
      raise e
    else
      return nil
    end
  ensure
    instrumenter.ex_method = old_method if instrumenter
  end

  def ins_push_frame
    instrumenter = ::ADSL::Extract::Instrumenter.get_instance
    instrumenter.ex_method.push_frame
  end
  
  def ins_pop_frame
    instrumenter = ::ADSL::Extract::Instrumenter.get_instance
    instrumenter.ex_method.pop_frame
  end

  def ins_if(condition, arg1, arg2)
    ast = condition
    
    ast = ast.adsl_ast if ast.respond_to?(:adsl_ast)
    condition_ast = nil
    if ast.is_a? ADSL::Parser::ASTNode
      if ast.class.is_expr?
        condition_ast = ast
      else
        ins_stmt condition
      end
    end

    # this condition exists because of an error condition in kandan
    condition_ast = nil if condition_ast.is_a?(ADSL::Parser::ASTString || ADSL::Parser::ASTNumber)

    condition_ast ||= ADSL::Parser::ASTBoolean.new(:bool_value => nil)
    
    push_frame_expr1, frame1_ret_value, frame1_stmts = arg1
    push_frame_expr2, frame2_ret_value, frame2_stmts = arg2

    if (frame1_ret_value != nil || frame2_ret_value != nil) &&
        frame1_ret_value.respond_to?(:adsl_ast) && frame1_ret_value.adsl_ast.class.is_expr? &&
        frame2_ret_value.respond_to?(:adsl_ast) && frame2_ret_value.adsl_ast.class.is_expr? &&
        !frame1_ret_value.adsl_ast.expr_has_side_effects? && !frame2_ret_value.adsl_ast.expr_has_side_effects?
     
      result_type = if frame1_ret_value.nil?
        frame2_ret_value.class
      elsif frame2_ret_value.nil?
        frame1_ret_value.class
      elsif frame1_ret_value.class <= frame2_ret_value.class
        frame2_ret_value.class
      elsif frame2_ret_value.class <= frame1_ret_value.class
        frame1_ret_value.class
      else
        nil 
      end

      if result_type
        if result_type < ActiveRecord::Base
          block1 = ::ADSL::Parser::ASTBlock.new :statements => frame1_stmts
          block2 = ::ADSL::Parser::ASTBlock.new :statements => frame2_stmts
          if_stmt = ::ADSL::Parser::ASTIf.new :condition => condition_ast, :then_block => block1, :else_block => block2

          frame1_stmts.pop
          frame2_stmts.pop
          ins_stmt if_stmt
          return result_type.new(:adsl_ast => ::ADSL::Parser::ASTIfExpr.new(
            :if => if_stmt,
            :then_expr => frame1_ret_value.adsl_ast,
            :else_expr => frame2_ret_value.adsl_ast
          ))
        elsif result_type.respond_to? :ds_type
          return ADSL::Extract::Rails::UnknownOfBasicType.new result_type.ds_type
        end
      end
    end

    block1 = ::ADSL::Parser::ASTBlock.new :statements => frame1_stmts
    block2 = ::ADSL::Parser::ASTBlock.new :statements => frame2_stmts
    if_stmt = ::ADSL::Parser::ASTIf.new :condition => condition_ast, :then_block => block1, :else_block => block2

    ins_stmt if_stmt
    return nil
  end
end


