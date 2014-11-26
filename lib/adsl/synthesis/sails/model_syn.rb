require 'adsl/util/general'
require 'adsl/synthesis/sails/ds_extensions'
require 'fileutils'

module ADSL
  module Synthesis
    module Sails
      class ModelSyn
        attr_accessor :ds, :members

        def initialize(ds, dir)
          @ds = ds
          raise ArgumentError, "Invalid data store spec type: #{ds.class}" unless ds.is_a? ADSL::DS::DSSpec
          raise ArgumentError, "Sails app dir does not exist" unless File.exist? dir
          raise ArgumentError, "Sails app dir is not a directory" unless File.directory? dir
          @dir = dir
        end

        def create_model_files
          model_dir = File.join @dir, 'api/models'
          FileUtils.makedirs model_dir
          @ds.classes.each do |klass|
            js = klass.to_sails_string @ds
            file_path = File.join model_dir, "#{ klass.name }.js"
            File.open file_path, 'w+' do |f|
              f.write js
            end
          end
        end

      end
    end
  end
end
