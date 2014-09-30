require 'active_support/core_ext/numeric/time'
require 'test/unit'
require 'adsl/parser/adsl_parser.tab'
require 'adsl/prover/engine'
require 'adsl/util/general'
require 'adsl/ds/data_store_spec'
require 'adsl/translation/ds_extensions'

class Test::Unit::TestCase
  TESTING_TIMEOUT = 5.seconds
  
  def adsl_assert(expected_result, input, options={})
    options[:timeout] ||= TESTING_TIMEOUT

    ds_spec = ADSL::Parser::ADSLParser.new.parse input
    raise "Exactly one action required in ADSL" if ds_spec.actions.length != 1
    action_name = ds_spec.actions.first.name
    provers = (options[:prover] || ['spass', 'z3']).to_a
    provers.each do |prover|
      translation = ds_spec.translate_action(action_name)
      fol = translation.to_fol.optimize!
      fol.conjecture = options[:conjecture] if options.include? :conjecture

      engine = ADSL::Prover::Engine.new prover, fol, :timeout => options[:timeout]
      
      result = engine.run[:result]
      if result == :unknown || result == :timeout
        puts "inconclusive result on testcase #{self.class.name}.#{method_name}"
      else
        puts fol.to_spass_string if expected_result != result
	assert_equal expected_result, result
      end
    end
  end

  def unload_class(*classes)
    classes.each do |klass_name|
      const = self.class.lookup_const klass_name
      next if const.nil?
      const.parent_module.send :remove_const, const.name.split('::').last
    end
  end

  def class_defined?(*classes)
    classes.each do |klass_name|
      return true unless self.class.lookup_const(klass_name).nil?
    end
    return false
  end

  def in_temp_file(content)
    Tempfile.with_tempfile content do |path|
      yield path
    end
  end

  def assert_set_equal(expected, actual, failure_msg = nil)
    expected.each do |elem|
      assert_block failure_msg || "Actual collection does not contain `#{elem}'" do
        actual.include? elem
      end
    end
    actual.each do |elem|
      assert_block failure_msg || "Expected collection does not contain `#{elem}'" do
        expected.include? elem
      end
    end
  end

  def assert_all_different(objects = {})
    counts = Hash.new{ |key, val| [] }
    objects.each{ |name, o| counts[o] << name }
    counts.each do |object, names|
      assert_equal 1, names.length, "Multiple identical objects found. Keys: #{ names.map(&:to_s).join(', ') }"
    end
  end

  def assert_equal_nospace(s1, s2)
    s1nospace = s1.gsub /\s+/, ''
    s2nospace = s2.gsub /\s+/, ''
    assert_equal s1nospace, s2nospace, "#{s1} expected, but was #{s2}"
  end

  def assert_include_nospace(s1, s2)
    s1nospace = s1.gsub /\s+/, ''
    s2nospace = s2.gsub /\s+/, ''
    assert s1nospace.include?(s2nospace), "#{s1} does not include #{s2}"
  end
end
