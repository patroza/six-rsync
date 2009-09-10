module Six
  module Repositories
    module Rsync
      class RsyncExecuteError < StandardError
      end

      # TODO: Check ruby md5 vs md5sum.exe cpu and mem?

      class Lib
        PROTECTED = false
        tmp = Hash.new
        tmp[:hosts] = []
        DEFAULT = tmp.to_yaml
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
            @rsync_work_dir = base.dir.path if base.dir
          elsif base.is_a?(Hash)
            @rsync_dir = base[:repository]
            @rsync_work_dir = base[:working_directory]
          end
          @logger = logger
        end

        def init
          puts "Processing: #{rsync_path}"
          if FileTest.exist? rsync_path
            @logger.error "Seems to already be an Rsync repository, Aborting!"
            raise RsyncExecuteError
            #return
          end
          if FileTest.exist? @rsync_work_dir
            @logger.error "Seems to already be a folder, Aborting!"
            raise RsyncExecuteError
            #return
          end
          FileUtils.mkdir_p rsync_path
          FileUtils.mkdir_p File.join(@rsync_work_dir, '.pack')
          write_config(config)
        end

        def config
          @config ||= YAML::load(DEFAULT)
        end

        def clone(repository, name, opts = {})
          @path = opts[:path] || '.'
          @rsync_work_dir = opts[:path] ? File.join(@path, name) : name
          if opts[:log]
            @logger = opts[:log]
          end

          case repository
          when Array
            config[:hosts] += repository
          when String
            config[:hosts] << repository
          end

     #     begin
            init

            # TODO: Eval move to update?
            arr_opts = []
            arr_opts << "-I" if opts[:force]
            puts "#{@path} - #{@rsync_work_dir}"
            begin
              update('', arr_opts)
            rescue
              @logger.error "Unable to sucessfully update, aborting..."
              # Dangerous? :D
              FileUtils.rm_rf @rsync_work_dir
            end
      #    rescue
      #      @logger.error "Unable to initialize"
      #    end

          opts[:bare] ? {:repository => @rsync_work_dir} : {:working_directory => @rsync_work_dir}
        end

        def update(cmd, x_opts = [], opts = {})
          @config = read_config
          unless @config
            @logger.error "Not an Rsync repository!"
            return
          end

          unless config[:hosts].size > 0
            @logger.error "No hosts configured!"
            return
          end

          #unpack

          if opts[:force]
            arr_opts = []
            arr_opts << PARAMS
            arr_opts += x_opts

            # TODO: UNCLUSTERFUCK
            arr_opts << File.join(config[:hosts].sample, '.pack/.')
            arr_opts << File.join(@rsync_work_dir, '.pack')

            command(cmd, arr_opts)
            write_sums
          else
            #reset(:hard => true)
            write_sums

            # fetch latest sums and only update when changed
            compare_sums
          end          
        end

        def reset(opts = {})
          puts "Restting!"
          if opts[:hard]
            compare_sums(false)
          end
        end

        private
        def unpack_file(file, path)
          Dir.chdir(path) do |dir|
            system "7za x \"#{file}\" -y"
            if file[/\.tar\.?/]
              file[/(.*)\/(.*)/]
              fil = $2
              fil = file unless fil
              f2 = fil.gsub('.gz', '')
              system "7za x \"#{f2}\" -y"
              FileUtils.rm_f f2
            end
          end
        end

        def unpack(opts = {})
          items = if opts[:path]
            [File.join(@rsync_work_dir, '.pack', opts[:path])]
          else
            Dir[File.join(@rsync_work_dir, '.pack/**/*')]
          end

          items.each do |file|
            unless File.directory? file
              relative = file.gsub(/#{@rsync_work_dir}[\\|\/]\.pack[\\|\/]/, '')
              fil = relative
              folder = "."
              folder, fil = $1, $2 if relative[/(.*)\/(.*)/]

              path = File.join(@rsync_work_dir, folder)
              FileUtils.mkdir_p path
              unpack_file(file, path)
            end
          end
        end

        def rsync_path
          File.join(@rsync_work_dir, '.rsync')
        end

        def read_config
          read_yaml(File.join(rsync_path, 'config.yml'))
        end

        def read_yaml(file)
          if FileTest.exist?(file)
            YAML::load_file(file)
          else
            nil
          end          
        end

        def fetch_file(path)
          path[/(.*)\/(.*)/]
          folder, file = $1, $2
          folder = "." unless folder
          file = path unless file
          # Only fetch a specific file
          puts "Fetching #{path}"
          arr_opts = []
          arr_opts << PARAMS
          arr_opts << File.join(config[:hosts].sample, path)
          arr_opts << File.join(@rsync_work_dir, folder)

          command('', arr_opts)
        end

        def write_default_config
          FileUtils.mkdir_p rsync_path
          write_config(config)
        end

        def calc_sums(typ)
          ar = []
          reg = case typ
          when :pack
            ar = Dir[File.join(@rsync_work_dir, '/.pack/**/*')]
            /#{@rsync_work_dir}[\\|\/]\.pack[\\|\/]/
          when :wd
            ar = Dir[File.join(@rsync_work_dir, '/**/*')]
            /#{@rsync_work_dir}[\\|\/]/
          end
          h = Hash.new
          ar.each do |file|
            relative = file.gsub(reg, '')
            sum = md5(file)
            h[relative] = sum if sum
          end
          h
        end

        def write_sums
          sums_pack = Hash.new
          sums_wd = Hash.new
          pack = /\A.pack[\\|\/]/

          h = calc_sums(:wd)
          File.open(File.join(@rsync_work_dir, '.rsync', 'sums_wd.yml'), 'w') { |file| file.puts h.sort.to_yaml }
          #File.open(File.join(@rsync_work_dir, '.sums.yml'), 'w') { |file| file.puts h.sort.to_yaml }

          h = calc_sums(:pack)
          File.open(File.join(@rsync_work_dir, '.rsync', 'sums_pack.yml'), 'w') { |file| file.puts h.sort.to_yaml }
          #File.open(File.join(@rsync_work_dir, '.pack', '.sums.yml'), 'w') { |file| file.puts h.sort.to_yaml }
        end

        def load_sums(file, key)
          sum = Hash.new
          File.open(File.join(@rsync_work_dir, file)) do |file|
            h = Hash.new
            YAML::load(file).each { |e| h[e[0]] = e[1] }
            sum[:list] = h
            sum[:md5] = md5(file.path)
          end
          sum
        end

        def load_local(typ)
          load_sums(".rsync/sums_#{typ}.yml", typ)
        end

        def load_remote(typ)
          file = case typ
          when :pack
            ".pack/.sums.yml"
          when :wd
            ".sums.yml"
          end
          load_sums(file, typ)
        end

        # Something goes wrong when the md5 sums on disk are not up2date with the files on disk

        def compare_set(local, remote, typ, online = true)
          local[typ] = load_local(typ)
          remote[typ] = load_remote(typ)


          #p [local[typ][:md5], remote[typ][:md5]]
          #gets

          if local[typ][:md5] == remote[typ][:md5]
            puts "#{typ} Match!"
          else
            mismatch = []
            puts "#{typ} NOT match!"
            remote[typ][:list].each_pair do |key, value|
              if value == local[typ][:list][key]
                #puts "Match! #{key}"
              else
                puts "Mismatch! #{key}"
                mismatch << key
              end
            end

            if mismatch.size > 0
              case typ
              when :pack
                # direct unpack of gz into working folder
                # Update file
                if online
                  if mismatch.count > (remote[typ][:list].count / 4)
                    puts "Many files mismatched (#{mismatch.count}), running full update on .pack folder"
                    arr_opts = []
                    arr_opts << PARAMS
                    arr_opts << File.join(config[:hosts].sample, '.pack/.')
                    arr_opts << File.join(@rsync_work_dir, '.pack')

                    command('', arr_opts)

                  else
                    mismatch.each { |e| fetch_file(File.join(".pack", e)) }
                  end
                end
              when :wd
                # calculate gz file and unpack
                mismatch.each { |e| unpack(:path => "#{e}.gz") }
              end
            end

            del = []
            local[typ][:list].each_pair do |key, value|
              if remote[typ][:list][key].nil?
                puts "File does not exist in remote! #{key}"
                del << key
              end
            end
            puts "To delete: #{del.join(',')}" if del.size > 0
            del.each { |e| del_file(e, typ) }
            write_sums
          end
        end

        # TODO: Allow local-self healing, AND remote healing. reset and fetch?
        def compare_sums(online = true)
          local, remote = Hash.new, Hash.new

          ## Pack
          fetch_file(File.join(".pack", ".sums.yml")) if online
          # TODO: Don't do actions when not online
          compare_set(local, remote, :pack)

          ## Working Directory
          fetch_file('.sums.yml') if online
          compare_set(local, remote, :wd)
        end

        def del_file(file, typ, opts = {})
          file = case typ
          when :pack
            File.join('.pack', file)
          when :wd
            file
          end
          FileUtils.rm_f File.join(@rsync_work_dir, file)
        end

        def md5(path)
          unless File.directory? path
            path[/(.*)[\/|\\](.*)/]
            folder, file = $1, $2
            Dir.chdir(folder) do
              r = %x[md5sum "#{file}"]
              r[/\A\w*/]
            end
            #File.open(file) do |file|
            #  file.binmode
            #  Digest::MD5.hexdigest(file.read)
            #end
          end
        end

        def write_config(config = YAML::load(DEFAULT))
          File.open(File.join(rsync_path, 'config.yml'), 'w') { |file| file.puts config.to_yaml }
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
          p rsync_cmd

          out = nil
          if chdir && (Dir.getwd != path)
            Dir.chdir(path) { out = run_command(rsync_cmd, &block) }
          else
            out = run_command(rsync_cmd, &block)
          end

          p out
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
