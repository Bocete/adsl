require 'adsl/synthesis/sails/test_helper'
require 'adsl/util/test_helper'
require 'minitest/unit'
require 'minitest/autorun'

module ADSL
  module IntegrationsTest
    module Sails
    end
  end
end

class ADSL::IntegrationsTest::Sails::TestHelperTest < Minitest::Unit::TestCase
  include ADSL::Synthesis::Sails::TestHelper

  def adsl
    <<-ADSL
      class Class {
        int asd
      }
    ADSL
  end

  def test_sails_model_setup
    assert(
      File.exists?(File.join ADSL::Synthesis::Sails::TestHelper::TEST_DIR, 'api/models/Class.js'),
      "Class model file not created"
    )
  end

  def test_sails_console_works__sync
    in_sails_console do |c|
      assert_equal 'asd', c.puts(c.inspect("'asd'"))
      assert_equal 8, c.puts(c.inspect("1+2+5"))
      c.puts "a = 100"
      assert_equal 80, c.puts(c.inspect("a - 20"))
    end
  end

  def test_create_and_delete_objects
    in_sails_console do |c|
      o = c.puts(<<-NODE)
        Class.create({asd: 123}, function(err, o){
          Class.find({}).exec(function(err, o){
            #{ c.inspect_and_terminate 'o' }
          })
        })
      NODE
      assert_equal 1, o.length
      assert_equal 123, o.first['asd']
    end
  end

  def test_nothing_exists_before1
    in_sails_console do |c|
      o = c.puts(<<-NODE)
        Class.find({}).exec(function(err, o){
          #{ c.inspect_and_terminate 'o' }
        })
      NODE
      assert o.empty?
      o = c.puts <<-NODE
        Class.create({asd: 123}, function(err, o){
          Class.find({}).exec(function(err, o){
            #{ c.inspect_and_terminate 'o' }
          })
        })
      NODE
      assert_equal 1, o.length
    end
  end
  
  def test_nothing_exists_before_even_more_sequential
    in_sails_console do |c|
      o = c.puts(<<-NODE)
        Class.find({}).exec(function(err, o){
          #{ c.inspect_and_terminate 'o' }
        })
      NODE
      assert o.empty?
      c.puts <<-NODE
        Class.create({asd: 123}, function(err, o){
          #{ c.terminate }
        })
      NODE
      o = c.puts <<-NODE
        Class.find({}).exec(function(err, o){
          #{ c.inspect_and_terminate 'o' }
        })
      NODE
      assert_equal 1, o.length
    end
  end
end
