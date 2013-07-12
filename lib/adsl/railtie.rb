require 'adsl'
require 'rails'

module ADSL
  class Railtie < Rails::Railtie
    railtie_name :adsl

    rake_tasks do
      desc 'Verify Rails app logic'
      task :verify do
        puts '!'
      end
    end
  end
end
