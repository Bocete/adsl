require 'adsl/util/test_helper'
require 'adsl/lang/parser/adsl_parser.tab'
require 'adsl/ds/data_store_spec'

module ADSL::Lang
  module Parser
    class ActionParserTest < ActiveSupport::TestCase
      include ADSL::DS
  
      def test_action__empty
        parser = ADSLParser.new
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse ""
        end
        assert_equal([], spec.actions)
      end
  
      def test_action__no_stmts
        parser = ADSLParser.new
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            action do_something {
            }
          adsl
        end
        assert_equal 1, spec.actions.length
        assert_equal 0, spec.actions.first.block.statements.length
        assert_equal "do_something", spec.actions.first.name
      end
  
      def test_action__vars_are_stored
        parser = ADSLParser.new
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Class {}
            action do_something {
              var = allof(Class)
              var = var
            }
          adsl
        end
        assert_equal 1, spec.actions.length
        action = spec.actions.first
        assert_equal 2, action.statements.length
        var1 = action.statements.first.var
        assert_equal var1, action.statements.last.expr.variable
        var2 = action.statements.last.var
        assert var1 != var2
      end
  
      def test_action__all_stmts_no_subblocks
        parser = ADSLParser.new
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Class { 0+ Class relation }
            action do_something {
              var = create(Class)
              create(Class)
              delete var
              var.relation += var
              var.relation -= var
            }
          adsl
        end
        assert_equal 1, spec.actions.length
        assert_equal 'do_something', spec.actions.first.name
        statements = spec.actions.first.block.statements
        assert_equal 6, statements.length
        relation = spec.classes.first.members.first
        
        assert_equal spec.classes.first, statements[0].klass
  
        var = statements[1].var
        assert !var.nil?
        assert_equal 'var', var.name
        
        assert_equal spec.classes.first, statements[2].klass
        
        assert_equal var, statements[3].objset.variable
  
        assert_equal var, statements[4].objset1.variable
        assert_equal var, statements[4].objset2.variable
        assert_equal relation, statements[4].relation
     
        assert_equal var, statements[5].objset1.variable
        assert_equal var, statements[5].objset2.variable
        assert_equal relation, statements[5].relation
      end
  
      def test_action__multiple_creates_in_single_stmt
        parser = ADSLParser.new
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Class { 0+ Class relation}
            action do_something {
              create(Class).relation += create(Class)
            }
          adsl
        end
        statements = spec.actions.first.block.statements
        assert_equal 3, statements.length
        assert_equal spec.classes.first, statements[0].klass
        assert_equal spec.classes.first, statements[1].klass
      end
      
      def test_action__createtup_deletetup_typecheck
        ['+=', '-='].each do |operator|
          parser = ADSLParser.new
          spec = nil
          assert_nothing_raised ADSLError do
            spec = parser.parse <<-adsl
              class Class { 1 Class rel }
              action blah {
                allof(Class).rel #{operator} allof(Class)
              }
            adsl
          end
          stmt = spec.actions.first.block.statements.first
          assert_equal spec.classes.first, stmt.objset1.klass
          assert_equal spec.classes.first, stmt.objset2.klass
          assert_equal spec.classes.first.members.first, stmt.relation
          
          assert_raises ADSLError do
            parser.parse <<-adsl
              class Class1 { 1 Class1 rel }
              class Class2 {}
              action blah {
                allof(Class2).rel #{operator} allof(Class1)
              }
            adsl
          end
          
          assert_raises ADSLError do
            parser.parse <<-adsl
              class Class1 { 1 Class1 rel }
              class Class2 {}
              action blah {
                allof(Class1).rel #{operator} allof(Class2)
              }
            adsl
          end
        end
      end
      
      def test_action__superclass_createtup_deletetup_typecheck
        parser = ADSLParser.new
        ['+=', '-='].each do |operator|
          spec = nil
          assert_nothing_raised ADSLError do
            spec = parser.parse <<-adsl
              class Super { 1 Super rel }
              class Sub extends Super {}
              action blah {
                allof(Super).rel #{operator} allof(Sub)
              }
            adsl
          end
          stmt = spec.actions.first.block.statements.first
          assert_equal spec.classes[0], stmt.objset1.klass
          assert_equal spec.classes[1], stmt.objset2.klass
          assert_equal spec.classes[0].members.first, stmt.relation
          
          assert_nothing_raised ADSLError do
            spec = parser.parse <<-adsl
              class Super { 1 Super rel }
              class Sub extends Super {}
              action blah {
                allof(Sub).rel #{operator} allof(Sub)
              }
            adsl
          end
          stmt = spec.actions.first.block.statements.first
          assert_equal spec.classes[1], stmt.objset1.klass
          assert_equal spec.classes[1], stmt.objset2.klass
          assert_equal spec.classes[0].members.first, stmt.relation
          
          assert_nothing_raised ADSLError do
            spec = parser.parse <<-adsl
              class Super {}
              class Sub extends Super { 1 Super rel }
              action blah {
                allof(Sub).rel #{operator} allof(Sub)
              }
            adsl
          end
          stmt = spec.actions.first.block.statements.first
          assert_equal spec.classes[1], stmt.objset1.klass
          assert_equal spec.classes[1], stmt.objset2.klass
          assert_equal spec.classes[1].members.first, stmt.relation
  
          assert_raises ADSLError do
            parser.parse <<-adsl
              class Super {}
              class Sub extends Super { 1 Sub rel }
              action blah {
                allof(Super).rel #{operator} allof(Super)
              }
            adsl
          end
          
          assert_raises ADSLError do
            parser.parse <<-adsl
              class Super {}
              class Sub extends Super { 1 Sub rel }
              action blah {
                allof(Sub).rel #{operator} allof(Super)
              }
            adsl
          end
        end
      end
  
      def test_action__superclass_settup_typecheck
        parser = ADSLParser.new
          
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Super { 1 Super rel }
            class Sub extends Super {}
            action blah {
              allof(Super).rel = allof(Sub)
            }
          adsl
        end
        stmt1 = spec.actions.first.block.statements.first
        stmt2 = spec.actions.first.block.statements.last
        assert_equal spec.classes[0], stmt1.objset1.klass
        assert_equal spec.classes[0], stmt1.objset2.klass
        assert_equal spec.classes[0].members.first, stmt1.relation
        assert_equal spec.classes[0], stmt2.objset1.klass
        assert_equal spec.classes[1], stmt2.objset2.klass
        assert_equal spec.classes[0].members.first, stmt2.relation
        
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Super { 1 Super rel }
            class Sub extends Super {}
            action blah {
              allof(Sub).rel = allof(Sub)
            }
          adsl
        end
        stmt1 = spec.actions.first.block.statements.first
        stmt2 = spec.actions.first.block.statements.last
        assert_equal spec.classes[1], stmt1.objset1.klass
        assert_equal spec.classes[0], stmt1.objset2.klass
        assert_equal spec.classes[0].members.first, stmt1.relation
        assert_equal spec.classes[1], stmt2.objset1.klass
        assert_equal spec.classes[1], stmt2.objset2.klass
        assert_equal spec.classes[0].members.first, stmt2.relation
        
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Super {}
            class Sub extends Super { 1 Super rel }
            action blah {
              allof(Sub).rel = allof(Sub)
            }
          adsl
        end
        stmt1 = spec.actions.first.block.statements.first
        stmt2 = spec.actions.first.block.statements.last
        assert_equal spec.classes[1], stmt1.objset1.klass
        assert_equal spec.classes[0], stmt1.objset2.klass
        assert_equal spec.classes[1].members.first, stmt1.relation
        assert_equal spec.classes[1], stmt2.objset1.klass
        assert_equal spec.classes[1], stmt2.objset2.klass
        assert_equal spec.classes[1].members.first, stmt2.relation
  
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Super {}
            class Sub extends Super { 1 Sub rel }
            action blah {
              allof(Super).rel = allof(Super)
            }
          adsl
        end
        
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Super {}
            class Sub extends Super { 1 Sub rel }
            action blah {
              allof(Sub).rel = allof(Super)
            }
          adsl
        end
      end
  
      def test_action__ssa_by_default
        parser = ADSLParser.new
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Class {}
            action do_something {
              var1 = allof(Class)
              var1 = var1
            }
          adsl
        end
  
        action = spec.actions.first
        var1, var2 = action.statements.map(&:var)
        
        assert var1 != var2
        assert var1 == action.statements.last.expr.variable
      end
  
      def test_action__allof_typecheck
        parser = ADSLParser.new
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Class { 0+ Class relation }
            action do_something {
              var = allof(Class)
              var.relation -= var
            }
          adsl
        end
  
        assert_equal 1, spec.actions.length
        klass = spec.classes.first
        relation = spec.classes.first.members.first
  
        assert_equal relation, spec.actions.first.block.statements.last.relation
        
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Class { 0+ Class relation }
            class Class2 {}
            action do_something {
              var1 = allof(Class)
              var2 = allof(Class2)
              var1.relation -= var2
            }
          adsl
        end
      end
  
      def test_action__subset_typecheck
        parser = ADSLParser.new
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Class { 0+ Class relation }
            action do_something {
              var = subset(allof(Class))
              var.relation -= var
            }
          adsl
        end
  
        assert_equal 1, spec.actions.length
        klass = spec.classes.first
        relation = spec.classes.first.members.first
  
        assert_equal relation, spec.actions.first.block.statements.last.relation
        
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Class { 0+ Class relation }
            class Class2 {}
            action do_something {
              var1 = allof Class
              var2 = subset Class2
              var1.relation -= var2
            }
          adsl
        end
      end
      
      def test_action__oneof_typecheck
        [:oneof, :tryoneof].each do |op|
          parser = ADSLParser.new
          spec = nil
          assert_nothing_raised ADSLError do
            spec = parser.parse <<-adsl
              class Class { 0+ Class relation }
              action do_something {
                var = #{ op }(allof(Class))
                var.relation -= var
              }
            adsl
          end
  
          assert_equal 1, spec.actions.length
          klass = spec.classes.first
          relation = spec.classes.first.members.first
  
          assert_equal relation, spec.actions.first.block.statements.last.relation
          
          assert_raises ADSLError do
            parser.parse <<-adsl
              class Class { 0+ Class relation }
              class Class2 {}
              action do_something {
                var1 = allof(Class)
                var2 = #{ op }(allof(Class2))
                var1.relation -= var2
              }
            adsl
          end
        end
      end
  
      def test_action__deref_typecheck
        parser = ADSLParser.new
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Class1 { 0+ Class2 relation }
            class Class2 { 0+ Class2 other_relation }
            action do_something {
              allof(Class1).relation.other_relation -= allof(Class2)
            }
          adsl
        end
  
        assert_equal 1, spec.actions.length
        klass2 = spec.classes.last
        relation = klass2.members.first
  
        stmt = spec.actions.first.block.statements.last
        assert_equal klass2.to_sig, stmt.objset1.type_sig
        assert_equal relation, stmt.relation
        
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Class1 { 0+ Class2 relation }
            class Class2 { 0+ Class2 other_relation }
            action do_something {
              allof(Class1).relation.relation -= allof(Class2)
            }
          adsl
        end
      end 
      
      def test_action__deref_superclass_typecheck
        parser = ADSLParser.new
        spec = nil
  
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Class1 { 0+ Class2 relation }
            class Class2 extends Class1 { 0+ Class2 other_relation }
            action do_something {
              allof(Class1).relation.other_relation -= allof(Class2)
            }
          adsl
        end
        klass2 = spec.classes.last
        relation = klass2.members.first
        stmt = spec.actions.first.block.statements.last
        assert_equal klass2.to_sig, stmt.objset1.type_sig
        assert_equal relation, stmt.relation
        
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Class1 { 0+ Class2 relation }
            class Class2 extends Class1 { 0+ Class2 other_relation }
            action do_something {
              allof(Class2).relation.other_relation -= allof(Class2)
            }
          adsl
        end
        klass2 = spec.classes.last
        relation = klass2.members.first
        stmt = spec.actions.first.block.statements.last
        assert_equal klass2.to_sig, stmt.objset1.type_sig
        assert_equal relation, stmt.relation
      end 
      
      def test_action__subblocks
        parser = ADSLParser.new
        spec = parser.parse <<-adsl
          class Class { 0+ Class relation }
          action do_something {
            var = allof Class
            foreach subvar: var
              var.relation -= subvar
            if *
              delete var
            else
              create Class
            foreach subvar: var {}
          }
        adsl
        
        assert_equal 1, spec.actions.length
        stmts = spec.actions.first.block.statements
        var = stmts[0].var
        klass = spec.classes.first
        
        assert_equal var, stmts[1].objset.variable
  
        assert_equal var, stmts[2].then_block.statements.first.objset.variable
  
        assert_equal klass, stmts[2].else_block.statements.first.klass
      end
  
      def test_action__subblocks_dont_undefine_variables
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            class Class {}
            action do_something {
              var = allof(Class)
              if * {
                var = allof(Class)
              }
              var = var
            }
          adsl
        end
      end
  
      def test_action__types_are_static
        parser = ADSLParser.new
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Class {}
            class Class2 {}
            action do_something {
              var = allof(Class)
              var = allof(Class2)
            }
          adsl
        end 
      end
  
      def test_action__if_elsif_else__combinations
        parser = ADSLParser.new
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Class {}
            action do_something {
              if *
            }
          adsl
        end
        spec = parser.parse <<-adsl
          class Class {}
          action do_something {
            if *
              create(Class)
          }
        adsl
        iff = spec.actions.first.block.statements.first
        assert_equal 0, iff.else_block.statements.length
        assert_equal 1, iff.then_block.statements.length
  
        spec = parser.parse <<-adsl
          class Class {}
          action do_something {
            if * {
            } elsif *
              create(Class)
            else {
              create(Class)
              create(Class)
            }
          }
        adsl
        iff = spec.actions.first.block.statements.first
        assert_equal 0, iff.then_block.statements.length
        assert_equal 1, iff.else_block.statements.length
        assert_equal DSIf, iff.else_block.statements.first.class

        subiff = iff.else_block.statements.first
        assert_equal 1, subiff.then_block.statements.length
        assert_equal 2, subiff.else_block.statements.length
      end
  
      def test_action__unmatching_types_in_either
        parser = ADSLParser.new
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Class {}
            class Class2 {}
            action do_something {
              var = allof(Class)
              if *
                var = allof(Class)
              else
                var = allof(Class2)
            }
          adsl
        end
      end
  
      def test_action__unmatching_types_in_either_but_inside
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            class Class {}
            class Class2 {}
            action do_something {
              if *
                var = allof(Class2)
              else
                var = allof(Class)
            }
          adsl
        end
      end
  
      def test_action__foreach_iterator_var_typecheck
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            class Class { 0+ Class relation }
            action do_something {
              foreach var: allof(Class)
                var.relation -= allof(Class)
            }
          adsl
        end
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Class {}
            class Class2 { 0+ Class2 relation }
            action do_something {
              foreach var: allof(Class)
                var.relation -= allof(Class)
            }
          adsl
        end
      end
  
      def test_action__foreach_does_not_redefine_var
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Class { 0+ Class relation }
            action do_something {
              var = subset Class
              foreach var: var {
              }
            }
          adsl
        end
      end
  
      def test_action__coex_for_each_is_by_default
        parser = ADSLParser.new
        spec = parser.parse <<-adsl
          class Class { 0+ Class relation }
          action do_something {
            foreach o: Class {
            }
          }
        adsl
        foreach = spec.actions.first.statements.first
        assert_equal DSForEach, foreach.class
        assert foreach.singleton_class.ancestors.include? DSForEach::Coex
      end
  
      def test_action__either_lambda_works
        parser = ADSLParser.new
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Class { 0+ Class relation }
            action do_something {
              var = allof Class
              if *
                var = subset var
              else
                var = subset var
              var = var
            }
          adsl
        end
  
        action = spec.actions.first
        statements = action.statements
  
        assert_equal 4, statements.length
        
        orig_def    = statements[0]
        inside_def1 = statements[1].then_block.statements.first
        inside_def2 = statements[1].else_block.statements.first
        lambda_def  = statements[2]
        final_def   = statements[3]
  
        assert_all_different(
          :orig_def    => orig_def.var,
          :inside_def1 => inside_def1.var,
          :inside_def2 => inside_def2.var,
          :lambda_def  => lambda_def.var,
          :final_def   => final_def.var
        )
  
        assert_equal lambda_def.expr.then_expr.variable, inside_def1.var
        assert_equal lambda_def.expr.else_expr.variable, inside_def2.var
      end
      
      def test_action__if_lambda_works
        parser = ADSLParser.new
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Class { 0+ Class relation }
            action do_something {
              var = allof Class
              if isempty(var)
                var = subset(var)
              else
                var = empty
              var = var
            }
          adsl
        end
  
        action = spec.actions.first
        statements = action.statements
  
        assert_equal 4, statements.length
        
        orig_def   = statements[0]
        then_def   = statements[1].then_block.statements.first
        else_def   = statements[1].else_block.statements.first
        lambda_def = statements[2]
        final_def  = statements[3]
  
        assert_all_different(
          :orig_def   => orig_def.var,
          :then_def   => then_def.var,
          :else_def   => else_def.var,
          :lambda_def => lambda_def.var,
          :final_def  => final_def.var
        )
  
        assert_equal lambda_def.expr.then_expr.variable, then_def.var
        assert_equal lambda_def.expr.else_expr.variable, else_def.var
      end
  
      def test_action__if_condition_var_definition
        parser = ADSLParser.new
        spec = nil
        assert_raises ADSLError do
          spec = parser.parse <<-adsl
            class Class {}
            action blah {
              if isempty(var = allof(Class))
                a = var
              else
                b = var
              delete var
            }
          adsl
        end
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Class {}
            action blah {
              if isempty(var = allof(Class))
                a = var
              else 
                b = var
            }
          adsl
        end
  
        statements = spec.actions.first.block.statements
        
        assert_equal 2, statements.length
  
        assert_equal 'var', statements[0].var.name
        assert_equal 'var', statements[1].condition.objset.variable.name
      end
  
      def test_action__foreach_pre_lambda
        get_pre_lambdas = lambda do |for_each|
          for_each.block.statements.select do |stat|
            stat.kind_of?(DSAssignment) and stat.expr.kind_of?(DSForEachPreLambdaExpr)
          end
        end
  
        parser = ADSLParser.new
        spec = parser.parse <<-adsl
          class Class {}
          action do_something {
            foreach var: allof(Class) {}
          }
        adsl
        assert_equal 0, get_pre_lambdas.call(spec.actions.first.block.statements[0]).length
  
        spec = parser.parse <<-adsl
          class Class {}
          action do_something {
            foreach var: allof(Class)
              var = allof(Class)
          }
        adsl
        assert_equal 0, get_pre_lambdas.call(spec.actions.first.block.statements[0]).length
  
        spec = parser.parse <<-adsl
          class Class {}
          action do_something {
            var = allof Class
            foreach a: Class {
              var = subset(var)
              var = subset(var)
            }
          }
        adsl
        pre_lambdas = get_pre_lambdas.call(spec.actions.first.block.statements[1])
        assert_equal 1, pre_lambdas.length
        assert_equal spec.actions.first.block.statements[0].var, pre_lambdas.first.expr.before_var
        assert_equal spec.actions.first.block.statements[1],     pre_lambdas.first.expr.for_each
        assert_equal spec.actions.first.block.statements[1].block.statements.last.var, pre_lambdas.first.expr.inside_var
  
        spec = parser.parse <<-adsl
          class Class {}
          action do_something {
            var = allof Class
            foreach var: Class
              var = allof Class
          }
        adsl
        assert_equal 0, get_pre_lambdas.call(spec.actions.first.block.statements[1]).length
      end
  
      def test_action__empty_set__typecheck
        parser = ADSLParser.new
        
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            class Class {
              1 Class klass
            }
            class Class2 {
              1 Class2 klass2
            }
            action do_something {
              allof(Class).klass += empty
              allof(Class2).klass2 += empty
            }
          adsl
        end
  
        assert_raises ADSLError do
          parser.parse <<-adsl
            action do_something {
              empty.some_relation += empty
            }
          adsl
        end
        
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            class Class {
              1 Class klass
            }
            action do_something {
              c = empty 
              allof(Class).klass += c
            }
          adsl
        end
        
        assert_raises ADSLError do
          parser.parse <<-adsl
            class Class {
              1 Class klass
            }
            action do_something {
              c = empty
              c.klass += allof(Class)
            }
          adsl
        end
      end
  
      def test_action__empty_set_and_var_types
        parser = ADSLParser.new
  
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            class Class {
              1 Class klass
            }
            action do_something {
              a = empty
              a = allof Class
              a.klass += a
            }
          adsl
        end
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            class Class {
              1 Class klass
            }
            action do_something {
              a = empty
              a = allof Class
              a.klass += a
            }
          adsl
        end
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            class Class {
              1 Class klass
            }
            action do_something {
              a = allof Class
              a = empty
              a.klass += a
            }
          adsl
        end
        assert_nothing_raised ADSLError do
          parser.parse <<-adsl
            class Class {
              1 Class klass
            }
            action do_something {
              a = allof Class
              a = empty
              b = a
              b.klass += a
            }
          adsl
        end
      end
  
      def test_action__nested_assignments
        parser = ADSLParser.new
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-ADSL
            class Class {}
            action blah {
              a = b = create Class
              delete a
              delete b
            }
          ADSL
        end
  
        klass = spec.classes.first
        statements = spec.actions.first.block.statements
  
        assert_equal 5, statements.length
  
        assert_equal klass, statements[0].klass
        assert_equal 'b',   statements[1].var.name
        assert_equal 'a',   statements[2].var.name
        assert_equal 'b',   statements[2].expr.variable.name
        assert_equal 'a',   statements[3].objset.variable.name
        assert_equal 'b',   statements[4].objset.variable.name
      end
  
      def test_action__conditional_branches
        parser = ADSLParser.new
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-ADSL
            class Class {}
            action blah {
              if isempty Class
                delete allof Class
              if isempty Class {
              } else
                delete allof(Class)
            }
          ADSL
        end
  
        klass = spec.classes.first
        statements = spec.actions.first.block.statements
        
        assert_equal 2, statements.length
  
        assert_equal 1, statements[0].then_block.statements.length
        assert_equal 0, statements[0].else_block.statements.length
        
        assert_equal 0, statements[1].then_block.statements.length
        assert_equal 1, statements[1].else_block.statements.length
      end
  
      def test_action__force_loop_flatness
        parser = ADSLParser.new
        spec = nil
  
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-ADSL
            class Class {}
            action blah {
              flatforeach a: Class {
              }
            }
          ADSL
        end
        foreach = spec.actions.first.block.statements.first
        assert foreach.is_a? DSForEach 
        assert foreach.singleton_class.ancestors.include? DSForEach::Coex
  
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-ADSL
            class Class {}
            action blah {
              unflatforeach a: Class {
              }
            }
          ADSL
        end
        foreach = spec.actions.first.block.statements.first
        assert foreach.is_a? DSForEach
        assert foreach.singleton_class.ancestors.include? DSForEach::Seq
        
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-ADSL
            class Class {}
            action blah {
              foreach a: Class {
              }
            }
          ADSL
        end
        foreach = spec.actions.first.block.statements.first
        assert foreach.is_a? DSForEach 
        assert foreach.singleton_class.ancestors.include? DSForEach::Coex
      end

      def test_action__returns_in_ret_block
        parser = ADSLParser.new
        spec = nil
        
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-ADSL
            class Class {}
            action blah {
              at__a = returnguard {
                return oneof Class
              }
            }
          ADSL
        end
        assignment = spec.actions.first.statements.first
        assert_equal DSAssignment, assignment.class
        assert_equal DSOneOf,      assignment.expr.class
      end

      def test_action__ret_block_forces_return
        parser = ADSLParser.new
        spec = nil
        
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-ADSL
            class Class {}
            action blah {
              a = returnguard {
                oneof Class
              }
            }
          ADSL
        end
        assignment = spec.actions.first.statements.first
        assert_equal DSAssignment, assignment.class
        assert_equal DSOneOf,      assignment.expr.class
      end

      def test_action__flatten_returns
        parser = ADSLParser.new
        spec = nil

        assert_nothing_raised do
          spec = parser.parse <<-adsl
            class Class {}
            action blah {
              at__a = returnguard{
                if isempty Class
                  return create Class
                b = tryoneof Class
                if isempty b
                  empty
                else
                  b
              }
            }
          adsl
        end

        # above code is expected to be parsed as
        # class Class {}
        # action blah {
        #   at__a = {
        #     if isempty Class
        #       create Class
        #     else {
        #       b = tryoneof Class
        #       if isempty b
        #         empty
        #       else
        #         b
        #     }
        #   }
        # }

        assert_equal 2, spec.actions.first.statements.length
        root_if = spec.actions.first.statements.first
        
        assert_equal DSIf,           root_if.class
        assert_equal DSIsEmpty,      root_if.condition.class
        assert_equal 1,              root_if.then_block.statements.length
        assert_equal DSCreateObj,    root_if.then_block.statements.first.class
        assert_equal 2,              root_if.else_block.statements.length
        assert_equal DSAssignment,   root_if.else_block.statements[0].class
        assert_equal DSIf,           root_if.else_block.statements[1].class
        assert_equal DSIsEmpty,      root_if.else_block.statements[1].condition.class
        assert                       root_if.else_block.statements[1].then_block.statements.empty?
        assert                       root_if.else_block.statements[1].else_block.statements.empty?

        root_assignment = spec.actions.first.statements.second
        assert_equal DSAssignment,   root_assignment.class
        assert_equal DSIfLambdaExpr, root_assignment.expr.class
        assert_equal root_if,        root_assignment.expr.if
      end

      def test__instance_variables_not_removed
        parser = ADSLParser.new
        spec = nil
        
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-ADSL
            class Class {}
            action blah {
              at__a = oneof Class
            }
          ADSL
        end
        assignment = spec.actions.first.statements.first
        assert_equal DSAssignment, assignment.class
        assert_equal DSOneOf,      assignment.expr.class
      end

      def test__foreach_does_not_destroy_variable_scoping
        parser = ADSLParser.new
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-ADSL
            class Class {}
            action blah {
              var = oneof Class
              foreach a: var {}
              delete var
            }
          ADSL
        end
      end

    end
  end
end

