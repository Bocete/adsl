require 'test/unit'
require 'util/test_helper'
require 'parser/adsl_ast'
require 'extract/rails/rails_extractor'
require 'extract/rails/rails_test_helper'
require 'extract/rails/rails_instrumentation_test_case'

class RailsExtractorTest < Extract::Rails::RailsInstrumentationTestCase
  include Extract::Rails

  def test_setup__routes
    route_set = ADSLRailsTestApplication.routes.routes
    
    assert route_set.map{ |route| route.ast.to_s }.include? '/asds/nothing(.:format)'
  end

  def test_setup__active_record
    assert_false self.class.lookup_const(:Asd).nil?
    assert_false self.class.lookup_const(:Kme).nil?
    assert_false self.class.lookup_const('Mod::Blah').nil?
  end

  def test_setup__urls_visible
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.get('/asds/nothing')
    assert_equal 200, session.response.status
    assert session.response.body.strip.empty?

    session = ActionDispatch::Integration::Session.new(Rails.application)
    Rails.logger.adsl_silence do
      session.get('thisdoesntexist')
    end
    assert_equal 404, session.response.status
  end

  def test_adsl_ast__empty_action
    extractor = RailsExtractor.new ar_classes
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :nothing)
    assert ast.block.statements.empty?
  end
  
  def test_adsl_ast__create_action
    extractor = RailsExtractor.new ar_classes
    ast = extractor.action_to_adsl_ast(extractor.route_for AsdsController, :create)
    assert_false ast.block.statements.empty?
    assert_equal ADSL::ADSLCreateObj, ast.block.statements.first.class
    assert_equal 'Asd', ast.block.statements.first.class_name.text
  end

end
