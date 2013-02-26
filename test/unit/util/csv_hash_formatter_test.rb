
require 'util/csv_hash_formatter'
require 'test/unit'

class CSVHashFormatterTest < Test::Unit::TestCase
  include Util

  def wrap(col_count, *content)
    output = ""
    until content.empty?
      row = content.first(col_count)
      output = output + row.map{ |c| "\"#{c}\"" }.join(',') + "\n"
      content = content[col_count..content.length]
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
  
  def test_two_rows_columns
    formatter = CSVHashFormatter.new
    formatter << { :asd => 'kme1', :asd2 => 'kme2'}
    formatter << { :asd => 'kme3', :asd2 => 'kme4'}
    assert_equal wrap(2, 'asd', 'asd2', 'kme1', 'kme2', 'kme3', 'kme4'), formatter.to_s
    
    formatter = CSVHashFormatter.new
    formatter << { :asd => 'kme1', :asd2 => 'kme2'}
    formatter << { :asd2 => 'kme4', :asd => 'kme3'}
    assert_equal wrap(2, 'asd', 'asd2', 'kme1', 'kme2', 'kme3', 'kme4'), formatter.to_s
  end

  def test_incomplete_column_lists
    formatter = CSVHashFormatter.new
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
