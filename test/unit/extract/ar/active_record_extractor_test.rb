require 'test/unit'
require 'extract/ar/active_record_extractor'
require 'pp'
require 'util/test_helper'

class ActiveRecordExtractorTest < Test::Unit::TestCase
=begin
  def test_filter_ar_classes__plain
    arclass1 = ActiveRecordMetaclass.new(:name => 'arclass1', :superclass_name => 'ActiveRecord::Base')
    arclass2 = ActiveRecordMetaclass.new(:name => 'arclass2', :superclass_name => 'ActiveRecord::Base')
    non_ar_class1 = ActiveRecordMetaclass.new(:name => 'non_ar_class1', :superclass_name => 'Blah')
    non_ar_class2 = ActiveRecordMetaclass.new(:name => 'non_ar_class2', :superclass_name => nil)
    classes = [arclass1, non_ar_class1, non_ar_class2, arclass2]

    assert_equal Set.new, ActiveRecordExtractor.new.filter_ar_classes(classes) ^ Set[arclass1, arclass2]
  end
  
  def test_filter_ar_classes__propagation
    arclass1 = ActiveRecordMetaclass.new(:name => 'arclass1', :superclass_name => 'ActiveRecord::Base')
    arclass2 = ActiveRecordMetaclass.new(:name => 'arclass2', :superclass_name => 'arclass1')
    non_ar_class1 = ActiveRecordMetaclass.new(:name => 'non_ar_class1', :superclass_name => 'Blah')
    non_ar_class2 = ActiveRecordMetaclass.new(:name => 'non_ar_class2', :superclass_name => nil)
    classes = [arclass1, non_ar_class1, non_ar_class2, arclass2]

    assert_equal Set.new, ActiveRecordExtractor.new.filter_ar_classes(classes) ^ Set[arclass1, arclass2]
  end
=end
end
