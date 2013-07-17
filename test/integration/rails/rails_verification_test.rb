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
  
  def test_verify_spass__true
    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant self.true
    ruby

    assert verify_spass :ast => ast, :verify_options => verify_options_for(:AsdsController__create)
  end
  
  def test_verify_spass__false
    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant self.not(exists{|asd|})
    ruby

    assert_false verify_spass :ast => ast, :verify_options => verify_options_for('AsdsController__create')
  end
  
  def test_verify_spass__one_asd
    AsdsController.class_exec do
      def nothing
        Asd.new
        Asd.find.destroy!
      end
    end
    
    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant self.not(exists{|asd|})
    ruby

    assert verify_spass :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end
  
  def test_verify_spass__one_asd_again
    AsdsController.class_exec do
      def nothing
        Asd.new.destroy!
      end
    end
    
    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant self.not(exists{|asd|})
    ruby

    assert verify_spass :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end
  
  def test_verify_spass__one_asd_through_method_calls
    Asd.class_exec do
      def self.create_new_instance
        Asd.new
      end

      def alias_to_kill
        destroy
      end
    end

    AsdsController.class_exec do
      def nothing
        Asd.create_new_instance
      end
    end
    
    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant self.not(exists{|asd|})
    ruby

    assert_false verify_spass :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end
end
