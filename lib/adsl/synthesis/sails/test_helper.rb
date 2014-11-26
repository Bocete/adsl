require 'tmpdir'
require 'fileutils'
require 'open3'
require 'adsl/synthesis/sails/model_syn'
require 'adsl/parser/adsl_parser.tab'
require 'active_support/json'

module ADSL
  module Synthesis
    module Sails
      module TestHelper

        TEST_APP_NAME = 'adsl_sails_syn_test_app'
        TEST_DIR = File.join Dir.tmpdir, TEST_APP_NAME

        def self.setup_already?
          return false unless File.exist? TEST_DIR
          return false unless File.directory? TEST_DIR
          true
        end

        def self.setup
          return if setup_already?
          begin
            old_working_directory = Dir.pwd

            puts "Setting up sails test directory under #{TEST_DIR}. May take awhile..."

            system <<-BASH
              cd #{Dir.tmpdir} &&
              sails new #{TEST_APP_NAME} &&
              cd #{TEST_DIR} &&
              npm install &&
              npm install grunt
            BASH

            # set the model schema setting to drop
            TestHelper.setSetting 'config/models.js', :migrate => :drop

            puts "Setting up sails done."
          ensure
            Dir.chdir old_working_directory
          end
        end

        def self.cleanup
          FileUtils.remove_entry_secure TEST_DIR if File.exist? TEST_DIR
        end

        def self.setSetting(configFile, options)
          path = File.join TEST_DIR, configFile
          string = File.read path

          deleted = string.gsub /^\s+(\w+): ([\w'"\.]),\s*$/ do |match|
            if options.include? match[1]
              ""
            else
              match[0]
            end
          end

          created = string.gsub /^\s*\n};$/m do |eof|
            "#{
              options.map do |k, v|
                v_str = v.is_a?(String) || v.is_a?(Symbol) ? "'#{v}'" : v.to_s
                "  #{k}: #{v_str},"
              end.join "\n"
            }\n};"
          end

          File.open path, 'w+' do |f|
            f.write created
          end
        end

        def setup
          return if @this_test_suite_setup
          @this_test_suite_setup ||= true

          # synthesize model files according to the adsl variable
          model_dir = File.join(TEST_DIR, 'api/models')
          FileUtils.remove_entry_secure model_dir if File.exist? model_dir

          adsl_source = self.adsl
          parser = ADSL::Parser::ADSLParser.new
          ds = parser.parse adsl_source

          syn = ADSL::Synthesis::Sails::ModelSyn.new ds, TEST_DIR
          syn.create_model_files
        end

        def in_sails_console
          console = SailsConsole.new
          console.start
          yield console
        ensure
          console.close unless console.nil?
        end

        class SailsConsole
          attr_accessor :eol_code

          def initialize
            @eol_code = rand(36**20).to_s(36)
            @read_json = false
          end

          def started?
            [@in, @out].each do |stream|
              return true if stream && !stream.closed?
            end
            false
          end

          def strip_console_header(str)
            str.start_with?('sails> ') ? str[7..-1] : str
          end

          def start
            raise if started?

            @in, @out, @wait_thr = Open3.popen2e "cd \"#{TEST_DIR}\" && sails console"

            # because there does not seem a way to skip the intro messages..
            # let's write a string constant and read until we find its output
            output = self.puts terminate
          end

          def terminate
            "console.log('#{@eol_code}');"
          end

          def inspect(string)
            @read_json = true
            "console.log('%j', #{string});"
          end

          def inspect_and_terminate(string)
            inspect(string) + terminate
          end

          def puts(line)
            command = line + (line.include?(@eol_code) ? "\n" : "\n#{terminate}\n" )
            @in.puts command
            output = ""
            while (line = @out.gets)
              if line.nil?
                raise "Sails console raised an error.  Combined output:\n#{output}"
              end
              line = strip_console_header(line)
              unless (cuthere = line.index(@eol_code)).nil?
                output = output + line.first(cuthere)
                break
              end
              output = output + line
            end
            output.gsub!('undefined', '')
            if @read_json
              @read_json = false
              start_index = output.rindex(/^[^\s]/)
              return nil if start_index.nil?
              last_relevant_line = output[start_index..-1]
              ActiveSupport::JSON.decode(last_relevant_line)
            else
              output.strip
            end
          end
          
          def close
            return unless started?
            [@in, @out].each &:close
            @in, @out = nil, nil
          end
        end

      end
    end
  end
end
