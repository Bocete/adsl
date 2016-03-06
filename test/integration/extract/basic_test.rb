require 'adsl/util/test_helper'
require 'adsl/extract/bin'
require 'adsl/extract/rails/rails_instrumentation_test_case'

class ADSL::Extract::BasicRailsVerificationTest < ADSL::Extract::Rails::RailsInstrumentationTestCase
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
  
  def test_verify__true
    extractor = create_rails_extractor <<-ruby
      invariant self.true
    ruby
    extractor.extract_all_actions 
    ast = extractor.adsl_ast

    assert verify :ast => ast, :verify_options => verify_options_for(:AsdsController__create)
  end
  
  def test_verify__false
    AsdsController.class_exec do
      def create
        Asd.new
      end
    end
    
    extractor = create_rails_extractor <<-ruby
      invariant self.not(exists{|asd|})
    ruby
    extractor.extract_all_actions
    ast = extractor.adsl_ast

    assert_false verify :ast => ast, :verify_options => verify_options_for('AsdsController__create')
  end
  
  def test_verify__one_asd
    AsdsController.class_exec do
      def nothing
        Asd.new
        Asd.find.destroy!
      end
    end
    
    extractor = create_rails_extractor <<-ruby
      invariant self.not(exists{|asd|})
    ruby
    extractor.extract_all_actions
    ast = extractor.adsl_ast

    assert verify :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end
  
  def test_verify__one_asd_again
    AsdsController.class_exec do
      def nothing
        Asd.new.destroy!
      end
    end
    
    extractor = create_rails_extractor <<-ruby
      invariant self.not(exists{|asd|})
    ruby
    extractor.extract_all_actions
    ast = extractor.adsl_ast

    assert verify :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end
  
  def test_verify__one_asd_through_method_calls
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
    
    extractor = create_rails_extractor <<-ruby
      invariant self.not(exists{|asd|})
    ruby
    extractor.extract_all_actions
    ast = extractor.adsl_ast

    assert_false verify :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end
  
  def test_verify__foreach
    AsdsController.class_exec do
      def nothing
        Asd.all.each do |asd|
          asd.delete
        end
      end
    end

    extractor = create_rails_extractor <<-ruby
      invariant forall{ |asd| asd.blahs.empty? }
    ruby
    extractor.extract_all_actions
    ast = extractor.adsl_ast

    assert verify :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end

  def test_verify__foreach_through
    AsdsController.class_exec do
      def nothing
        Asd.all.each do |asd|
          asd.delete
        end
      end
    end

    extractor = create_rails_extractor <<-ruby
      invariant forall{ |asd| asd.kmes.empty? }
    ruby
    extractor.extract_all_actions
    ast = extractor.adsl_ast

    assert verify :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end

  def test_verify__association_build__simple
    AsdsController.class_exec do
      def nothing
        Asd.find.blahs.build
      end
    end

    extractor = create_rails_extractor <<-ruby
      invariant forall{ |asd| not asd.blahs.empty? }
    ruby
    extractor.extract_all_actions
    ast = extractor.adsl_ast

    assert verify :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end
  
  def test_verify__association_build__inverse
    AsdsController.class_exec do
      def nothing
        b = Mod::Blah.new
        Asd.find.blahs << b
      end
    end

    extractor = create_rails_extractor <<-ruby
      invariant forall(:blah => Mod::Blah){ |blah| not blah.asd.empty? }
      invariant exists{ |asd| }
    ruby
    extractor.extract_all_actions
    ast = extractor.adsl_ast

    assert verify :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end

  def test_verify__association_build__can_be_used
    AsdsController.class_exec do
      def nothing
        Asd.find.blahs.build.delete
      end
    end

    extractor = create_rails_extractor <<-ruby
      invariant forall{ |asd| asd.blahs.empty? }
    ruby
    extractor.extract_all_actions
    ast = extractor.adsl_ast

    assert verify :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end
  
  def test_verify__association_build__can_be_used_2
    AsdsController.class_exec do
      def nothing
        Asd.find.blahs.build.delete
      end
    end

    extractor = create_rails_extractor <<-ruby
      invariant Mod::Blah.all.empty?
    ruby
    extractor.extract_all_actions
    ast = extractor.adsl_ast

    assert verify :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end
  
  def test_verify__association_build__through_creates_join_objects
    AsdsController.class_exec do
      def nothing
        Asd.new.kmes.build
      end
    end

    extractor = create_rails_extractor <<-ruby
      invariant forall{ |asd| asd.blahs.empty? }
    ruby
    extractor.extract_all_actions
    ast = extractor.adsl_ast

    assert_false verify :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end

  def test_verify__union_of_objsets_overestimate
    AsdsController.class_exec do
      def nothing
        a = Asd.find
        a.blahs = Mod::Blah.new + Mod::Blah.new
        Mod::Blah.find.delete
        Mod::Blah.find.delete
      end
    end
    
    extractor = create_rails_extractor <<-ruby
      invariant Mod::Blah.all.empty?
    ruby
    extractor.extract_all_actions
    ast = extractor.adsl_ast

    assert verify :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end
  
  def test_verify__union_of_objsets_underestimate
    AsdsController.class_exec do
      def nothing
        a = Asd.find
        a.blahs = Mod::Blah.new + Mod::Blah.new
        Mod::Blah.find.delete
        Mod::Blah.find.delete
      end
    end
    
    extractor = create_rails_extractor <<-ruby
      invariant !Mod::Blah.all.empty?
    ruby
    extractor.extract_all_actions
    ast = extractor.adsl_ast

    assert verify :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end
  
  def test_verify__call_of_optional_assignment
    AsdsController.class_exec do
      def asd
        @asd ||= Asd.find
      end

      def nothing
        @asd = Asd.where
        (@asd ||= Asd.find).blahs.build
      end
    end
    
    extractor = create_rails_extractor <<-ruby
      invariant forall(:blah => Mod::Blah){ |blah| blah.asd.empty? }
    ruby
    extractor.extract_all_actions
    ast = extractor.adsl_ast

    assert_false verify :ast => ast, :verify_options => verify_options_for('AsdsController__nothing')
  end
end
