require 'adsl/parser/adsl_parser.tab'
require 'adsl/ds/data_store_spec'
require 'test/unit'
require 'pp'

module ADSL::Parser
  class ActionParserTest < Test::Unit::TestCase
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
          action do_something() {
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
          action do_something() {
            var = allof(Class)
            var = var
          }
        adsl
      end
      assert_equal 1, spec.actions.length
      assert_equal 2, spec.actions.first.block.statements.length
      var1 = spec.actions.first.statements.first.var
      assert_equal var1, spec.actions.first.statements.last.objset
      var2 = spec.actions.first.statements.last.var
      assert var1 != var2
    end

    def test_action__context_difference
      context1 = ASTTypecheckResolveContext.new
      context1.push_frame

      klass = DSClass.new :name => 'klass'
      sig = DSTypeSig.new klass

      a1 = DSVariable.new :name => 'a', :type_sig => sig
      a2 = DSVariable.new :name => 'a', :type_sig => sig
      b1 = DSVariable.new :name => 'b', :type_sig => sig
      b2 = DSVariable.new :name => 'b', :type_sig => sig

      context1.define_var a1, true
      context1.define_var b1, true

      context2 = context1.dup

      context2.redefine_var a2, false

      assert_equal({"a" => [a1, a2]}, ASTTypecheckResolveContext.context_vars_that_differ(context1, context2))

      context3 = context2.dup
      assert_equal({"a" => [a1, a2, a2]}, ASTTypecheckResolveContext.context_vars_that_differ(context1, context2, context3))

      context3.redefine_var b2, false
      assert_equal({"a" => [a1, a2, a2], "b" => [b1, b1, b2]}, ASTTypecheckResolveContext.context_vars_that_differ(context1, context2, context3))
    end

    def test_action__all_stmts_no_subblocks
      parser = ADSLParser.new
      spec = nil
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class { 0+ Class relation }
          action do_something() {
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
      relation = spec.classes.first.relations.first
      
      assert_equal spec.classes.first, statements[0].klass

      var = statements[1].var
      assert !var.nil?
      assert_equal 'var', var.name
      
      assert_equal spec.classes.first, statements[2].klass
      
      assert_equal var, statements[3].objset

      assert_equal var, statements[4].objset1
      assert_equal var, statements[4].objset2
      assert_equal relation, statements[4].relation
   
      assert_equal var, statements[5].objset1
      assert_equal var, statements[5].objset2
      assert_equal relation, statements[5].relation
    end

    def test_action__multiple_creates_in_single_stmt
      parser = ADSLParser.new
      spec = nil
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class { 0+ Class relation}
          action do_something() {
            create(Class).relation += create(Class)
          }
        adsl
      end
      statements = spec.actions.first.block.statements
      assert_equal 3, statements.length
      assert_equal spec.classes.first, statements[0].klass
      assert_equal spec.classes.first, statements[1].klass
    end

    def test_action__args_typecheck
      parser = ADSLParser.new
      spec = nil
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class {}
          action do_something(0+ Class var1) {
            var2 = var1
          }
        adsl
      end
      
      klass = spec.classes.first
      var1 = spec.actions.first.args.first
      var2 = spec.actions.first.statements.first.var

      assert_equal Set[klass], klass.to_sig.classes
      assert_equal klass.to_sig, var1.type_sig
      assert_equal klass.to_sig, var2.type_sig
    end

    def test_action__args_multiple
      parser = ADSLParser.new
      spec = nil
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class1 {}
          class Class2 {}
          class Class3 {}
          action do_something(0..1 Class1 var1, 1 Class2 var2, 1+ Class3 var3) {
          }
        adsl
      end
      assert_equal ['var1', 'var2', 'var3'], spec.actions.first.args.map{ |v| v.name }
      assert_equal spec.classes.map(&:to_sig), spec.actions.first.args.map(&:type_sig)
      assert_equal [[0, 1], [1, 1], [1, 1.0/0.0]], spec.actions.first.cardinalities
    end
    
    def test_action__createtup_deletetup_typecheck
      ['+=', '-='].each do |operator|
        parser = ADSLParser.new
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Class { 1 Class rel }
            action blah() {
              allof(Class).rel #{operator} allof(Class)
            }
          adsl
        end
        stmt = spec.actions.first.block.statements.first
        assert_equal spec.classes.first, stmt.objset1.klass
        assert_equal spec.classes.first, stmt.objset2.klass
        assert_equal spec.classes.first.relations.first, stmt.relation
        
        assert_raise ADSLError do
          parser.parse <<-adsl
            class Class1 { 1 Class1 rel }
            class Class2 {}
            action blah() {
              allof(Class2).rel #{operator} allof(Class1)
            }
          adsl
        end
        
        assert_raise ADSLError do
          parser.parse <<-adsl
            class Class1 { 1 Class1 rel }
            class Class2 {}
            action blah() {
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
            action blah() {
              allof(Super).rel #{operator} allof(Sub)
            }
          adsl
        end
        stmt = spec.actions.first.block.statements.first
        assert_equal spec.classes[0], stmt.objset1.klass
        assert_equal spec.classes[1], stmt.objset2.klass
        assert_equal spec.classes[0].relations.first, stmt.relation
        
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Super { 1 Super rel }
            class Sub extends Super {}
            action blah() {
              allof(Sub).rel #{operator} allof(Sub)
            }
          adsl
        end
        stmt = spec.actions.first.block.statements.first
        assert_equal spec.classes[1], stmt.objset1.klass
        assert_equal spec.classes[1], stmt.objset2.klass
        assert_equal spec.classes[0].relations.first, stmt.relation
        
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Super {}
            class Sub extends Super { 1 Super rel }
            action blah() {
              allof(Sub).rel #{operator} allof(Sub)
            }
          adsl
        end
        stmt = spec.actions.first.block.statements.first
        assert_equal spec.classes[1], stmt.objset1.klass
        assert_equal spec.classes[1], stmt.objset2.klass
        assert_equal spec.classes[1].relations.first, stmt.relation

        assert_raise ADSLError do
          parser.parse <<-adsl
            class Super {}
            class Sub extends Super { 1 Sub rel }
            action blah() {
              allof(Super).rel #{operator} allof(Super)
            }
          adsl
        end
        
        assert_raise ADSLError do
          parser.parse <<-adsl
            class Super {}
            class Sub extends Super { 1 Sub rel }
            action blah() {
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
          action blah() {
            allof(Super).rel = allof(Sub)
          }
        adsl
      end
      stmt1 = spec.actions.first.block.statements.first
      stmt2 = spec.actions.first.block.statements.last
      assert_equal spec.classes[0], stmt1.objset1.klass
      assert_equal spec.classes[0], stmt1.objset2.klass
      assert_equal spec.classes[0].relations.first, stmt1.relation
      assert_equal spec.classes[0], stmt2.objset1.klass
      assert_equal spec.classes[1], stmt2.objset2.klass
      assert_equal spec.classes[0].relations.first, stmt2.relation
      
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Super { 1 Super rel }
          class Sub extends Super {}
          action blah() {
            allof(Sub).rel = allof(Sub)
          }
        adsl
      end
      stmt1 = spec.actions.first.block.statements.first
      stmt2 = spec.actions.first.block.statements.last
      assert_equal spec.classes[1], stmt1.objset1.klass
      assert_equal spec.classes[0], stmt1.objset2.klass
      assert_equal spec.classes[0].relations.first, stmt1.relation
      assert_equal spec.classes[1], stmt2.objset1.klass
      assert_equal spec.classes[1], stmt2.objset2.klass
      assert_equal spec.classes[0].relations.first, stmt2.relation
      
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Super {}
          class Sub extends Super { 1 Super rel }
          action blah() {
            allof(Sub).rel = allof(Sub)
          }
        adsl
      end
      stmt1 = spec.actions.first.block.statements.first
      stmt2 = spec.actions.first.block.statements.last
      assert_equal spec.classes[1], stmt1.objset1.klass
      assert_equal spec.classes[0], stmt1.objset2.klass
      assert_equal spec.classes[1].relations.first, stmt1.relation
      assert_equal spec.classes[1], stmt2.objset1.klass
      assert_equal spec.classes[1], stmt2.objset2.klass
      assert_equal spec.classes[1].relations.first, stmt2.relation

      assert_raise ADSLError do
        parser.parse <<-adsl
          class Super {}
          class Sub extends Super { 1 Sub rel }
          action blah() {
            allof(Super).rel = allof(Super)
          }
        adsl
      end
      
      assert_raise ADSLError do
        parser.parse <<-adsl
          class Super {}
          class Sub extends Super { 1 Sub rel }
          action blah() {
            allof(Sub).rel = allof(Super)
          }
        adsl
      end
    end

    def test_action__args_cardinality
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class {}
          action do_something(0..1 Class var1) {
          }
        adsl
        spec = parser.parse <<-adsl
          class Class {}
          action do_something(1 Class var1) {
          }
        adsl
        spec = parser.parse <<-adsl
          class Class {}
          action do_something(1..1 Class var1) {
          }
        adsl
        spec = parser.parse <<-adsl
          class Class {}
          action do_something(0+ Class var1) {
          }
        adsl
        spec = parser.parse <<-adsl
          class Class {}
          action do_something(1+ Class var1) {
          }
        adsl
      end
      assert_raise do
        parser.parse <<-adsl
          class Class{}
          action do_something(1..0)
        adsl
      end
      assert_raise do
        parser.parse <<-adsl
          class Class{}
          action do_something(0)
        adsl
      end
      assert_raise do
        parser.parse <<-adsl
          class Class{}
          action do_something(0..0)
        adsl
      end
    end

    def test_action__ssa_by_default
      parser = ADSLParser.new
      spec = nil
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class {}
          action do_something(0+ Class var1, 0+ Class var2) {
            var2 = var1
          }
        adsl
      end

      arg1 = spec.actions.first.args.first
      arg2 = spec.actions.first.args.last
      redefined = spec.actions.first.statements.first.var
      
      assert arg1 != arg2
      assert arg2 != redefined
    end

    def test_action__allof_typecheck
      parser = ADSLParser.new
      spec = nil
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class { 0+ Class relation }
          action do_something() {
            var = allof(Class)
            var.relation -= var
          }
        adsl
      end

      assert_equal 1, spec.actions.length
      klass = spec.classes.first
      relation = spec.classes.first.relations.first

      assert_equal relation, spec.actions.first.block.statements.last.relation
      
      assert_raise ADSLError do
        parser.parse <<-adsl
          class Class { 0+ Class relation }
          class Class2 {}
          action do_something() {
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
          action do_something() {
            var = subset(allof(Class))
            var.relation -= var
          }
        adsl
      end

      assert_equal 1, spec.actions.length
      klass = spec.classes.first
      relation = spec.classes.first.relations.first

      assert_equal relation, spec.actions.first.block.statements.last.relation
      
      assert_raise ADSLError do
        parser.parse <<-adsl
          class Class { 0+ Class relation }
          class Class2 {}
          action do_something() {
            var1 = allof(Class)
            var2 = subset(allof(Class2))
            var1.relation -= var2
          }
        adsl
      end
    end
    
    def test_action__oneof_typecheck
      [:oneof, :forceoneof].each do |op|
        parser = ADSLParser.new
        spec = nil
        assert_nothing_raised ADSLError do
          spec = parser.parse <<-adsl
            class Class { 0+ Class relation }
            action do_something() {
              var = #{ op }(allof(Class))
              var.relation -= var
            }
          adsl
        end

        assert_equal 1, spec.actions.length
        klass = spec.classes.first
        relation = spec.classes.first.relations.first

        assert_equal relation, spec.actions.first.block.statements.last.relation
        
        assert_raise ADSLError do
          parser.parse <<-adsl
            class Class { 0+ Class relation }
            class Class2 {}
            action do_something() {
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
          action do_something() {
            allof(Class1).relation.other_relation -= allof(Class2)
          }
        adsl
      end

      assert_equal 1, spec.actions.length
      klass2 = spec.classes.last
      relation = klass2.relations.first

      stmt = spec.actions.first.block.statements.last
      assert_equal klass2.to_sig, stmt.objset1.type_sig
      assert_equal relation, stmt.relation
      
      assert_raise ADSLError do
        parser.parse <<-adsl
          class Class1 { 0+ Class2 relation }
          class Class2 { 0+ Class2 other_relation }
          action do_something() {
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
          action do_something() {
            allof(Class1).relation.other_relation -= allof(Class2)
          }
        adsl
      end
      klass2 = spec.classes.last
      relation = klass2.relations.first
      stmt = spec.actions.first.block.statements.last
      assert_equal klass2.to_sig, stmt.objset1.type_sig
      assert_equal relation, stmt.relation
      
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class1 { 0+ Class2 relation }
          class Class2 extends Class1 { 0+ Class2 other_relation }
          action do_something() {
            allof(Class2).relation.other_relation -= allof(Class2)
          }
        adsl
      end
      klass2 = spec.classes.last
      relation = klass2.relations.first
      stmt = spec.actions.first.block.statements.last
      assert_equal klass2.to_sig, stmt.objset1.type_sig
      assert_equal relation, stmt.relation
    end 
    
    def test_action__subblocks
      parser = ADSLParser.new
      spec = parser.parse <<-adsl
        class Class { 0+ Class relation }
        action do_something() {
          var = allof(Class)
          foreach subvar: var {
            var.relation -= subvar
          }
          either {
            delete var
          } or {
            create(Class)
          }
          foreach subvar: var {}
        }
      adsl
      
      assert_equal 1, spec.actions.length
      stmts = spec.actions.first.block.statements
      var = stmts[0].var
      klass = spec.classes.first
      
      assert_equal var, stmts[1].objset

      assert_equal var, stmts[2].blocks[0].statements.first.objset

      assert_equal klass, stmts[2].blocks[1].statements.first.klass
    end

    def test_action__subblocks_dont_undefine_variables
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        parser.parse <<-adsl
          class Class {}
          action do_something() {
            var = allof(Class)
            either {
              var = allof(Class)
            } or {
            }
            var = var
          }
        adsl
      end
    end

    def test_action__types_are_static
      parser = ADSLParser.new
      assert_raise ADSLError do
        parser.parse <<-adsl
          class Class {}
          class Class2 {}
          action do_something() {
            var = allof(Class)
            var = allof(Class2)
          }
        adsl
      end 
    end

    def test_action__either_variable_number_of_blocks
      parser = ADSLParser.new
      assert_raise do
        parser.parse <<-adsl
          class Class {}
          action do_something() {
            either {}
          }
        adsl
      end 
      spec = parser.parse <<-adsl
        class Class {}
        action do_something() {
          either {
          } or {
            create(Class)
          }
        }
      adsl
      either = spec.actions.first.block.statements.first
      assert_equal 2, either.blocks.length
      assert_equal 0, either.blocks[0].statements.length
      assert_equal 1, either.blocks[1].statements.length

      spec = parser.parse <<-adsl
        class Class {}
        action do_something() {
          either {
          } or {
            create(Class)
          } or {
            create(Class)
            create(Class)
          }
        }
      adsl
      either = spec.actions.first.block.statements.first
      assert_equal 3, either.blocks.length
      assert_equal 0, either.blocks[0].statements.length
      assert_equal 1, either.blocks[1].statements.length
      assert_equal 2, either.blocks[2].statements.length
    end

    def test_action__unmatching_types_in_either
      parser = ADSLParser.new
      assert_raise ADSLError do
        parser.parse <<-adsl
          class Class {}
          class Class2 {}
          action do_something() {
            var = allof(Class)
            either {
              var = allof(Class)
            } or {
              var = allof(Class2)
            }
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
          action do_something() {
            either {
              var = allof(Class2)
            } or {
              var = allof(Class)
            }
          }
        adsl
      end
    end

    def test_action__foreach_iterator_var_typecheck
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        parser.parse <<-adsl
          class Class { 0+ Class relation }
          action do_something() {
            foreach var: allof(Class) {
              var.relation -= allof(Class)
            }
          }
        adsl
      end
      assert_raise ADSLError do
        parser.parse <<-adsl
          class Class {}
          class Class2 { 0+ Class2 relation }
          action do_something() {
            foreach var: allof(Class) {
              var.relation -= allof(Class)
            }
          }
        adsl
      end
    end

    def test_action__foreach_does_not_redefine_var
      parser = ADSLParser.new
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class { 0+ Class relation }
          action do_something(0+ Class var) {
            foreach var: var {
            }
          }
        adsl
      end
    end

    def test_action__flat_for_each_is_by_default
      parser = ADSLParser.new
      spec = parser.parse <<-adsl
        class Class { 0+ Class relation }
        action do_something() {
          foreach o: allof(Class) {
          }
        }
      adsl
      assert spec.actions.first.statements.map{ |c| c.class }.include? DSFlatForEach
    end

    def test_action__either_lambda_works
      parser = ADSLParser.new
      spec = nil
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class { 0+ Class relation }
          action do_something() {
            var = allof(Class)
            either {
              var = subset(var)
            } or {
              var = subset(var)
            }
            var = var
          }
        adsl
      end

      action = spec.actions.first
      statements = action.statements

      assert_equal 4, statements.length
      
      orig_def    = statements[0]
      inside_def1 = statements[1].blocks[0].statements.first
      inside_def2 = statements[1].blocks[1].statements.first
      lambda_def  = statements[2]
      final_def   = statements[3]

      assert_all_different(
        :orig_def    => orig_def.var,
        :inside_def1 => inside_def1.var,
        :inside_def2 => inside_def2.var,
        :lambda_def  => lambda_def.var,
        :final_def   => final_def.var
      )

      assert_equal lambda_def.objset.objsets[0], inside_def1.var
      assert_equal lambda_def.objset.objsets[1], inside_def2.var
    end
    
    def test_action__if_lambda_works
      parser = ADSLParser.new
      spec = nil
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class { 0+ Class relation }
          action do_something() {
            var = allof(Class)
            if isempty(var) {
              var = subset(var)
            } else {
              var = empty
            }
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

      assert_equal lambda_def.objset.then_objset, then_def.var
      assert_equal lambda_def.objset.else_objset, else_def.var
    end

    def test_action__if_condition_var_definition
      parser = ADSLParser.new
      spec = nil
      assert_raise ADSLError do
        spec = parser.parse <<-adsl
          class Class {}
          action blah() {
            if isempty(var = allof(Class)) {
              a = var
            } else {
              b = var
            }
            delete var
          }
        adsl
      end
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class {}
          action blah() {
            if isempty(var = allof(Class)) {
              a = var
            } else {
              b = var
            }
          }
        adsl
      end

      statements = spec.actions.first.block.statements
      
      assert_equal 2, statements.length

      assert_equal 'var', statements[0].var.name
      assert_equal 'var', statements[1].condition.objset.name
    end

    def test_action__foreach_pre_lambda
      get_pre_lambdas = lambda do |for_each|
        for_each.block.statements.select do |stat|
          stat.kind_of?(DSAssignment) and stat.objset.kind_of?(DSForEachPreLambdaObjset)
        end
      end

      parser = ADSLParser.new
      spec = parser.parse <<-adsl
        class Class {}
        action do_something() {
          foreach var: allof(Class) {}
        }
      adsl
      assert_equal 0, get_pre_lambdas.call(spec.actions.first.block.statements[0]).length

      spec = parser.parse <<-adsl
        class Class {}
        action do_something() {
          foreach var: allof(Class) {
            var = allof(Class)
          }
        }
      adsl
      assert_equal 0, get_pre_lambdas.call(spec.actions.first.block.statements[0]).length

      spec = parser.parse <<-adsl
        class Class {}
        action do_something() {
          var = allof(Class)
          foreach a: allof(Class) {
            var = subset(var)
            var = subset(var)
          }
        }
      adsl
      pre_lambdas = get_pre_lambdas.call(spec.actions.first.block.statements[1])
      assert_equal 1, pre_lambdas.length
      assert_equal spec.actions.first.block.statements[0].var, pre_lambdas.first.objset.before_var
      assert_equal spec.actions.first.block.statements[1], pre_lambdas.first.objset.for_each
      assert_equal spec.actions.first.block.statements[1].block.statements.last.var, pre_lambdas.first.objset.inside_var

      spec = parser.parse <<-adsl
        class Class {}
        action do_something() {
          var = allof(Class)
          foreach var: allof(Class) {
            var = allof(Class)
          }
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
          action do_something() {
            allof(Class).klass += empty
            allof(Class2).klass2 += empty
          }
        adsl
      end

      assert_raise ADSLError do
        parser.parse <<-adsl
          action do_something() {
            empty.some_relation += empty
          }
        adsl
      end
      
      assert_nothing_raised ADSLError do
        parser.parse <<-adsl
          class Class {
            1 Class klass
          }
          action do_something() {
            foreach c: empty {
              allof(Class).klass += c
            }
          }
        adsl
      end
      
      assert_raise ADSLError do
        parser.parse <<-adsl
          class Class {
            1 Class klass
          }
          action do_something() {
            foreach c: empty {
              c.klass += allof(Class)
            }
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
          action do_something() {
            a = empty
            a = allof(Class)
            a.klass += a
          }
        adsl
      end
      assert_nothing_raised ADSLError do
        parser.parse <<-adsl
          class Class {
            1 Class klass
          }
          action do_something() {
            a = empty
            a = allof(Class)
            a.klass += a
          }
        adsl
      end
      assert_nothing_raised ADSLError do
        parser.parse <<-adsl
          class Class {
            1 Class klass
          }
          action do_something() {
            a = allof(Class)
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
          action do_something() {
            a = allof(Class)
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
          action blah() {
            a = b = create(Class)
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
      assert_equal 'b',   statements[2].objset.name
      assert_equal 'a',   statements[3].objset.name
      assert_equal 'b',   statements[4].objset.name
    end

    def test_action__conditional_branches
      parser = ADSLParser.new
      spec = nil
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-ADSL
          class Class {}
          action blah() {
            if isempty(allof(Class)) {
              delete allof(Class)
            }
            if isempty(allof(Class)) {
            } else {
              delete allof(Class)
            }
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
  end
end
