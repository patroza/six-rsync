# encoding: UTF-8
#begin; require 'faster_require'; rescue LoadError; end if RUBY_PLATFORM =~ /cygwin|mingw|win32/

require 'fileutils'
require 'digest/md5'
require 'yaml'
require 'open3'

require 'six/rsync/path'
require 'six/rsync/repository'
require 'six/rsync/working_directory'
require 'six/rsync/lib'
require 'six/rsync/base'

case RUBY_VERSION
when /1\.8\.[0-9]/
  class Array
    def sample
      self[rand(self.size)]
    end
  end
end

module Six
  module Repositories
    module Md5
    end

    module Rsync
      COMPONENT = 'six-rsync'
      VERSION = '0.7.2'
      BASE_PATH = Dir.pwd      

      case RUBY_PLATFORM
        when /-mingw32$/, /-mswin32$/
          TEMP_PATH = if ENV['TEMP']
            if ENV['TEMP'].size > 0
              File.directory?(ENV['TEMP']) ? ENV['TEMP'] : BASE_PATH
            else
              BASE_PATH
            end
          else
            BASE_PATH
          end
          HOME_PATH = File.exists?(File.join(ENV['APPDATA'])) ? File.join(ENV['APPDATA']) : TEMP_PATH
        else
          HOME_PATH = ENV['HOME']
          TEMP_PATH = '/tmp'
      end
      DATA_PATH = File.join(HOME_PATH, COMPONENT)
      CONFIG_FILE = File.join(DATA_PATH, 'config.yml')
      if File.exists?(DATA_PATH)
        unless File.directory?(DATA_PATH)
          puts "#{DATA_PATH} is a file instead of folder"
          raise StandardError
        end
      else
        FileUtils.mkdir_p DATA_PATH
      end
      config = File.exists?(CONFIG_FILE) ? YAML::load_file(CONFIG_FILE) : nil 
      CONFIG = config ? config : Hash.new

      # No meaning on Cygwin 1.7
      # ENV['CYGWIN'] = "nontsec"

      # open a bare repository
      #
      # this takes the path to a bare rsync repo
      # it expects not to be able to use a working directory
      # so you can't checkout stuff, commit things, etc.
      # but you can do most read operations
      def self.bare(rsync_dir, options = {})
        Base.bare(rsync_dir, options)
      end

      # open an existing rsync working directory
      #
      # this will most likely be the most common way to create
      # a rsync reference, referring to a working directory.
      # if not provided in the options, the library will assume
      # your rsync_dir is in the default place (.rsync/)
      #
      # options
      #   :repository => '/path/to/alt_rsync_dir'
      #   :index => '/path/to/alt_index_file'
      def self.open(working_dir, options = {})
        Base.open(working_dir, options)
      end

      # Converts into repository
      def self.convert(working_dir = '.', options = {})
        Base.convert(working_dir, options)
      end

      # initialize a new rsync repository, defaults to the current working directory
      #
      # options
      #   :repository => '/path/to/alt_rsync_dir'
      #   :index => '/path/to/alt_index_file'
      def self.init(working_dir = '.', options = {})
        Base.init(working_dir, options)
      end

      # clones a remote repository
      #
      # options
      #   :bare => true (does a bare clone)
      #   :repository => '/path/to/alt_rsync_dir'
      #   :index => '/path/to/alt_index_file'
      #
      # example
      #  Rsync.clone('rsync://repo.or.cz/ruby', 'clone', :bare => true)
      #
      def self.clone(repository, name, options = {})
        Base.clone(repository, name, options)
      end

=begin
      # Export the current HEAD (or a branch, if <tt>options[:branch]</tt>
      # is specified) into the +name+ directory, then remove all traces of rsync from the
      # directory.
      #
      # See +clone+ for options.  Does not obey the <tt>:remote</tt> option,
      # since the rsync info will be deleted anyway; always uses the default
      # remote, 'origin.'
      def self.export(repository, name, options = {})
        options.delete(:remote)
        repo = clone(repository, name, {:depth => 1}.merge(options))
        repo.checkout("origin/#{options[:branch]}") if options[:branch]
        Dir.chdir(repo.dir.to_s) { FileUtils.rm_r '.rsync' }
      end

      #g.config('user.name', 'Scott Chacon') # sets value
      #g.config('user.email', 'email@email.com')  # sets value
      #g.config('user.name')  # returns 'Scott Chacon'
      #g.config # returns whole config hash
      def config(name = nil, value = nil)
        lib = Rsync::Lib.new
        if(name && value)
          # set value
          lib.config_set(name, value)
        elsif (name)
          # return value
          lib.config_get(name)
        else
          # return hash
          lib.config_list
        end
      end

      # Same as g.config, but forces it to be at the global level
      #
      #g.config('user.name', 'Scott Chacon') # sets value
      #g.config('user.email', 'email@email.com')  # sets value
      #g.config('user.name')  # returns 'Scott Chacon'
      #g.config # returns whole config hash
      def self.global_config(name = nil, value = nil)
        lib = Rsync::Lib.new(nil, nil)
        if(name && value)
          # set value
          lib.global_config_set(name, value)
        elsif (name)
          # return value
          lib.global_config_get(name)
        else
          # return hash
          lib.global_config_list
        end
      end

      def global_config(name = nil, value = nil)
        self.class.global_config(name, value)
      end
=end
    end
  end
end
