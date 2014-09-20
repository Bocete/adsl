require 'test/unit'
require 'adsl/verification/rails_verification'
require 'adsl/extract/rails/rails_instrumentation_test_case'
require 'adsl/util/test_helper'

class ADSL::Verification::RailsVerificationTest < ADSL::Extract::Rails::RailsInstrumentationTestCase
  include ADSL::Verification::RailsVerification

  def verify_options_for(action)
    {
      :output => :silent,
      :check_satisfiability => false,
      :halt_on_error => true,
      :timeout => 120,
      :actions => [action.to_s]
    }
  end
  
  def test_verify_spass__branch_no_return
    AsdsController.class_exec do
      def nothing
        if true
          Asd.new
        else
          Asd.build
        end
      end
    end
    
    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant(self.not.exists{ |asd| })
    ruby

    assert_false verify_spass :ast => ast, :verify_options => verify_options_for(:AsdsController__nothing)
  end
  
  def test_verify_spass__branch_with_return__matters
    AsdsController.class_exec do
      def nothing
        if true
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

    assert_false verify_spass :ast => ast, :verify_options => verify_options_for(:AsdsController__nothing)
  end
  
  def test_verify_spass__branch_with_return__may_create_but_will_delete
    AsdsController.class_exec do
      def nothing
        if true
        else
          Asd.build
        end
        Asd.find.destroy!
      end
    end
    
    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant(self.not.exists{ |asd| })
    ruby

    assert verify_spass :ast => ast, :verify_options => verify_options_for(:AsdsController__nothing)
  end
  
  def test_verify_spass__branch_with_return__may_create_or_delete
    AsdsController.class_exec do
      def nothing
        if true
        else
          return Asd.build
        end
        Asd.find.destroy!
      end
    end
    
    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant(self.not.exists{ |asd| })
    ruby
    
    assert_false verify_spass :ast => ast, :verify_options => verify_options_for(:AsdsController__nothing)
  end
   
  def test_verify_spass__variable_assignments
    AsdsController.class_exec do
      def nothing
        a = nil
        if true
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

    assert verify_spass :ast => ast, :verify_options => verify_options_for(:AsdsController__nothing)
  end
  
end
