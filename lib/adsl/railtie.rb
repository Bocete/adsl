require 'adsl'
require 'rails'
require 'adsl/verification/rails_verification'

module ADSL
  class Railtie < Rails::Railtie

    include ADSL::Verification::RailsVerification

    railtie_name :adsl

    rake_tasks do
      desc 'Verify Rails app logic'
      task :verify => :environment do
        verify_spass
      end
    end
  end
end
