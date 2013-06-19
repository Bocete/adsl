require 'rake/testtask'

parser_dir = "./lib/parser"

namespace :build do
  desc "Generate Lexer & Parser"
  task :parser do
    %x(rex -o #{parser_dir}/adsl_parser.rex.rb #{parser_dir}/adsl_parser.rex)
    %x(racc -o #{parser_dir}/adsl_parser.tab.rb #{parser_dir}/adsl_parser.racc)
  end
end
task :build => ["build:parser"]

namespace :test do
  namespace :unit do
    desc "Test Lexer & Parser"
    task :parser => ["build:parser"]
    Rake::TestTask.new(name=:parser) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/parser/*_test.rb']
      t.verbose = true
    end

    desc "Test Util"
    Rake::TestTask.new(name=:util) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/util/*_test.rb']
      t.verbose = true
    end
    
    desc "Test First Order Logic"
    Rake::TestTask.new(name=:fol) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/fol/*_test.rb']
      t.verbose = true
    end
    
    desc "Test Spass Translator"
    Rake::TestTask.new(name=:spass) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/spass/*_test.rb']
      t.verbose = true
    end
    
    desc "Test DataStoreSpec"
    Rake::TestTask.new(name=:ds) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/ds/*_test.rb']
      t.verbose = true
    end
    
    desc "Test Extract"
    Rake::TestTask.new(name=:extract) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/extract/*_test.rb']
      t.verbose = true
    end
  end

  task :unit => ["test:unit:parser", "test:unit:util", "test:unit:ds", "test:unit:fol", "test:unit:spass", "test:unit:extract"]

  Rake::TestTask.new(name=:integration) do |t|
    t.libs += ["lib"]
    t.test_files = FileList['test/integration/*_test.rb']
    t.verbose = true
  end
end

task :test => ["test:unit", "test:integration"]
