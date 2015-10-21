module ADSL
  module Prover
    module Util

      class ProcessRaceExitCodeException < Exception
      end

      # returns stdout of the process that terminates first
      # not completely thread safe; cannot be with 1.8.7
      def self.process_race(*commands)
        if commands.length > 1
          self._multi_process_race commands
        elsif commands.length == 1
          self._single_process_race commands.first
        else
          return nil, nil
        end
      end

      private

      def self._single_process_race(command)
        pid = nil
        output = IO.popen command, :err=>[:child, :out] do |io|
          pid = io.pid
          io.read
        end
        status = $?.exitstatus
        return output, 0
      end

      def self._multi_process_race(commands)
        parent_thread = Thread.current
        mutex = Mutex.new
        children_threads = []
        spawned_pids = []
        result = nil
        mutex.synchronize do
          commands.each_index do |command, index|
            children_threads << Thread.new do
              begin
                #sleep 0.1
                pid = nil
                output = IO.popen command, :err=>[:child, :out] do |io|
                  pid = io.pid
                  io.read
                end
                unless $?.nil?
                  status = $?.exitstatus
                  spawned_pids << pid
                  mutex.synchronize do
                    result = [output, index, status] if result.nil?
                    parent_thread.run
                  end
                end
              rescue => e
                parent_thread.raise e unless e.message == 'die!'
              end
            end
          end
        end
        Thread.stop
        #if result[2] != 0
        #  puts result[0]
        #  raise ProcessRaceExitCodeException, "Return status of command #{commands[result[1]]} was #{result[2]}"
        #end
        return result.first 2
      ensure
        children_threads.each do |child|
          child.terminate
          #child.raise 'die!'
        end
        #spawned_pids.each do |pid|
        #  Process.kill 'HUP', pid if 
        #end
      end

    end
  end
end
