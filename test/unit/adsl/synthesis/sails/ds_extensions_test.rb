require 'minitest/unit'
require 'minitest/autorun'
require 'adsl/synthesis/sails/ds_extensions'
require 'adsl/util/test_helper'
require 'adsl/ds/data_store_spec'
require 'adsl/ds/type_sig'

module ADSL
  module Synthesis
    module Sails
    end
  end
end

class ADSL::Synthesis::Sails::DSExtensionsTest < Minitest::Unit::TestCase
  include ADSL::DS

  def setup
    @class1 = DSClass.new :name => 'Class1'
    @class2 = DSClass.new :name => 'Class2'
    @zeroToOne = DSRelation.new(
      :name => 'zeroToOne',
      :cardinality => TypeSig::ObjsetCardinality::ZERO_ONE,
      :from_class => @class1,
      :to_class => @class2
    )
    @oneToOne = DSRelation.new(
      :name => 'oneToOne',
      :cardinality => TypeSig::ObjsetCardinality::ONE,
      :from_class => @class1,
      :to_class => @class2
    )
    @zeroToMany = DSRelation.new(
      :name => 'zeroToMany',
      :cardinality => TypeSig::ObjsetCardinality::ZERO_MANY,
      :from_class => @class1,
      :to_class => @class2
    )
    @oneToMany = DSRelation.new(
      :name => 'oneToMany',
      :cardinality => TypeSig::ObjsetCardinality::ONE_MANY,
      :from_class => @class1,
      :to_class => @class2
    )

    @class1.members.concat [@zeroToOne, @oneToOne, @zeroToMany, @oneToMany]

    @ds = DSSpec.new(
      :classes => [@class1, @class2]
    )
    @ds.classes.each do |c|
      c.members.each do |m|
        m.prepare_sails_translation @ds
      end
    end
  end

  def test__association__to_sails_string
    assert_equal_nospace "zeroToOne: { model: 'Class2' }",                      @zeroToOne.to_sails_string(@ast_spec)
    assert_equal_nospace "oneToOne: { model: 'Class2', required: true }",       @oneToOne.to_sails_string(@ast_spec)
    assert_equal_nospace "zeroToMany: { collection: 'Class2' }",                @zeroToMany.to_sails_string(@ast_spec)
    assert_equal_nospace "oneToMany: { collection: 'Class2', required: true }", @oneToMany.to_sails_string(@ast_spec)
  end

  def test__association__deref_methods
    assert_include_nospace <<-NODEJS, @zeroToOne.sails_class_methods.join(' ')
      derefzeroToOne: function(elems, cb) {
        if (elems.length == 0) {
          cb(null, []);
        } else if (elems.length == 1) {
          Class2.find({ id: elems[0].zeroToOne }).exec(cb); 
        } else {
          Class2.find({ or: elems.map(function(e){ { id: e.zeroToOne } }) }).exec(cb);
        }
      }
    NODEJS
  end

  def test__field__to_sails_string
    type_mappings = [
      [TypeSig::BasicType::BOOL,    'boolean'],
      [TypeSig::BasicType::STRING,  'string' ],
      [TypeSig::BasicType::INT,     'integer'],
      [TypeSig::BasicType::DECIMAL, 'float'  ],
      [TypeSig::BasicType::REAL,    'float'  ]
    ]
    type_mappings.each do |ds_type, sails|
      field = DSField.new :name => 'fieldName', :type => ds_type
      assert_equal_nospace "fieldName: { type: '#{sails}' }", field.to_sails_string(nil)
    end
  end

end
