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
      def escape_str(obj)
        "\"#{obj.to_s.gsub('"', '""')}\""
      end
     
      def initialize(*cols)
        @row_hashes = []
        @columns = []
        cols.each do |col|
          add_column col
        end
      end

      def prepare_for_csv(row)
        row.keys.each do |col|
          row[col] = row[col].to_s if row[col].is_a? Symbol
        end
      end

      def add_row(row)
        prepare_for_csv row
        @row_hashes << row
        row.keys.each do |key|
          add_column key unless @columns.include? key
        end
      end

      def add_column(col)
        raise ArgumentError, "Duplicate column name #{col}" if @columns.include? col.to_sym
        @columns << col.to_sym
      end

      alias_method :<<, :add_row

      def column_type(col)
        type = nil
        @row_hashes.each do |row|
          next if row[col].nil?
          if row[col].is_a?(Numeric) && type.nil?
            type = :numeric
          elsif row[col] == true || row[col] == false && type.nil?
            type = :boolean
          elsif row[col].is_a?(String) || row[col].is_a?(Symbol)
            type = :string
          end
        end
        type
      end

      def infer_column_types
        types = {}
        @columns.each do |col|
          types[col] = column_type col
        end
        types
      end

      def sort!(*columns)
        types = infer_column_types
        @row_hashes.sort_by! do |row|
          columns.map do |col|
            if types[col] == nil
              nil
            elsif types[col] == :numeric
              row[col] || -Float::INFINITY
            elsif types[col] == :boolean
              next 2 if row[col] == true
              next 1 if row[col] == false
              next 0
            else
              row[col] || ''
            end
          end.to_a
        end
        self
      end

      def to_s
        return '' if @columns.empty?
        output = @columns.map{ |c| escape_str(c) }.join(',') + "\n"
        types = infer_column_types
        @row_hashes.each do |row|
          output += @columns.map do |c|
            next row[c].to_s || '' if types[c] == :numeric
            next row[c].nil? ? '' : "\"#{row[c]}\"" if types[c] == :boolean
            escape_str(row[c] || '')
          end.join(',') + "\n"
        end
        output
      end
    end
  end
end
