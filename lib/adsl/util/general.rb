require 'set'
require 'open3'
require 'thread'
require 'active_support'
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
end

class Time
  def self.time_execution
    pre = Time.now
    yield
    ((Time.now - pre)*1000).to_i
  end
end

class Array
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
  # returns stdout of the process that terminates first
  # not completely thread safe; cannot be with 1.8.7
  def process_race(*commands)
    parent_thread = Thread.current
    mutex = Mutex.new
    children_threads = []
    spawned_pids = []
    result = nil
    mutex.synchronize do
      commands.each do |command|
        children_threads << Thread.new do
          begin
            sleep 0.1
            pipe = IO.popen command, 'r'
            spawned_pids << pipe.pid
            output = pipe.read
            mutex.synchronize do
              result = output if result.nil?
              parent_thread.run
            end
          rescue => e
            parent_thread.raise e unless e.message == 'die!'
          end
        end
      end
    end
    Thread.stop
    return result
  ensure
    children_threads.each do |child|
      child.raise 'die!'
    end
    spawned_pids.each do |pid|
      Process.kill 'HUP', pid
    end
  end

  def until_no_change(object)
    loop do
      old_object = object
      object = yield object
      return object if old_object == object
    end
  end
end
