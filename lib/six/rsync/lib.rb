module Six
  module Repositories
    module Rsync
      class RsyncExecuteError < StandardError
      end

      class Lib
        PROTECTED = true
        DEFAULT = Hash.new
        DEFAULT[:hosts] = []
        PARAMS = if PROTECTED
          "--dry-run --times -O --no-whole-file -r --delete --stats --progress --exclude=.rsync"
        else
          "--times -O --no-whole-file -r --delete --stats --progress --exclude=.rsync"
        end
        WINDRIVE = / (\w)\:/

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
          unless FileTest.exist? rsync_path
            @logger.error "Seems to already be an Rsync repository!"
            return
          end
          FileUtils.mkdir_p rsync_path
          write_config(config)
        end

        def config
          @config ||= DEFAULT.clone
        end

        def clone(repository, name, opts = {})
          @path = opts[:path] || '.'
          @rsync_dir = opts[:path] ? File.join(@path, name) : name

          case repository
          when Array
            config[:hosts] += repository
          when String
            config[:hosts] << repository
          end

          init

          # TODO: Eval move to update?
          arr_opts = []
          arr_opts << "-I" if opts[:force]

          update('', arr_opts)

          opts[:bare] ? {:repository => @rsync_dir} : {:working_directory => @rsync_dir}
        end

        def update(cmd, x_opts = [])
          @config = read_config
          unless @config
            @logger.error "Not an Rsync repository!"
            return
          end

          p config
          unless config[:hosts].size > 0
            @logger.error "No hosts configured!"
            return
          end

          arr_opts = []
          arr_opts << PARAMS
          arr_opts += x_opts
          arr_opts << config[:hosts].sample
          arr_opts << @rsync_dir

          command(cmd, arr_opts)
        end

        private
        def rsync_path
          File.join(@rsync_dir, '.rsync')
        end

        def read_config
          read_yaml(File.join(rsync_path, 'config.yml'))
        end

        def read_sums
          read_yaml(File.join(rsync_path, 'sums.yml'))
        end

        def read_yaml(file)
          if FileTest.exist?(file)
            YAML::load_file(file)
          else
            nil
          end          
        end

        def write_default_config
          FileUtils.mkdir_p rsync_path
          write_config(config)
        end

        def write_sums
          sums = Hash.new
          Dir[File.join(@rsync_dir, '**/*')].each do |file|
            relative = file.gsub(/#{@rsync_dir}[\\|\/]/, '')
            sums[relative] = Digest::MD5.hexdigest(File.read(file))
          end

          File.open(File.join(rsync_path, 'sums.yml'), 'w') do |file|
            file.puts sums.to_yaml
          end
        end

        def write_config(config = DEFAULT)
          File.open(File.join(rsync_path, '.config'), 'w') do |file|
            file.puts config.to_yaml
          end
        end

        def command_lines(cmd, opts = [], chdir = true, redirect = '')
          command(cmd, opts, chdir).split("\n")
        end

        def command(cmd, opts = [], chdir = true, redirect = '', &block)
          path = @rsync_work_dir || @rsync_dir || @path

          opts = [opts].flatten.map {|s| s }.join(' ') # escape()
          rsync_cmd = "rsync #{cmd} #{opts} #{redirect} 2>&1"
          while rsync_cmd[WINDRIVE] do
            drive = rsync_cmd[WINDRIVE]
            rsync_cmd.gsub!(drive, " /cygdrive/#{$1}")
          end

          out = nil
          if chdir && (Dir.getwd != path)
            Dir.chdir(path) { out = run_command(rsync_cmd, &block) }
          else
            out = run_command(rsync_cmd, &block)
          end

          if @logger
            @logger.info(rsync_cmd)
            @logger.debug(out)
          end

          if $?.exitstatus > 0
            if $?.exitstatus == 1 && out == ''
              return ''
            end
            raise Rsync::RsyncExecuteError.new(rsync_cmd + ':' + out.to_s)
          end
          out
        end

        def run_command(rsync_cmd, &block)
          if block_given?
            IO.popen(rsync_cmd, &block)
          else
            `#{rsync_cmd}`.chomp
          end
        end

        def escape(s)
          "\"" + s.to_s.gsub('\"', '\"\\\"\"') + "\""
        end
      end
    end
  end
end
