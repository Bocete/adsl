# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name        = "adsl"
  s.version     = "0.1.0"
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Ivan Bocic"]
  s.email       = ["bo@cs.ucsb.edu"]
  s.homepage    = "http://cs.ucsb.edu/~bo/adsl/"
  s.license     = "GNU LGPL 3"
  s.summary     = "A library for formal verification of Rails models"
  s.description = "A tool for automatic extraction and verification of Rails formal models. Just include it in your Gemfile, write a few invariants, setup Spass and `rake verify`!"

  s.required_ruby_version = '>= 1.9.3'

  s.files        = Dir.glob('{bin,lib}/**/*') + %w(LICENSE README.md Gemfile)
  s.test_files   = Dir.glob('test/**/*_test.rb')
  s.executables  = []
  s.require_path = 'lib'

  s.add_development_dependency 'rake'
  s.add_development_dependency 'rails'#, '~> 3'
  s.add_development_dependency 'sqlite3'
  s.add_development_dependency 'minitest', '~> 4'
  s.add_development_dependency 'minitest-reporters'
  s.add_development_dependency 'cancan'

  s.add_dependency 'rexical'
  s.add_dependency 'racc'
  s.add_dependency 'activesupport'#, '~> 3'
  s.add_dependency 'i18n' # activesupport crashes without it
  s.add_dependency 'colorize'
  s.add_dependency 'method_source', '~> 0.8'
  s.add_dependency 'ruby_parser', '~> 3.1'
  s.add_dependency 'ruby2ruby'
  s.add_dependency 'backports'
  s.add_dependency 'activerecord'#, '~> 3.2' # used for code extraction only
  s.add_dependency 'activerecord-tableless'
#  s.add_dependency 'test-unit' # not a development dependency as there is an issue with test-unit vs minitest gem inclusion
  
end

