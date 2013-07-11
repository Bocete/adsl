require 'test/unit'
require 'adsl/spass/ruby_extensions'

class ADSL::Spass::RubyExtensionsTest < Test::Unit::TestCase
  def test_string__resolve_params_distinct_identifiers
    a = "asd(${1}, ${2})"
    assert_equal "asd(a, b)", a.resolve_params(:a, :b)
    assert_raise ArgumentError do
      a.resolve_params(:s)
    end
    assert_equal "asd(s, k)", a.resolve_params(:s, :k, :r)
  end
  
  def test_string__resolve_params_repeating_identifiers
    a = "asd(${1}, ${2}): ${1}"
    assert_equal "asd(a, b): a", a.resolve_params(:a, :b)
    assert_raise ArgumentError do
      a.resolve_params(:s)
    end
    assert_equal "asd(s, k): s", a.resolve_params(:s, :k, :r)
  end
  
  def test_symbol__to_spass_string
    assert_nothing_raised do
      :a.to_spass_string
    end
    assert_equal "a", :a.to_spass_string
    assert_equal "kme", :kme.to_spass_string
  end
  
  def test_string__to_spass_string
    assert_nothing_raised do
      "a".to_spass_string
    end
    assert_equal "a", "a".to_spass_string
    assert_equal "kme", "kme".to_spass_string
  end
end

