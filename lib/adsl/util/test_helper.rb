require 'active_support/core_ext/numeric/time'
require 'minitest/unit'
require 'minitest/autorun'
require 'adsl/parser/adsl_parser.tab'
require 'adsl/prover/engine'
require 'adsl/util/general'
require 'adsl/ds/data_store_spec'
require 'adsl/translation/ds_extensions'
require 'adsl/translation/verification_problems'

class MiniTest::Unit::TestCase
  TESTING_TIMEOUT = 5.seconds
  
  def adsl_assert(expected_result, input, options={})
    options[:timeout] ||= TESTING_TIMEOUT

    ds_spec = ADSL::Parser::ADSLParser.new.parse input
    raise "Exactly one action required in ADSL" if ds_spec.actions.length != 1
    action_name = ds_spec.actions.first.name
    provers = (options[:prover] || ['spass', 'z3', 'z3_unsorted']).to_a
    provers.each do |prover|
      if options.include?(:conjecture) 
        problems = [ADSL::Translation::FOLVerificationProblem.new(options[:conjecture])]
      else
        problems = ds_spec.generate_problems action_name
      end
      translation = ds_spec.translate_action(action_name, *problems.flatten)
      fol = translation.to_fol.optimize!

      engine = ADSL::Prover::Engine.new prover, fol, :timeout => options[:timeout]
      
      result = engine.run
      if result[:result] == :unknown || result[:result] == :timeout
        message "inconclusive result"# on testcase #{self.class.name}.#{method_name}"
      else
        errmsg = "Error for prover #{prover}\ninput:\n#{result[:input]}"
	      assert_equal expected_result, result[:result], errmsg 
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

  def unload_method(klass, method_name)
    unless klass.respond_to? :class_eval
      const = self.class.lookup_const klass
      return if const.nil?
      klass = const
    end
    return unless klass.respond_to? method_name

    klass.class_eval "undef :#{ method_name }"
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

  def assert_false(actual, failure_msg = nil)
    assert !actual, failure_msg
  end

  def assert_not_equal(expected, actual, failure_msg = nil)
    failure_msg ||= "Elements asserted to be equal: #{expected}, #{actual}"
    assert expected != actual, failure_msg
  end

  def assert_nothing_raised(failure_msg = nil)
    yield
  rescue StandardError => e
    flunk "Exception raised: #{ e.message }"
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

  def assert_block(msg = nil)
    val = yield
    assert val, msg
  end

  def assert_equal_nospace(s1, s2)
    s1nospace = s1.gsub /\s+/m, ''
    s2nospace = s2.gsub /\s+/m, ''
    assert_equal s1nospace, s2nospace, "#{s1} expected, but was #{s2}"
  end

  def assert_include_nospace(s1, s2)
    s1nospace = s1.gsub /\s+/, ''
    s2nospace = s2.gsub /\s+/, ''
    assert s1nospace.include?(s2nospace), "#{s1} does not include #{s2}"
  end
end
