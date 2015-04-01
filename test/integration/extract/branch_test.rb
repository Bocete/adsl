require 'minitest/unit'
require 'minitest/autorun'

require 'adsl/extract/bin'
require 'adsl/extract/rails/rails_instrumentation_test_case'
require 'adsl/util/test_helper'

class ADSL::Extract::BranchVerificationTest < ADSL::Extract::Rails::RailsInstrumentationTestCase
  include ADSL::Extract::Bin

  def verify_options_for(action)
    {
      :output => :silent,
      :check_satisfiability => false,
      :halt_on_error => true,
      :timeout => 40,
      :action => action
    }
  end
  
  def test__branch_no_return
    AsdsController.class_exec do
      def nothing
        if :something_not_interpretable_as_a_formula
          Asd.new
        else
          Asd.build
        end
      end
    end
    
    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant(self.not.exists{ |asd| })
    ruby

    assert_false verify :ast => ast, :verify_options => verify_options_for(:AsdsController__nothing)
  end
  
  def test__branch_with_return__matters
    AsdsController.class_exec do
      def nothing
        if :something_not_interpretable_as_a_formula
          return Asd.new
        else
          return Asd.build
        end
        Asd.find.destroy!
      end
    end
    
    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant(self.not.exists{ |asd| })
    ruby

    assert_false verify :ast => ast, :verify_options => verify_options_for(:AsdsController__nothing)
  end
  
  def test__branch_with_return__may_create_but_will_delete
    AsdsController.class_exec do
      def nothing
        if :something_not_interpretable_as_a_formula
        else
          Asd.build
        end
        Asd.find.destroy!
      end
    end
    
    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant(self.not.exists{ |asd| })
    ruby

    assert verify :ast => ast, :verify_options => verify_options_for(:AsdsController__nothing)
  end
   
  def test__branch_conditions_decide_branch_choice
    AsdsController.class_exec do
      def nothing
        if true
        else
          Asd.build
        end
      end
    end
    
    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant(self.not.exists{ |asd| })
    ruby
    
    assert verify :ast => ast, :verify_options => verify_options_for(:AsdsController__nothing)
  end
  
  def test__branch_with_return__may_create_or_delete
    AsdsController.class_exec do
      def nothing
        if :something_not_interpretable_as_a_formula
        else
          return Asd.build
        end
        Asd.find.destroy!
      end
    end
    
    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant(self.not.exists{ |asd| })
    ruby
    
    assert_false verify :ast => ast, :verify_options => verify_options_for(:AsdsController__nothing)
  end
   
  def test__variable_assignments
    AsdsController.class_exec do
      def nothing
        a = nil
        if :something_not_interpretable_as_a_formula
          a = Asd.new
        else
          a = Asd.build
        end
        a.destroy!
      end
    end
    
    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant(self.not.exists{ |asd| })
    ruby

    assert verify :ast => ast, :verify_options => verify_options_for(:AsdsController__nothing)
  end
  
end
