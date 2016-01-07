require 'adsl/util/general'
require 'active_record'
require 'action_controller'
require 'action_view'

$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
 
ENV["RAILS_ENV"] ||= 'test'

def initialize_test_context
  Object.lookup_or_create_class('::Asd', ActiveRecord::Base).class_exec do
    has_many :blahs, :class_name => 'Mod::Blah'
    has_many :kmes, :through => :blahs, :source => :kme12, :dependent => :destroy
  end
  
  Object.lookup_or_create_class('::Kme', Asd).class_exec do
    belongs_to :blah, :class_name => 'Mod::Blah', :dependent => :delete
  end
  
  Object.lookup_or_create_class('::Mod::Blah', ActiveRecord::Base).class_exec do
    belongs_to :asd
    has_one :kme12, :class_name => 'Kme', :dependent => :delete
  end

  Object.lookup_or_create_class('::ApplicationController', ActionController::Base).class_exec do
    def respond_to
      # allow for empty render statements, for testing purposes only
      if block_given?
        super
      else
        render :nothing => true
      end
    end

    def render(options = {}, extra_options = nil, &block)
      options ||= {}
      options[:nothing] = true
      super
    end
    
    def authorize!; end
    def load_resource; end
    def should_authorize?; false; end
    def should_load_resource?; false; end

    def self.authorize_resource(*args)
      ApplicationController.class_exec do
        def should_authorize?; true; end
      end
    end
    
    def self.load_resource(*args)
      ApplicationController.class_exec do
        def should_load_resource?; true; end
      end
    end

    def self.load_and_authorize_resource
      load_resource
      authorize_resource
    end

    # no templates exist and we do not care
    rescue_from ActionView::MissingTemplate do; end
  end

  Object.lookup_or_create_class('::AsdsController', ApplicationController).class_exec do
    def index;   respond_to; end
    def show;    respond_to; end
    def new;     respond_to; end
    def create;  respond_to; end
    def edit;    respond_to; end
    def update;  respond_to; end
    def destroy; respond_to; end
    def nothing; respond_to; end

    before_filter :before,  :only => :before_filter_action
    before_filter :before2, :only => :before_filter_action
    after_filter  :after,   :only => :after_filter_action

    before_filter :before_nothing, :only => :nothing
    after_filter  :after_nothing,  :only => :nothing

    def before_filter_action; respond_to; end
    def after_filter_action;  respond_to; end
    
    def before; end
    def before2; end
    def after; end

    def before_nothing; end
    def after_nothing; end

    before_filter :load_resource
    before_filter :authorize!
  end
end

def teardown_test_context
  unload_class :Asd, :Kme, 'Mod::Blah'
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
    config.action_dispatch.show_exceptions = false
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
        get :before_filter_action
        get :after_filter_action
        get :around_filter_action
      end
    end
  end

  # Initialize the test activerecord schema
  ActiveRecord::Migration.verbose = false
  ActiveRecord::Schema.define do
    create_table :asds do |t|
      t.string :field
    end
    create_table :blahs do |t|
      t.integer :asd_id
    end
    create_table :users do |t|
      t.string :name
      t.boolean :is_admin
    end
  end
end

def define_cancan_suite
  require 'cancan'
  Object.lookup_or_create_class('::User', ActiveRecord::Base).class_exec do
    has_many :asds
  end
  Object.lookup_or_create_class('::Asd', ActiveRecord::Base).class_exec do
    belongs_to :user
  end
  Object.lookup_or_create_class('::Ability', Object).class_exec do
    include ::CanCan::Ability
  end
end

def teardown_cancan_suite
  unload_class :Ability, :User
end
