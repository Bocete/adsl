require 'set'
require 'open3'
require 'thread'
require 'active_support'
require 'active_support/core_ext/module'
require 'tempfile'

TEST_ENV = false

class String
  def increment_suffix
    suffix = scan(/_(\d+)$/).last
    if suffix.nil?
      return self + "_2"
    else
      suffix = suffix.first
      return self[0, self.length - suffix.length] + (suffix.to_i + 1).to_s
    end
  end

  # for lolz
  def dyslexicize
    gsub(/(\w)(\w+)(\w)/) { |match| ([$1] + $2.chars.to_a.shuffle + [$3]).join('') }
  end

  def adsl_indent
    indented = "  " + gsub("\n", "\n  ")
    (/  $/ =~ indented) ? indented[0..-3] : indented
  end

  def without_leading_whitespace
    lines = self.lines
    whitespace_len = lines.map{ |line| line =~ /\S/ }.compact.min
    lines.map{ |line| line.length > whitespace_len ? line[whitespace_len..-1] : line }.join ""
  end
  
  def resolve_params(*args)
    args = args.flatten
    max_arg_index = self.scan(/\$\{(\d+)\}/).map{ |a| a.first.to_i }.max || 0
    if args.length < max_arg_index
      raise ArgumentError, "Invalid argument number: #{args.length} instead of #{max_arg_index}"
    end
    result = self
    args.length.times do |i|
      result = result.gsub "${#{i + 1}}", args[i].to_s
    end
    result
  end
end

class Time
  def self.time_execution
    pre = Time.now
    yield
    ((Time.now - pre)*1000).to_i
  end
end

class Object
  def deep_dup
    dup
  end
end

class Array
  def each_index_with_elem(&block)
    return each_index_without_elem(&block) if block.nil? or block.arity < 2
    count.times.each do |index|
      block[self[index], index]
    end
    self
  end
  alias_method_chain :each_index, :elem

  def map_index(&block)
    return map(&block) if block.nil? or block.arity < 2
    pairs = self.zip self.length.times
    pairs.map(&block)
  end
  
  def worklist_each
    changed = true
    until empty? or not changed
      changed = false
      length.times do
        task = self.shift
        new_value = yield task
        self << new_value if new_value
        changed = true if task != new_value
      end
    end
  end

  def adsl_indent
    join("").adsl_indent
  end

  def try_map(*args)
    raise "At least method name required for try_map" if args.empty?
    raise "First argument to try_map needs to be a symbol or string" unless args.first.is_a?(String) or args.first.is_a?(Symbol)
    map do |e|
      e.respond_to?(args.first) ? e.send(*args) : e
    end
  end

  def try_map!(*args)
    raise "At least method name required for try_map!" if args.empty?
    raise "First argument to try_map! needs to be a symbol or string" unless args.first.is_a?(String) or args.first.is_a?(Symbol)
    map! do |e|
      e.respond_to?(args.first) ? e.send(*args) : e
    end
  end

  def select_reject
    arr1 = []
    arr2 = []
    self.each do |e|
      if yield e
        arr1 << e
      else
        arr2 << e
      end
    end
    return arr1, arr2
  end

  def set_to(array)
    self.clear
    array.each{ |e| self << e }
    self
  end

  def deep_dup
    self.map &:deep_dup
  end
end

class Hash
  def deep_dup
    Hash[*self.to_a.flatten(1).deep_dup]
  end
end

class Tempfile
  def self.with_tempfile(content)
    file = Tempfile.new('adsl_tempfile')
    file.write content
    file.close
    yield file.path
  ensure
    file.unlink unless file.nil?
  end
end

class Range
  def empty?
    max.nil?
  end

  def intersect(other)
    return (0...0) if self.empty? || other.empty? || self.min > other.max || other.min > self.max
    (([self.min, other.min].max)..([self.max, other.max].min))
  end
end

class Symbol
  def dup; self; end
end

class NilClass
  def dup; self; end
end

class Numeric
  def dup; self; end
end

class TrueClass
  def dup; self; end
end

class FalseClass
  def dup; self; end
end

class Module
  def parent_module
    name.split('::')[0..-2].join('::').constantize
  end

  def lookup_const(const)
    lookup_container = self
    const.to_s.split('::').each do |portion|
      portion = 'Object' if portion.empty?
      defined = lookup_container.const_defined? portion rescue false
      return nil unless defined
      lookup_container = lookup_container.const_get portion
    end
    lookup_container
  end

  def lookup_or_create_module(name)
    lookup_container = self
    name.to_s.split('::').each do |portion|
      portion = 'Object' if portion.empty?
      unless lookup_container.const_defined? portion
        new_module = Module.new
        lookup_container.const_set portion, new_module
      end
      lookup_container = lookup_container.const_get portion 
    end
    lookup_container
  end
  
  def lookup_or_create_class(name, superclass)
    already_defined = lookup_const name
    return already_defined unless already_defined.nil?

    container_name = name.match(/^(.*)::\w+$/) ? $1 : 'Object'
    container = lookup_or_create_module container_name
    new_class = Class.new(superclass)
    container.const_set name.to_s.split('::').last, new_class
    new_class
  end
end

module Kernel
  def until_no_change(object)
    loop do
      old_object = object
      object = yield object
      return object if old_object == object
    end
  end

  def ensure_once(key = caller(1, 1).first)
    @ensure_once_events_already_covered ||= {}
    if @ensure_once_events_already_covered.include? key
      @ensure_once_events_already_covered[key]
    else
      value = yield
      @ensure_once_events_already_covered[key] = value
      value
    end
  end
end

class Set
  alias_method :<, :proper_subset?   unless public_method_defined? :<
  alias_method :>, :proper_superset? unless public_method_defined? :>
  alias_method :<=, :subset?   unless public_method_defined? :<=
  alias_method :>=, :superset? unless public_method_defined? :>=
end

module Enumerable
  def find_one(&block)
    raise ArgumentError, "find_one expects a block" unless block_given?
    elems = select &block
    raise ArgumentError, "Element not found" if elems.empty?
    raise ArgumentError, "Multiple elements found" if elems.count > 1
    elems.first
  end
end
