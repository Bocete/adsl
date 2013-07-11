# A writer into CSV format that takes lines in hash format
# row = {:column1 => value1, :column2 => value2, ... }
# All rows are buffered together and a csv file is output with
# the union of individual column sets
# if the order of columns matter, supply an OrderedHash
# instance for each row

require 'set'

module ADSL
  module Util
    class CSVHashFormatter
      def escape(obj)
        "\"#{obj.to_s.gsub('"', '""')}\""
      end
     
      def initialize(*cols)
        @row_hashes = []
        @columns = []
        cols.each do |col|
          add_column col
        end
      end

      def add_row(row)
        @row_hashes << row
        row.keys.each do |key|
          add_column key unless @columns.include? key
        end
      end

      def add_column(col)
        raise "Duplicate column name #{col}" if @columns.include? col.to_sym
        @columns << col.to_sym
      end

      alias_method :<<, :add_row

      def to_s
        return '' if @columns.empty?
        output = @columns.map{ |c| escape(c) }.join(',') + "\n"
        @row_hashes.each do |row|
          output = output + @columns.map{ |c| escape(row[c] || '') }.join(',') + "\n"
        end
        output
      end
    end
  end
end
