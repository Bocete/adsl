class Numeric
  def integer?
    self == self.to_i
  end

  def positive?
    self > 0
  end

  def negative?
    self < 0
  end

  def round?
    self == round
  end

  INFINITY = 1.0/0.0
end
