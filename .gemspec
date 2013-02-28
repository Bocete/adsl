# -*- encoding: utf-8 -*-

lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
 
Gem::Specification.new do |s|
  s.name        = "adsl"
  s.version     = "0.0.0"
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Ivan Bocic"]
  s.email       = ["bo@cs.ucsb.edu"]
  s.homepage    = "http://cs.ucsb.edu/~bo/adsl/"
  s.summary     = "A tool for parsing ADSL and translating it into Spass"
  s.description = "ADSL parses ADSL specification, translating it into Spass for verification"
 
  s.files        = Dir.glob("{bin,lib}/**/*") + %w(LICENSE README.md ROADMAP.md CHANGELOG.md)
  s.executables  = ['adsl-verify']
  s.require_path = 'lib'
end

