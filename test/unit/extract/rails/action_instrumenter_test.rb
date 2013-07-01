require 'test/unit'
require 'extract/rails/action_instrumenter'
require 'util/test_helper'
require 'active_record'
require 'activerecord-tableless'
require 'ruby_parser'
require 'ruby2ruby'

class ActionInstrumenterTest < Test::Unit::TestCase
  include Extract::Rails
  
  def setup
    assert_false class_defined? :Asd, :ADSLMetaAsd, :Kme, :ADSLMetaKme, :Blah, :ADSLMetaBlah, :Mod
    eval <<-ruby
      class Asd < ActiveRecord::Base
        has_no_table
        has_one :asd
        has_many :kmes
      end

      class Kme < Asd
        has_no_table
      end

      module Mod
        class Blah < ActiveRecord::Base
          has_no_table
        end
      end
    ruby
    
    ActiveRecordMetaclassGenerator.new(Asd).generate_class
    ActiveRecordMetaclassGenerator.new(Kme).generate_class
    ActiveRecordMetaclassGenerator.new(Mod::Blah).generate_class
  end

  def ar_class_names
    ['Asd', 'Kme', 'Blah']
  end

  def teardown
    unload_class :Asd, :ADSLMetaAsd, :Kme, :ADSLMetaKme, :Blah, :ADSLMetaBlah, :Mod
  end

  def test__replaces_activerecord_names
    instrumenter = Extract::Rails::ActionInstrumenter.new ar_class_names, File.join(Dir.pwd, '/test/unit').to_s
    input_code = <<-rails
      def blah
        Asd.all.something Kme.all, Mod::Blah.find, Asd
      end
    rails
    
    resulting_code = Ruby2Ruby.new.process instrumenter.instrument(RubyParser.new.process input_code)

    assert_equal 4, resulting_code.scan(/ADSLMeta/).length
    assert_equal 2, resulting_code.scan(/ADSLMetaAsd/).length
    assert_equal 2, resulting_code.scan(/Asd/).length
    assert_equal 1, resulting_code.scan(/ADSLMetaKme/).length
    assert_equal 1, resulting_code.scan(/Kme/).length
    assert_equal 1, resulting_code.scan(/Mod::ADSLMetaBlah/).length
    assert_equal 0, resulting_code.scan(/Mod::Blah/).length
  end
  
  def test__assignments_assign_to_metavariables
    instrumenter = Extract::Rails::ActionInstrumenter.new ar_class_names, File.join(Dir.pwd, '/test/unit').to_s
    input_code = <<-rails
      def blah
        a = 5
        b = :kme
      end
    rails
    instrumented_sexp = instrumenter.instrument(RubyParser.new.process input_code)
    resulting_code = Ruby2Ruby.new.process instrumented_sexp

    assert_equal 2, resulting_code.scan(/Extract::Rails::MetaVariable/).length
  end
end
