# encoding: UTF-8

# TODO: Cleanup mess

gem 'log4r', '>= 1.1.2'
require 'log4r'
require 'six/rsync'
require 'six/rsync/options'

module Six
  module Repositories
    module Rsync
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

        def self.info(folder)
          app = self.new(folder)
          app.repo.info
          app
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

        def self.status(folder)
          app = self.new(folder)
          app.repo.status
          app
        end

        def self.clone(folder)
          pa = if folder[/[\/|\\]/]
            folder = File.basename(folder) 
            File.dirname(folder)
          else
            Dir.pwd
          end
          @repo = Six::Repositories::Rsync.clone(Six::Repositories::Rsync.host, folder, :path => pa, :log => Six::Repositories::Rsync.logger)
        end

        def self.init(folder)
#          if File.exists?(folder)
#            logger.error "#{folder} already exists!"
#            Process.exit
#          end
          Six::Repositories::Rsync.init(folder, :log => Six::Repositories::Rsync.logger)
        end

        def self.convert(folder)
#          if File.exists?(folder)
#            logger.error "#{folder} already exists!"
#            Process.exit
#          end
          Six::Repositories::Rsync.convert(folder, :log => Six::Repositories::Rsync.logger)
        end
      end

      unless defined?(Ocra)
        options, todo = parse_options

        # Create loggers
        @@log = Log4r::Logger.new(COMPONENT)
        format1 = if defined?(DEBUG)
          Log4r::PatternFormatter.new(:pattern => "[%l] %d: %m", :date_pattern => '%H:%M:%S')
        else
          Log4r::PatternFormatter.new(:pattern => "%m")
        end
        format2 = Log4r::PatternFormatter.new(:pattern => "[%l] %c %d: %m", :date_pattern => '%H:%M:%S')

        # Create Outputters
        if options[:logging]
          o_file = Log4r::FileOutputter.new "#{COMPONENT}-file",
                                            'level' => 0, # All
                                            :filename => File.join(DATA_PATH, 'logs', "#{COMPONENT}.log"),
                                            'formatter' =>  format2
          #:maxsize => 1024
          @@log.outputters << o_file
        end

        o_out = Log4r::StdoutOutputter.new "#{COMPONENT}-stdout",
                                           'level' => 2, # no DEBUG
                                           'formatter' =>  format1

        o_err = Log4r::StderrOutputter.new "#{COMPONENT}-stderr",
                                           'level' => 5, # Error and Up
                                           'formatter' =>  format1

        @@log.outputters << o_out << o_err

        puts "six-rsync by Sickboy <sb_at_dev-heaven.net> v#{Six::Repositories::Rsync::VERSION}"

        if ARGV.empty?
          ARGV << Dir.pwd
          #logger.error "Using current folder"
          #Process.exit
        end


        #app = App.new(ARGV[0])
        ARGV.each do |arg|
          todo.each do |option|
            App.send option, "#{arg}"  # Unfreeze
          end
        end
      end
    end
  end
end
