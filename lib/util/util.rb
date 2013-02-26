require 'set'
require 'open3'
require 'thread'

class String
  def increment_suffix
    suffix = scan(/_\d+$/).first
    if suffix.nil?
      return self + "_2"
    else
      return self[0, self.length - suffix.length] + '_' + (suffix.to_i + 1).to_s
    end
  end
end

class Time
  def self.time_execution
    pre = Time.now
    yield
    ((Time.now - pre)*1000).to_i
  end
end

def container_for(*fields, &block)
  raise ArgumentError, 'Field list empty' if fields.empty?

  all_fields = Set.new(fields)
  if methods.include? "container_for_fields"
    all_fields.merge send(:container_for_fields)
  end
  singleton_class = (class << self; self; end)
  singleton_class.send :define_method, :container_for_fields, lambda{all_fields}

  attr_accessor *fields

  self.send(:define_method, :initialize) do |*options|
    options = options.empty? ? {} : options[0]
    options ||= {}
    options_trimmed = Hash[options]

    all_fields.each do |field|
      instance_variable_set "@#{field}".to_sym, options_trimmed.delete(field.to_sym)
    end
    if block
      instance_eval &block
    elsif not options_trimmed.empty?
      raise ArgumentError, "Undefined fields mentioned in initializer: #{options_trimmed.keys.map{ |key| ":#{key.to_s}"}.join(", ")}"
    end
  end

  send :define_method, :recursively_gather do |method|
    to_inspect = [self]
    inspected = Set[]
    while not to_inspect.empty?
      elem = to_inspect.pop
      inspected << elem
      if elem.class.methods.include? 'container_for_fields'
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
