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
    AsdsController.class_exec do
      def create
        Asd.new
      end
    end
    
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
  
  def test_verify_spass__foreach
    AsdsController.class_exec do
      def nothing
        Asd.all.each do |asd|
          asd.blahs.each do |blah|
            blah.delete
          end
        end
      end
    end

    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant forall{ |asd| asd.blahs.empty? }
    ruby

    assert verify_spass :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end

  def test_verify_spass__foreach_through
    AsdsController.class_exec do
      def nothing
        Asd.all.each do |asd|
          asd.kmes.each do |kme|
            kme.delete
          end
        end
      end
    end

    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant forall{ |asd| asd.kmes.empty? }
    ruby

    assert verify_spass :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end

  def test_verify_spass__association_build__simple
    AsdsController.class_exec do
      def nothing
        Asd.find.blahs.build
      end
    end

    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant forall{ |asd| asd.blahs.empty? }
    ruby

    assert_false verify_spass :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end
  
  def test_verify_spass__association_build__can_be_used
    AsdsController.class_exec do
      def nothing
        Asd.find.blahs.build.delete
      end
    end

    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant forall{ |asd| asd.blahs.empty? }
    ruby

    assert verify_spass :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end
  
  def test_verify_spass__association_build__can_be_used_2
    AsdsController.class_exec do
      def nothing
        Asd.find.blahs.build.delete
      end
    end

    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant Mod::Blah.all.empty?
    ruby

    assert verify_spass :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end
  
  def test_verify_spass__association_build__through_creates_join_objects
    AsdsController.class_exec do
      def nothing
        Asd.find.kmes.build
      end
    end

    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant forall{ |asd| asd.blahs.empty? }
    ruby

    assert_false verify_spass :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end

  def test_verify_spass__union_of_objsets
    AsdsController.class_exec do
      def nothing
        a = Asd.find
        a.blahs = Mod::Blah.new + Mod::Blah.new
        a.blahs.find.delete
      end
    end
    
    ast = create_rails_extractor(<<-ruby).adsl_ast
      invariant forall(:blah1 => Mod::Blah, :blah2 => Mod::Blah){ |asd, blah1, blah2|
        self.and(blah1 <= asd.blahs, blah2 <= asd.blahs).implies[blah1 == blah2]
      }
    ruby
  end
end
