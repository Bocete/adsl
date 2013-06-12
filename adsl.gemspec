# -*- encoding: utf-8 -*-

lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
 
Gem::Specification.new do |s|
  s.name        = "adsl"
  s.version     = "0.0.3"
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Ivan Bocic"]
  s.email       = ["bo@cs.ucsb.edu"]
  s.homepage    = "http://cs.ucsb.edu/~bo/adsl/"
  s.license     = "GNU LGPL 3"
  s.summary     = "A tool for parsing ADSL and translating it into Spass"
  s.description = "ADSL parses ADSL specification, translating it into Spass for verification"

  s.required_ruby_version = '~> 1.8.7'

  s.files        = Dir.glob("{bin,lib}/**/*") + %w(LICENSE README.md Gemfile)
  s.executables  = ['adsl-verify']
  s.require_path = 'lib'

  s.add_development_dependency 'rake'
  s.add_development_dependency 'test-unit'

  s.add_dependency 'rexical'
  s.add_dependency 'racc'
  s.add_dependency 'active_support'
  s.add_dependency 'colorize'
  s.add_dependency 'i18n'

end

