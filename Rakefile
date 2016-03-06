require 'rake/testtask'

parser_dir = "./lib/adsl/lang/parser"

def unit_test(pattern)
  File.join "test/unit/adsl", pattern, "**/*_test.rb"
end

namespace :build do
  desc "Generate Lexer & Parser"
  task :parser do
    %x(rex -o #{parser_dir}/adsl_parser.rex.rb #{parser_dir}/adsl_parser.rex)
    %x(racc -o #{parser_dir}/adsl_parser.tab.rb #{parser_dir}/adsl_parser.racc)
  end
end
task :build => ["build:parser"]

namespace :test do

  unit_test_dirs = ['ds', 'extract', 'fol', 'lang', 'prover', 'util']

  namespace :unit do
    desc "Test the language and parser"
    task :lang => ["build:parser"]

    unit_test_dirs.each do |dir|
      Rake::TestTask.new(name=dir) do |t|
        t.libs += ['lib', 'test']
        t.test_files = FileList[unit_test dir]
        t.verbose = true
      end
    end
  end

  desc "Test All Units"
  Rake::TestTask.new(name=:unit) do |t|
    t.libs += ['lib', 'test']
    t.test_files = FileList['test/unit/adsl/**/*_test.rb']
    t.verbose = true
  end

  namespace :integration do
    namespace :prover do
      Rake::TestTask.new(name=:basic) do |t|
        t.libs += ['lib', 'test']
        t.test_files = FileList['test/integration/prover/basic_test.rb']
        t.verbose = true
      end

      Rake::TestTask.new(name=:branch) do |t|
        t.libs += ['lib', 'test']
        t.test_files = FileList['test/integration/prover/branch_test.rb']
        t.verbose = true
      end
      
      Rake::TestTask.new(name=:ac) do |t|
        t.libs += ['lib', 'test']
        t.test_files = FileList['test/integration/prover/access_control_test.rb']
        t.verbose = true
      end
    end
    Rake::TestTask.new(name=:prover) do |t|
      t.libs += ['lib', 'test']
      t.test_files = FileList['test/integration/prover/**/*_test.rb']
      t.verbose = true
    end
   
    namespace :extract do
      Rake::TestTask.new(name=:basic) do |t|
        t.libs += ['lib', 'test']
        t.test_files = FileList['test/integration/extract/basic_test.rb']
        t.verbose = true
      end

      Rake::TestTask.new(name=:branch) do |t|
        t.libs += ['lib', 'test']
        t.test_files = FileList['test/integration/extract/branch_test.rb']
        t.verbose = true
      end

      Rake::TestTask.new(name=:ac) do |t|
        t.libs += ['lib', 'test']
        t.test_files = FileList['test/integration/extract/access_control_test.rb']
        t.verbose = true
      end
    end
    Rake::TestTask.new(name=:extract) do |t|
      t.libs += ['lib', 'test']
      t.test_files = FileList['test/integration/extract/**/*_test.rb']
      t.verbose = true
    end
  end
  
  desc "Test All Integrations"
  Rake::TestTask.new(name=:integration) do |t|
    t.libs += ['lib', 'test']
    t.test_files = FileList['test/integration/**/*_test.rb']
    t.verbose = true
  end
end
