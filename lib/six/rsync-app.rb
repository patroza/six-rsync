# encoding: UTF-8

# TODO: Cleanup mess

require 'log4r'
require 'six/rsync'
require 'six/rsync/options'

module Six
  module Repositories
    module Rsync
      COMPONENT = 'six-rsync'

      # Create loggers
      @@log = Log4r::Logger.new(COMPONENT)
      if defined?(DEBUG)
        format1 = Log4r::PatternFormatter.new(:pattern => "[%l] %d: %m", :date_pattern => '%H:%M:%S')
      else
        format1 = Log4r::PatternFormatter.new(:pattern => "%m")
      end
      format2 = Log4r::PatternFormatter.new(:pattern => "[%l] %c %d: %m", :date_pattern => '%H:%M:%S')

      # Create Outputters
      o_file = Log4r::FileOutputter.new "#{COMPONENT}-file",
        'level' => 0, # All
      :filename => "#{COMPONENT}.log",
        'formatter' =>  format2
      #:maxsize => 1024

      @@log.outputters << o_file

      o_out = Log4r::StdoutOutputter.new "#{COMPONENT}-stdout",
        'level' => 2, # no DEBUG
      'formatter' =>  format1

      o_err = Log4r::StderrOutputter.new "#{COMPONENT}-stderr",
        'level' => 4, # Error and Up
      'formatter' =>  format1

      @@log.outputters << o_out << o_err

      module_function
      def logger
        @@log
      end
      def host
        @@host
      end
      class App
        attr_reader :repo
        def logger
          Six::Repositories::Rsync.logger
        end

        def initialize(folder)
          @folder = folder
          @repo = Six::Repositories::Rsync.open(folder, :log => logger)
        end

        def self.open(folder)
          app = self.new(folder)
          app
        end

        def self.commit(folder)
          app = self.new(folder)
          app.repo.commit
          app
        end

        def self.update(folder)
          app = self.new(folder)
          app.repo.update
          app
        end

        def self.clone(folder)
          folder[/(.*)[\/|\\](.*)/]
          pa, folder = $1, $2
          @repo = Six::Repositories::Rsync.clone(Six::Repositories::Rsync.host, folder, :path => pa, :log => Six::Repositories::Rsync.logger)
        end

        def self.init(folder)
#          if File.exists?(folder)
#            logger.error "#{folder} already exists!"
#            Process.exit
#          end
          Six::Repositories::Rsync.init(folder, :log => Six::Repositories::Rsync.logger)
        end
      end

      parse_options

      unless ARGV[0]
        logger.error "No folder argument given!"
        Process.exit
      end


      #app = App.new(ARGV[0])
      @@options.each do |option|
        App.send option, ARGV[0]
      end
    end
  end
end
