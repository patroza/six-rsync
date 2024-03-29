# encoding: UTF-8

module Six
  module Repositories
    module Rsync
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

          #FileUtils.mkdir_p(opts[:working_directory]) if opts[:working_directory] && !File.directory?(opts[:working_directory])

          # run rsync_init there
          logger = if opts[:log]
            opts[:log]
          else
            nil
          end
          Rsync::Lib.new(opts, logger).init

          self.new(opts)
        end

        def self.convert(working_dir, opts = {})
          opts = {
            :working_directory => working_dir,
            :repository => File.join(working_dir, '.rsync')
          }.merge(opts)

          #FileUtils.mkdir_p(opts[:working_directory]) if opts[:working_directory] && !File.directory?(opts[:working_directory])

          # run rsync_convert there
          logger = if opts[:log]
            opts[:log]
          else
            nil
          end
          Rsync::Lib.new(opts, logger).convert

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
        def self.clone(host, name, opts = {})
          # run Rsync clone
          logger = if opts[:log]
            opts[:log]
          else
            nil
          end
          self.new(Rsync::Lib.new(nil, logger).clone(host, name, opts))
        end

        def initialize(options = {})
          if working_dir = options[:working_directory]
            options[:repository] ||= File.join(working_dir, '.rsync')
          end
          if options[:log]
            @logger = options[:log]
            @logger.debug("Starting Rsync on #{working_dir}")
          else
            @logger = nil
          end
          @working_directory = options[:working_directory] ? Rsync::WorkingDirectory.new(options[:working_directory]) : nil
          @repository = options[:repository] ? Rsync::Repository.new(options[:repository]) : nil

        end

        def update(opts = {})
          lib.update('', [], opts)
        end

        def reset(opts = {})
          lib.reset(opts)
        end

        def add(file = '')
          lib.add(file)
        end

        def commit
          lib.commit
        end

        def push
          lib.push
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
          lib.status
        end

        def info
          lib.info
        end

        # this is a convenience method for accessing the class that wraps all the
        # actual 'git' forked system calls.  At some point I hope to replace the Git::Lib
        # class with one that uses native methods or libgit C bindings
        def lib
          @lib ||= Rsync::Lib.new(self, @logger)
        end
      end
    end
  end
end
