require 'rake/testtask'

parser_dir = "./lib/adsl/parser"

namespace :build do
  desc "Generate Lexer & Parser"
  task :parser do
    %x(rex -o #{parser_dir}/adsl_parser.rex.rb #{parser_dir}/adsl_parser.rex)
    %x(racc -o #{parser_dir}/adsl_parser.tab.rb #{parser_dir}/adsl_parser.racc)
  end
end
task :build => ["build:parser"]

namespace :test do
  namespace :units do
    desc "Test Lexer & Parser"
    task :parser => ["build:parser"]
    Rake::TestTask.new(name=:parser) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/adsl/parser/**/*_test.rb']
      t.verbose = true
    end

    desc "Test Util"
    Rake::TestTask.new(name=:util) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/adsl/util/**/*_test.rb']
      t.verbose = true
    end
    
    desc "Test First Order Logic"
    Rake::TestTask.new(name=:fol) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/adsl/fol/**/*_test.rb']
      t.verbose = true
    end
    
    desc "Test Spass Translator"
    Rake::TestTask.new(name=:spass) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/adsl/spass/**/*_test.rb']
      t.verbose = true
    end
    
    desc "Test DataStoreSpec"
    Rake::TestTask.new(name=:ds) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/adsl/ds/**/*_test.rb']
      t.verbose = true
    end
    
    desc "Test Extract"
    Rake::TestTask.new(name=:extract) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/adsl/extract/**/*_test.rb']
      t.verbose = true
    end
    
    desc "Test Verification"
    Rake::TestTask.new(name=:verification) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/adsl/verification/**/*_test.rb']
      t.verbose = true
    end
  end

  desc "Test All Units"
  Rake::TestTask.new(name=:units) do |t|
    t.libs += ["lib"]
    t.test_files = FileList['test/unit/adsl/**/*_test.rb']
    t.verbose = true
  end

  Rake::TestTask.new(name=:integrations) do |t|
    t.libs += ["lib"]
    t.test_files = FileList['test/integration/**/*_test.rb']
    t.verbose = true
  end
end

task :test => ["test:units", "test:integrations"]
