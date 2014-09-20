require 'set'
require 'open3'
require 'thread'
require 'active_support'
require 'active_support/core_ext/module'
require 'tempfile'

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

class Array
  def each_index_with_elem(&block)
    return each_index_without_elem(&block) if block.nil? or block.arity < 2
    count.times.each do |index|
      block[self[index], index]
    end
    self
  end
  alias_method_chain :each_index, :elem
  
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

class Fixnum
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
      return nil unless lookup_container.const_defined? portion
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
  
  def container_for(*fields, &block)
    all_fields = Set.new(fields)
    if respond_to? :container_for_fields
      prev_fields = send :container_for_fields
      all_fields.merge prev_fields
    end
    singleton_class.send :define_method, :container_for_fields, lambda{ all_fields }
    singleton_class.send :define_method, :recursively_comparable do
      send :define_method, :eql? do |other|
        return false if other.class != self.class
        self.class.container_for_fields.each do |field|
          f1 = self.send field
          f2 = other.send field
          if f1.respond_to?(:each) && f2.respond_to?(:each)
            return false if f1.count != f2.count
            f1.zip(f2).each do |e1, e2|
              return false unless f1.eql? f2
            end
          else
            return false unless f1.eql? f2
          end
        end
        return true
      end
      alias_method :==, :eql?
      send :define_method, :hash do
        [*self.class.container_for_fields.map{ |f| self.send f }].hash
      end
      send :define_method, :dup do
        new_values = {}
        self.class.container_for_fields.each do |field_name|
          value = send field_name
          new_values[field_name] = value.respond_to?(:dup) ? value.dup : value
        end
        self.class.new new_values
      end
    end

    attr_accessor *fields

    send :define_method, :initialize do |*options|
      options = options.empty? ? {} : options[0]
      options ||= {}
      options_trimmed = Hash[options]

      all_fields.each do |field|
        instance_variable_set "@#{field}".to_sym, options_trimmed.delete(field.to_sym)
      end
      if block
        instance_eval &block
      elsif not options_trimmed.empty?
        raise ArgumentError, "Undefined fields mentioned in initializer of #{self.class}: #{options_trimmed.keys.map{ |key| ":#{key.to_s}"}.join(", ")}" + "\n[#{all_fields.to_a.join ' ' }]"
      end
    end

    send :define_method, :recursively_gather do |method|
      to_inspect = [self]
      inspected = Set[]
      while not to_inspect.empty?
        elem = to_inspect.pop
        inspected << elem
        if elem.class.respond_to? :container_for_fields
          elem.class.container_for_fields.each do |field|
            field_val = elem.send(field)
            next if field_val.nil?
            [field_val].flatten.each do |subval|
              to_inspect << subval unless inspected.include?(subval)
            end
          end
        end
      end
      result = Set[]
      inspected.each do |val|
        result = result + [val.send(method)].flatten if val.class.method_defined?(method)
      end
      result.delete_if{ |a| a.nil? }.flatten
    end
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
end
