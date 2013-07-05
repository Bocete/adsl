$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
 
ENV["RAILS_ENV"] ||= 'test'
 
def initialize_test_context
  eval <<-ruby 
    class ::Asd < ActiveRecord::Base
      has_many :blahs, :class_name => 'Mod::Blah'
    end

    class ::Kme < Asd
    end

    module ::Mod
      class Blah < ActiveRecord::Base
        belongs_to :asd
      end
    end
    
    class ::ApplicationController < ActionController::Base
      def respond_to
        if block_given?
          yield
        else
          render nothing: true
        end
      end
    end

    class ::AsdsController < ::ApplicationController
      def index;   respond_to; end
      def show;    respond_to; end
      def new;     respond_to; end
      def create;  respond_to; end
      def update;  respond_to; end
      def destroy; respond_to; end
      def nothing; respond_to; end
    end
  ruby
end

# Only the parts of rails we want to use
# if you want everything, use "rails/all"
require "action_controller/railtie"

if ENV["RAILS_ENV"] == 'test'

  # Define the application and configuration
  class ADSLRailsTestApplication < ::Rails::Application
    # configuration here if needed
    config.assets.enabled = false
    config.active_support.deprecation = :stderr
    config.secret_token = 'RandomTextRequiredByARecentVersionOfRakeOrWhateverWhoCaresThisIsUsedForGemTestingOnly'
  end

  logger = Logger.new(STDOUT)
  logger.level = Logger::ERROR
  # silence is getting deprecated in Rails 4.0
  # not sure why, the alternatives are not nearly as convenient
  def logger.adsl_silence
    old_level = self.level
    self.level = 6
    yield
  ensure
    self.level = old_level
  end

  Rails.logger = logger


  ActiveRecord::Base.establish_connection(
    :adapter => 'sqlite3',
    :database => ':memory:',
    :verbosity => 'quiet'
  )
 
  # Initialize the application
  ADSLRailsTestApplication.initialize!
  ADSLRailsTestApplication.routes.draw do
    resources :asds do
      collection do
        get :nothing
      end
    end
  end

  # Initialize the test activerecord schema
  ActiveRecord::Migration.verbose = false
  ActiveRecord::Schema.define do
    create_table :asds do |t|
      t.string :type
    end
    create_table :blahs do |t|
      t.integer :asd_id
    end
  end
end

