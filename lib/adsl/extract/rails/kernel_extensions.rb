require 'adsl/extract/instrumenter'
require 'adsl/extract/rails/action_instrumenter'
require 'adsl/extract/rails/basic_type_extensions'
require 'adsl/extract/rails/method'
require 'adsl/lang/ast_nodes'

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
        result_type = result.respond_to?(:ds_type) ? result.ds_type : result
        return ADSL::Extract::Rails::UnknownOfBasicType.new result_type
      end
    end
    old_ins_call object, method_name, *args, &block
  end

  def ins_block(*exprs)
    adsl_asts = exprs.flatten.map{ |e| e.respond_to?(:adsl_ast) ? e.adsl_ast : e }.flatten.select{ |e| e.is_a? ::ADSL::Lang::ASTNode }

    if adsl_asts.any?
      block = adsl_asts.length == 1 ? adsl_asts.first : ::ADSL::Lang::ASTBlock.new(:exprs => adsl_asts)
      if exprs.last.is_a?(ActiveRecord::Base)
        exprs.last.class.new :adsl_ast => block
      else
        block
      end
    else
      exprs.last
    end
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

      value_adsl_ast = value.try_adsl_ast
      
      if value_adsl_ast and !value_adsl_ast.is_a?(::ADSL::Lang::ASTBoolean)
        if operator == '||='
          old_value = outer_binding.eval name rescue nil
          
          # sometimes ||= is used on a variable that doesn't exist before
          if old_value.nil?
            old_value_adsl_ast = ::ADSL::Lang::ASTVariableRead.new(:var_name => ::ADSL::Lang::ASTIdent[adsl_ast_name])
          else
            old_value_adsl_ast = old_value.try_adsl_ast
          end
          
          if old_value_adsl_ast
            value_adsl_ast = ::ADSL::Lang::ASTIf.new(
              :condition => ::ADSL::Lang::ASTIsEmpty.new(:objset => old_value_adsl_ast),
              :then_expr => value_adsl_ast,
              :else_expr => old_value_adsl_ast
            )
          end
        end
        assignment = ::ADSL::Lang::ASTAssignment.new(
          :var_name => ::ADSL::Lang::ASTIdent[adsl_ast_name],
          :expr => value_adsl_ast
        )

        if value.is_a?(ActiveRecord::Base)
          new_value_type = value.class
        else
          old_value = outer_binding.eval("#{name}")# && old_value.is_a?(ActiveRecord::Base)
          new_value_type = old_value.class if old_value.is_a? ActiveRecord::Base
        end
        
        new_value = new_value_type.nil? ? value : new_value_type.new(
          :adsl_ast => ::ADSL::Lang::ASTVariableRead.new(:var_name => ::ADSL::Lang::ASTIdent[adsl_ast_name]
        ))
        outer_binding.eval "#{name} #{operator} ObjectSpace._id2ref(#{new_value.object_id})"

        assignment = value.class.new :adsl_ast => assignment if value.is_a?(ActiveRecord::Base)
        values_to_be_returned << assignment
        # 
        # values_to_be_returned << new_value
      else
        outer_binding.eval "#{name} #{operator} ObjectSpace._id2ref(#{value.object_id})"
        values_to_be_returned << value
      end
    end
    names.length == 1 ? values_to_be_returned.first : values_to_be_returned
  end

  def ins_do_return(return_value = nil)
    instrumenter = ::ADSL::Extract::Instrumenter.get_instance

    instrumenter.ex_method.report_return_type return_value.class

    return_values = [return_value].flatten
    if return_values.length == 1
      ::ADSL::Lang::ASTReturn.new :expr => return_value.try_adsl_ast
    else
      ::ADSL::Lang::ASTBlock.new :exprs => return_values.map(&:try_adsl_ast) + [::ADSL::Lang::ASTReturn.new(:expr => nil.adsl_ast)]
    end
  end

  def ins_do_raise(*args)
    if TEST_ENV && args.any?
      pp args
      puts caller
    end
    ::ADSL::Lang::ASTRaise.new
  end

  def ins_do_render
    instrumenter = ::ADSL::Extract::Instrumenter.get_instance
    if instrumenter.action_name.to_s == instrumenter.ex_method.name.to_s
      ::ADSL::Lang::ASTFlag.new(:label => :render)
    else
      # we're rendering from outside the action.  Presumably, from a filter that's aborting the action
      ins_do_raise
    end
  end

  def ins_explore_all(method_name, &block)
    instrumenter = ::ADSL::Extract::Instrumenter.get_instance
    old_method = instrumenter.ex_method
    method = ::ADSL::Extract::Rails::Method.new :name => method_name, :action_or_callback => old_method.name == :root
    instrumenter.ex_method = method

    return_val = method.extract_from &block
    method.report_return_type return_val.class

    adsl_ast = return_val.try_adsl_ast
    adsl_ast = ::ADSL::Lang::ASTReturnGuard.new :expr => adsl_ast if adsl_ast.is_a? ::ADSL::Lang::ASTNode

    if old_method.is_root_level?
      old_method.root_block.exprs << adsl_ast if adsl_ast.is_a? ::ADSL::Lang::ASTNode
      old_method.root_block.exprs << ::ADSL::Lang::ASTFlag.new(:label => method_name)
    else
      return_type = method.return_type
      if return_type
        return_val = return_type.new :adsl_ast => adsl_ast
      elsif return_val.is_a?(::ADSL::Lang::ASTNode) && adsl_ast.is_a?(::ADSL::Lang::ASTNode)
        return_val = adsl_ast unless return_val.noop? && adsl_ast.noop?
      end
    end

    return return_val
  rescue Exception => e
    if TEST_ENV
      pp e.message
      puts e.backtrace
      raise e
    #else
    #  return ins_do_raise(e.message)
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

  def ins_try(obj, method, *args, &block)
    if obj.is_a? ActiveRecord::Base
      adsl_ast = obj.adsl_ast

      return obj.send method, *args, &block if adsl_ast.evals_to_something_always?

      @@counter ||= 0
      var_name = "somelonganduniquevariablename#{ @@counter += 1 }"
      assignment = ADSL::Lang::ASTAssignment.new :var_name => ADSL::Lang::ASTIdent[var_name], :expr => obj.adsl_ast
      condition = ADSL::Lang::ASTNot.new(:subformula => ADSL::Lang::ASTIsEmpty.new(:objset => assignment))
      obj = obj.class.new :adsl_ast => ADSL::Lang::ASTVariableRead.new(:var_name => ADSL::Lang::ASTIdent[var_name])
    else
      condition = ADSL::Lang::ASTBoolean.new
    end

    result_unless_nil = obj.send method, *args, &block

    ins_if condition, result_unless_nil, nil
  end

  def ins_if(condition, then_expr, else_expr)
    if condition.is_a?(ActiveRecord::Base) || condition.nil?
      adsl_ast = condition.adsl_ast
      if !adsl_ast.evals_to_something?
        condition_ast = ADSL::Lang::ASTBoolean::FALSE
      elsif adsl_ast.evals_to_something_always?
        condition_ast = ADSL::Lang::ASTBoolean::TRUE
      else
        condition_ast = ADSL::Lang::ASTNot.new(:subformula => ADSL::Lang::ASTIsEmpty.new(:objset => condition.adsl_ast))
      end
    elsif condition.is_a?(ADSL::Lang::ASTNode)
      condition_ast = condition
    else 
      condition_ast = ADSL::Lang::ASTBoolean.new
    end
    then_ast = then_expr.try_adsl_ast
    else_ast = else_expr.try_adsl_ast

    iff = ::ADSL::Lang::ASTIf.new :condition => condition_ast, :then_expr => then_ast, :else_expr => else_ast

    classes = [then_expr, else_expr].map(&:class).select{ |c| c < ActiveRecord::Base }.uniq
    if classes.length == 1
      iff = classes.first.new :adsl_ast => iff
    end

    iff
  end
end


