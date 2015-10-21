require 'adsl/util/test_helper'
require 'adsl/util/csv_hash_formatter'

class ADSL::Util::CSVHashFormatterTest < ActiveSupport::TestCase
  include ADSL::Util

  def wrap(col_count, *content)
    output = ""
    until content.empty?
      row = content.shift col_count
      output = output + row.map{ |c| "\"#{c}\"" }.join(',') + "\n"
    end
    output
  end

  def test_blank_if_empty
    formatter = CSVHashFormatter.new
    assert_equal '', formatter.to_s
  end
  
  def test_single_row_column
    formatter = CSVHashFormatter.new
    formatter << { :asd => 'kme' }
    assert_equal wrap(1, 'asd', 'kme'), formatter.to_s
  end

  def test_no_duplicate_columns
    formatter = CSVHashFormatter.new
    formatter.add_column 'a'

    assert_raises ArgumentError do
      formatter.add_column 'a'
    end
    
    formatter = CSVHashFormatter.new 'a'
    assert_raises ArgumentError do
      formatter.add_column 'a'
    end
    
    assert_raises ArgumentError do
      formatter = CSVHashFormatter.new 'a', 'a'
    end
  end
  
  def test_two_rows_columns
    formatter = CSVHashFormatter.new :asd, :asd2
    formatter << { :asd => 'kme1', :asd2 => 'kme2'}
    formatter << { :asd => 'kme3', :asd2 => 'kme4'}
    assert_equal wrap(2, 'asd', 'asd2', 'kme1', 'kme2', 'kme3', 'kme4'), formatter.to_s
    
    formatter = CSVHashFormatter.new 'asd'
    formatter << { :asd => 'kme1', :asd2 => 'kme2'}
    formatter << { :asd2 => 'kme4', :asd => 'kme3'}
    assert_equal wrap(2, 'asd', 'asd2', 'kme1', 'kme2', 'kme3', 'kme4'), formatter.to_s
  end

  def test_incomplete_column_lists
    formatter = CSVHashFormatter.new :col1, :col2, :col3
    formatter << { :col1 => 'val1', :col2 => 'val2'}
    formatter << { :col3 => 'val4', :col2 => 'val3'}
    assert_equal wrap(3, 'col1', 'col2', 'col3', 'val1', 'val2', '', '', 'val3', 'val4'), formatter.to_s
  end

  def test_csv_escaping
    formatter = CSVHashFormatter.new
    formatter << { :asd => '"kme"'}
    assert_equal wrap(1, 'asd', '""kme""'), formatter.to_s
  end
end
