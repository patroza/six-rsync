module Six
  module Repositories
    module Rsync
      class RsyncExecuteError < StandardError
      end

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
          clone_dir = opts[:path] ? File.join(@path, name) : name

          arr_opts = []
          arr_opts << PARAMS
          arr_opts << "-I" if opts[:force]

          arr_opts << repository
          arr_opts << clone_dir

          command('', arr_opts)

          opts[:bare] ? {:repository => clone_dir} : {:working_directory => clone_dir}
        end

        private

        def command_lines(cmd, opts = [], chdir = true, redirect = '')
          command(cmd, opts, chdir).split("\n")
        end

        def command(cmd, opts = [], chdir = true, redirect = '', &block)
          #ENV['GIT_DIR'] = @rsync_dir
          #ENV['GIT_WORK_TREE'] = @rsync_work_dir
          path = @rsync_work_dir || @rsync_dir || @path

          opts = [opts].flatten.map {|s| s }.join(' ') #wescape()
          rsync_cmd = "rsync #{cmd} #{opts} #{redirect} 2>&1"
          while rsync_cmd[/ (\w)\:/] do
            drive = rsync_cmd[/ (\w)\:/]
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
