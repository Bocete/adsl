require 'minitest/unit'
require 'minitest/autorun'
require 'adsl/synthesis/sails/model_syn'
require 'adsl/ds/data_store_spec'
require 'adsl/ds/type_sig'
require 'adsl/parser/adsl_parser.tab'
require 'adsl/util/test_helper'
require 'fileutils'

class ADSL::Synthesis::Sails::ModelSynTest < Minitest::Unit::TestCase
  include ADSL::DS
  
  def assert_include_nospace(substring, text)
    sb_nsp   = substring.gsub /\s+/m, ''
    text_nsp = text.gsub /\s+/m, ''
    assert text_nsp.include?(sb_nsp), "'#{text}' does not include '#{substring}'"
  end

  def setup
    @ds = ADSL::Parser::ADSLParser.new.parse <<-ADSL
      class User {
        string name
        0+ Address addresses inverseof user
        0..1 ForOneToOne oneToOne
      }
      class Address {
        1 User user
      }
      class ForOneToOne {
        0..1 User oneToOne inverseof oneToOne
      }
    ADSL
    @c1, @c2 = @ds.classes
    @dir = Dir.mktmpdir('adsl_translation_test')

    syn = ADSL::Synthesis::Sails::ModelSyn.new @ds, @dir
    syn.create_model_files

    {'Address.js' => :@address_model, 'User.js' => :@user_model, 'ForOneToOne.js' => :@forOneToOne_model}.each do |file, field|
      model_file = File.join @dir, 'api/models', file
      assert File.exist?(model_file), "File '#{model_file}' not found"
      instance_variable_set field, File.read(model_file)
    end
  end

  def teardown
    FileUtils.rm_rf @dir unless @dir.nil?
    @dir = nil
  end

  def test__creates_appropriate_files
    expected_files = @ds.classes.map{ |c| File.join @dir, 'api/models', "#{ c.name }.js" }
    actual_files = Dir.glob(File.join @dir, 'api/models/**/*.js')
    assert_set_equal expected_files, actual_files
  end

  def test__expected_fields
    assert_include_nospace <<-NODE, @user_model
      name: { type: 'string' }
    NODE
    assert_include_nospace <<-NODE, @user_model
      addresses: { collection: 'Address', via: 'user' }
    NODE
    assert_include_nospace <<-NODE, @user_model
      oneToOne: { model: 'ForOneToOne' }
    NODE
  end

  def test__expected__user_address_expected_members
    assert_include_nospace <<-NODE, @address_model
      user: {
        model: 'User',
        required: true
      }
    NODE
  end

end
