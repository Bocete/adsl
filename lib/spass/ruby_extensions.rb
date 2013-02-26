class Symbol
  def to_spass_string
    to_s
  end
end

class String
  def to_spass_string
    self
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

