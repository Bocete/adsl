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
    
    desc "Test The Prover Engine"
    Rake::TestTask.new(name=:prover) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/adsl/prover/**/*_test.rb']
      t.verbose = true
    end
    
    desc "Test DataStoreSpec"
    Rake::TestTask.new(name=:ds) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/adsl/ds/**/*_test.rb']
      t.verbose = true
    end

    desc "Test Synthesis"
    Rake::TestTask.new(name=:synthesis) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/adsl/synthesis/**/*_test.rb']
      t.verbose = true
    end
    
    desc "Test Extract"
    Rake::TestTask.new(name=:extract) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/adsl/extract/**/*_test.rb']
      t.verbose = true
    end
    
    desc "Test Translation"
    Rake::TestTask.new(name=:translation) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/unit/adsl/translation/**/*_test.rb']
      t.verbose = true
    end
  end

  desc "Test All Units"
  Rake::TestTask.new(name=:units) do |t|
    t.libs += ["lib"]
    t.test_files = FileList['test/unit/adsl/**/*_test.rb']
    t.verbose = true
  end
 

  namespace :integrations do
    Rake::TestTask.new(name=:prover) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/integration/prover/**/*_test.rb']
      t.verbose = true
    end
   
    namespace :extract do
      Rake::TestTask.new(name=:basic) do |t|
        t.libs += ["lib"]
        t.test_files = FileList['test/integration/extract/basic_test.rb']
        t.verbose = true
      end

      Rake::TestTask.new(name=:branch) do |t|
        t.libs += ["lib"]
        t.test_files = FileList['test/integration/extract/branch_test.rb']
        t.verbose = true
      end
    end
    Rake::TestTask.new(name=:extract) do |t|
      t.libs += ["lib"]
      t.test_files = FileList['test/integration/extract/**/*_test.rb']
      t.verbose = true
    end

#    namespace :sails do
#      desc 'Setup Sails installation to verify code synthesis'
#      task :setup do
#        require 'adsl/synthesis/sails/test_helper'
#        ADSL::Synthesis::Sails::TestHelper.setup
#      end
#
#      desc 'Cleanup Sails installation used to verify code synthesis'
#      task :cleanup do
#        require 'adsl/synthesis/sails/test_helper'
#        ADSL::Synthesis::Sails::TestHelper.cleanup
#      end
#
#      desc 'test whether tests work in general'
#      task :basic => ["integrations:sails:setup"]
#      Rake::TestTask.new(name=:basic) do |t|
#        t.libs += ["lib"]
#        t.test_files = FileList['test/integration/sails/basic/**/*_test.rb']
#        t.verbose = true
#      end
#
#      desc 'association generation and dereferencing'
#      task :schema => ["integrations:sails:setup"]
#      Rake::TestTask.new(name=:schema) do |t|
#        t.libs += ["lib"]
#        t.test_files = FileList['test/integration/sails/schema/**/*_test.rb']
#        t.verbose = true
#      end
#    end
#
#    task :sails => ["integrations:sails:setup"]
#    Rake::TestTask.new(name=:sails) do |t|
#      t.libs += ["lib"]
#      t.test_files = FileList['test/integration/sails/**/*_test.rb']
#      t.verbose = true
#    end
  end
  
  desc "Test All Integrations"
  Rake::TestTask.new(name=:integrations) do |t|
    t.libs += ["lib"]
    t.test_files = FileList['test/integration/**/*_test.rb']
    t.verbose = true
  end
end

task :test => ["test:units", "test:integrations"]
