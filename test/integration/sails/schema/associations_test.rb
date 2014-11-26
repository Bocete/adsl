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

class ADSL::IntegrationsTest::Sails::AssociationsTest < Minitest::Unit::TestCase
  include ADSL::Synthesis::Sails::TestHelper

  def adsl
    <<-ADSL
      class Class1 {
        int asd
        0..1 Class2 manyToOne
        0..1 Class2 oneToOne
      }
      class Class2 {
        0+ Class1 oneToMany inverseof manyToOne
        0..1 Class1 oneToOne inverseof oneToOne
      }
    ADSL
  end

  def test_deref_oneToOne
    in_sails_console do |c|
      o1 = c.puts "Class2.create({}).exec(function(err, o) { #{c.inspect_and_terminate 'o' } })"
      o2 = c.puts "Class2.create({}).exec(function(err, o) { #{c.inspect_and_terminate 'o' } })"
      o = c.puts <<-NODE
        Class1.create({
          asd: 123
        }).exec(function(err, o) {
          #{c.inspect_and_terminate 'o'}
        })
      NODE
      assert_equal [], c.puts(<<-NODE)
        Class1.find({ id: #{ o['id'] } }).exec(function(err, o){
          Class1.derefoneToOne(o, function(err, result) {
            #{ c.inspect_and_terminate 'result' }
          })
        })
      NODE

      o = c.puts <<-NODE
        Class1.findOne({ id: #{ o['id'] } }).exec(function(err, o){
          o.oneToOne = #{o2['id']}; o.save(function(err, o){
            #{ c.inspect_and_terminate 'o' }
          })
        })
      NODE
      assert_false o['oneToOne'].nil?

      deref = c.puts(<<-NODE)
        Class1.find({ id: #{ o['id'] } }).exec(function(err, o){
          Class1.derefoneToOne(o, function(err, result) {
            #{ c.inspect_and_terminate 'result' }
          })
        })
      NODE
      assert_false deref.empty?
      assert_equal o2['id'], deref[0]['id']
    end
  end
  
  def test_deref_oneToMany
    in_sails_console do |c|
      o1 = c.puts "Class1.create({}).exec(function(err, o) { #{c.inspect_and_terminate 'o' } })"
      o2 = c.puts "Class1.create({}).exec(function(err, o) { #{c.inspect_and_terminate 'o' } })"
      o = c.puts  "Class2.create({}).exec(function(err, o) { #{c.inspect_and_terminate 'o' } })"
      assert_equal [], c.puts(<<-NODE)
        Class2.find({ id: #{ o['id'] } }).exec(function(err, o){
          Class2.derefoneToMany(o, function(err, result) {
            #{ c.inspect_and_terminate 'result' }
          })
        })
      NODE

      c.puts <<-NODE
        Class1.findOne({ id: #{ o1['id'] } }).exec(function(err, o1){
          o1.manyToOne = #{ o['id'] }; o1.save(function(err, o1){
            #{ c.inspect_and_terminate 'o1' }
          })
        })
      NODE
      c.puts <<-NODE
        Class1.findOne({ id: #{ o2['id'] } }).exec(function(err, o2){
          o2.manyToOne = #{ o['id'] }; o2.save(function(err, o2){
            #{ c.inspect_and_terminate 'o2' }
          })
        })
      NODE

      deref = c.puts(<<-NODE)
        Class2.find({ id: #{ o['id'] } }).exec(function(err, o){
          Class2.derefoneToMany(o, function(err, result) {
            #{ c.inspect_and_terminate 'result' }
          })
        })
      NODE
      assert_false deref.empty?
      expected_ids = [o1, o2].map{ |c| c['id'] }
      deref_ids = deref.map{ |c| c['id'] }
      assert_set_equal expected_ids, deref_ids
    end
  end
end
