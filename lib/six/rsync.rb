module Six
  module Repositories
    BASE_PATH = Dir.pwd
    TOOLS_PATH = File.join(BASE_PATH, 'tools')
    FOLDER = /(.*)\/(.*)/
    ENV['PATH'] = ENV['PATH'] + ";#{TOOLS_PATH}"

    module Rsync
      class Lib
        DEFAULT = Hash.new
        DEFAULT[:hosts] = []
        PARAMS = "--times -O --no-whole-file -r --delete --stats --progress --exclude=.rsync"

        def initialize(base = nil, logger = nil)
          @rsync_dir = nil
          @rsync_work_dir = nil
          @path = nil

          if base.is_a?(Rsync::Base)
            @rsync_dir = base.repo.path
            #@rsync_work_dir = base.dir.path if base.dir
          elsif base.is_a?(Hash)
            @rsync_dir = base[:repository]
            #@rsync_work_dir = base[:working_directory]
          end
          @logger = logger
        end

        def init
          File.open(File.join(@rsync_dir, '.rsync', '.config'), 'w') do |file|
            file.puts DEFAULT.to_yaml
          end
        end

        def clone(repository, name, opts = {})
          @path = opts[:path] || '.'
          clone_dir = opts[:path] ? @path : name # File.join(@path, name)

          arr_opts = []
          arr_opts << PARAMS
          arr_opts << "-I" if opts[:force]

          arr_opts << repository
          arr_opts << clone_dir

          command('', arr_opts)

          opts[:bare] ? {:repository => clone_dir} : {:working_directory => clone_dir}
        end
      end

      class Base
        attr_reader :repository

        # opens a new Rsync Project from a working directory
        # you can specify non-standard rsync_dir and index file in the options
        def self.open(working_dir, opts={})
          self.new({:working_directory => working_dir}.merge(opts))
        end

        # initializes a rsync repository
        #
        # options:
        #  :repository
        #  :index_file
        #
        def self.init(working_dir, opts = {})
          opts = {
            :working_directory => working_dir,
            :repository => File.join(working_dir, '.rsync')
          }.merge(opts)

          FileUtils.mkdir_p(opts[:working_directory]) if opts[:working_directory] && !File.directory?(opts[:working_directory])

          # run rsync_init there
          Rsync::Lib.new(opts).init

          self.new(opts)
        end

        # clones a rsync repository locally
        #
        #  repository - http://repo.or.cz/w/sinatra.git
        #  name - sinatra
        #
        # options:
        #   :repository
        #
        #    :bare
        #   or
        #    :working_directory
        #    :index_file
        #
        def self.clone(repository, name, opts = {})
          # run Rsync clone
          self.new(Rsync::Lib.new.clone(repository, name, opts))
        end


        def initialize(options = {})
          @repository = repository

          if working_dir = options[:working_directory]
            options[:repository] ||= File.join(working_dir, '.rsync')
          end

          if options[:log]
            @logger = options[:log]
            @logger.info("Starting Rsync")
          else
            @logger = nil
          end
        end

        # returns a reference to the working directory
        #  @rsync.dir.path
        #  @rsync.dir.writeable?
        def dir
          @working_directory
        end

        # returns reference to the rsync repository directory
        #  @rsync.dir.path
        def repo
          @repository
        end
    
        def set_working(work_dir, check = true)
          @lib = nil
          @working_directory = Rsync::WorkingDirectory.new(work_dir.to_s, check)
        end

        # changes current working directory for a block
        # to the rsync working directory
        #
        # example
        #  @rsync.chdir do
        #    # write files
        #    @rsync.add
        #    @rsync.commit('message')
        #  end
        def chdir # :yields: the Rsync::Path
          Dir.chdir(dir.path) do
            yield dir.path
          end
        end

        # returns the repository size in bytes
        def repo_size
          size = 0
          Dir.chdir(repo.path) do
            (size, dot) = `du -s`.chomp.split
          end
          size.to_i
        end

        # returns a Rsync::Status object
        def status
          Rsync::Status.new(self)
        end

      end
    end
  end
end

