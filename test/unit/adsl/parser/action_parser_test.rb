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

      a1 = DSVariable.new :name => 'a'
      a2 = DSVariable.new :name => 'a'
      b = DSVariable.new :name => 'b'
      b2 = DSVariable.new :name => 'b'

      context1.define_var a1, true
      context1.define_var b, true

      context2 = context1.dup

      context2.redefine_var a2, false

      assert_equal({"a" => [a1, a2]}, ASTTypecheckResolveContext.context_vars_that_differ(context1, context2))

      context3 = context2.dup
      assert_equal({"a" => [a1, a2, a2]}, ASTTypecheckResolveContext.context_vars_that_differ(context1, context2, context3))

      context3.redefine_var b2, false
      assert_equal({"a" => [a1, a2, a2], "b" => [b, b, b2]}, ASTTypecheckResolveContext.context_vars_that_differ(context1, context2, context3))
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

      assert_equal klass, var1.type
      assert_equal klass, var2.type
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
      assert_equal spec.classes, spec.actions.first.args.map{ |v| v.type }
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
      parser = ADSLParser.new
      spec = nil
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class { 0+ Class relation }
          action do_something() {
            var = oneof(allof(Class))
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
            var2 = oneof(allof(Class2))
            var1.relation -= var2
          }
        adsl
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
      assert_equal klass2, stmt.objset1.type
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
      assert_equal klass2, stmt.objset1.type
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
      assert_equal klass2, stmt.objset1.type
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
      orig_def = action.statements[0].var
      inside_def1 = action.statements[1].blocks[0].statements.first.var
      inside_def2 = action.statements[1].blocks[1].statements.first.var
      after_def = action.statements[2].objset

      assert orig_def != inside_def1
      assert orig_def != inside_def2
      assert inside_def1 != after_def
      assert inside_def2 != after_def
      assert inside_def1 != inside_def2
      assert orig_def != after_def
      assert_equal after_def.vars[0], inside_def1
      assert_equal after_def.vars[1], inside_def2
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

    def test_action__entity_class_writes
      parser = ADSLParser.new
      spec = nil
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class {}
          class Class2 {}
          action do_something() {
            create(Class)
          }
        adsl
      end
      assert_equal Set[spec.classes.first], spec.actions.first.block.list_entity_classes_written_to

      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class {}
          class Class2 {}
          action do_something() {
            create(Class)
            either {
              foreach a: allof(Class) {
                delete allof(Class2)
              }
            } or {}
          }
        adsl
      end
      assert_equal Set[*spec.classes], spec.actions.first.block.list_entity_classes_written_to
      assert_equal Set[spec.classes.first], spec.actions.first.block.statements.first.list_entity_classes_written_to
      assert_equal Set[spec.classes.second], spec.actions.first.block.statements.last.list_entity_classes_written_to
    end

    def test_action__entity_class_reads
      parser = ADSLParser.new
      spec = nil
      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class {}
          class Class2 {}
          action do_something() {
            delete allof(Class)
          }
        adsl
      end
      assert_equal Set[spec.classes.first], spec.actions.first.block.list_entity_classes_read

      assert_nothing_raised ADSLError do
        spec = parser.parse <<-adsl
          class Class {}
          class Class2 {}
          action do_something() {
            create(Class)
            either {
              foreach a: allof(Class) {
                delete allof(Class2)
              }
            } or {}
          }
        adsl
      end
      assert_equal Set[*spec.classes], spec.actions.first.block.list_entity_classes_read
      assert_equal Set[], spec.actions.first.block.statements.first.list_entity_classes_read
      assert_equal Set[*spec.classes], spec.actions.first.block.statements.last.list_entity_classes_read
    end
  end
end
