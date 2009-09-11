# TODO: Add Rsync add, commit and push (Update should be pull?), either with staging like area like Git, or add is pack into .pack, and commit is update sum ?
# TODO: Seperate command lib from custom layer over rsync?

module Six
  module Repositories
    module Rsync
      class RsyncExecuteError < StandardError
      end

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
        WINDRIVE = /\"(\w)\:/

        def esc(val)
          "\"#{val}\""
        end

        def initialize(base = nil, logger = nil)
          @rsync_dir = nil
          @rsync_work_dir = nil
          @path = nil
          @version = nil

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
          @logger.info "Processing: #{rsync_path}"
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
          # TODO: .pack path should be formulized
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

          begin
            init

            # TODO: Eval move to update?
            arr_opts = []
            arr_opts << "-I" if opts[:force]
            begin
              update('', arr_opts)
            rescue
              @logger.error "Unable to sucessfully update, aborting..."
              # Dangerous? :D
              FileUtils.rm_rf @rsync_work_dir
            end
          rescue
            @logger.error "Unable to initialize"
          end

          opts[:bare] ? {:repository => @rsync_work_dir} : {:working_directory => @rsync_work_dir}
        end

        def update(cmd, x_opts = [], opts = {})
          @logger.info "Updating: #{@rsync_work_dir}, please wait..."
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

          host = config[:hosts].sample
          @logger.info "Trying: #{host}, please wait..."

          if opts[:force]
            arr_opts = []
            arr_opts << PARAMS
            arr_opts += x_opts

            # TODO: UNCLUSTERFUCK
            arr_opts << esc(File.join(host, '.pack/.'))
            arr_opts << esc(File.join(@rsync_work_dir, '.pack'))

            command(cmd, arr_opts)
            write_sums(:pack)
            write_sums(:wd)
          else
            #reset(:hard => true)
            write_sums(:pack)
            write_sums(:wd)

            # fetch latest sums and only update when changed
            compare_sums
          end          
        end

        # TODO: Allow local-self healing, AND remote healing. reset and fetch?
        def reset(opts = {})
          @logger.info "Resetting!"
          if opts[:hard]
            compare_sums(false)
          end
        end

        def add(file)
          @logger.error "Please use commit instead!"
          return
          @logger.info "Adding #{file}"
          if (file == ".")
            remote_wd = load_remote(:wd)
            remote_pack = load_remote(:pack)
            ar = Dir[File.join(@rsync_work_dir, '/**/*')]
            reg = /#{@rsync_work_dir}[\\|\/]/

            change = false
            ar.each do |file|
              unless file[/\.gz\Z/]
                relative = file.gsub(reg, '')
                checksum = md5(file)
                if checksum != remote_wd[:list][relative]
                  change = true
                  @logger.info "Packing #{file}"
                  system "gzip --best --rsyncable --keep #{file}"
                  remote_wd[:list][relative] = checksum
                  remote_pack[:list]["#{relative}.gz"] = md5("#{file}.gz")
                  FileUtils.mv("#{file}.gz", File.join(@rsync_work_dir, '.pack', "#{relative}.gz"))

                end
              end
            end
            if change
              File.open(File.join(@rsync_work_dir, '.sums.yml'), 'w') { |file| file.puts remote_wd[:list].sort.to_yaml }
              File.open(File.join(@rsync_work_dir, '.pack', '.sums.yml'), 'w') { |file| file.puts remote_pack[:list].sort.to_yaml }
            end
          else

          end
        end

        def commit
          @logger.info "Committing changes on #{@rsync_work_dir}"
          @config = read_config
          unless @config
            @logger.error "Not an Rsync repository!"
            return
          end

          unless config[:hosts].size > 0
            @logger.error "No hosts configured!"
            return
          end

          remote_wd = load_remote(:wd)
          remote_pack = load_remote(:pack)
          ar = Dir[File.join(@rsync_work_dir, '/**/*')]
          reg = /#{@rsync_work_dir}[\\|\/]/

          change = false
          ar.each do |file|
            unless file[/\.gz\Z/]
              relative = file.gsub(reg, '')
              checksum = md5(file)
              if checksum != remote_wd[:list][relative]
                change = true
                @logger.info "Packing #{file}"
                system "gzip --best --rsyncable --keep #{file}"
                remote_wd[:list][relative] = checksum
                remote_pack[:list]["#{relative}.gz"] = md5("#{file}.gz")
                FileUtils.mv("#{file}.gz", File.join(@rsync_work_dir, '.pack', "#{relative}.gz"))
              end
            end
          end

          if change
            File.open(File.join(@rsync_work_dir, '.sums.yml'), 'w') { |file| file.puts remote_wd[:list].sort.to_yaml }
            File.open(File.join(@rsync_work_dir, '.pack', '.sums.yml'), 'w') { |file| file.puts remote_pack[:list].sort.to_yaml }

            cmd = ''

            host = config[:hosts].sample
            verfile_srv = File.join(".pack", ".version")
            fetch_file(verfile_srv, host)
            ver = read_version

            verfile = File.join('.rsync', '.version')
            if FileTest.exist?(File.join(@rsync_work_dir, verfile))
              File.open(File.join(@rsync_work_dir, verfile)) {|file| @version = file.read.to_i }
            end
            @version = 0 unless @version
            @version += 1
            if @version < ver # && !force
              @logger.warn "WARNING, version on server is NEWER, aborting!"
              raise RsyncExecuteError
            end

            write_version
            FileUtils.cp(File.join(@rsync_work_dir, verfile), File.join(@rsync_work_dir, verfile_srv))

            arr_opts = []
            arr_opts << PARAMS

            # TODO: UNCLUSTERFUCK

            # Upload .pack changes
            if host[/\A(\w)*\@/]
              arr_opts << "-e ssh"
            end
            arr_opts << esc(File.join(@rsync_work_dir, '.pack/.'))
            arr_opts << esc(File.join(host, '.pack'))

            command(cmd, arr_opts)

            arr_opts = []
            arr_opts << PARAMS


            # TODO: UNCLUSTERFUCK
            if host[/\A(\w)*\@/]
              arr_opts << "-e ssh"
            end

            arr_opts << esc(File.join(@rsync_work_dir, '.pack', '.sums.yml'))
            arr_opts << esc(File.join(host, '.pack'))
            command(cmd, arr_opts)

            arr_opts = []
            arr_opts << PARAMS

            # TODO: UNCLUSTERFUCK
            if host[/\A(\w)*\@/]
              arr_opts << "-e ssh"
            end
            arr_opts << esc(File.join(@rsync_work_dir, '.sums.yml'))
            arr_opts << esc(host)
            command(cmd, arr_opts)
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

        def fetch_file(path, host)
          path[/(.*)\/(.*)/]
          folder, file = $1, $2
          folder = "." unless folder
          file = path unless file
          # Only fetch a specific file
          @logger.debug "Fetching #{path} from  #{host}"
          arr_opts = []
          arr_opts << PARAMS
          if host[/\A(\w)*\@/]
            arr_opts << "-e ssh"
          end
          arr_opts << esc(File.join(host, path))
          arr_opts << esc(File.join(@rsync_work_dir, folder))

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

        def write_sums(typ)
          h = calc_sums(typ)
          case typ
          when :pack
            File.open(File.join(@rsync_work_dir, '.rsync', 'sums_pack.yml'), 'w') { |file| file.puts h.sort.to_yaml }
            #File.open(File.join(@rsync_work_dir, '.pack', '.sums.yml'), 'w') { |file| file.puts h.sort.to_yaml }
          when :wd
            File.open(File.join(@rsync_work_dir, '.rsync', 'sums_wd.yml'), 'w') { |file| file.puts h.sort.to_yaml }
            #File.open(File.join(@rsync_work_dir, '.sums.yml'), 'w') { |file| file.puts h.sort.to_yaml }
          end
          h
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

        def compare_set(local, remote, typ, host, online = true)
          local[typ] = load_local(typ)
          remote[typ] = load_remote(typ)

          if local[typ][:md5] == remote[typ][:md5]
            @logger.info "#{typ} Match!"
          else
            mismatch = []
            @logger.info "#{typ} NOT match!"
            remote[typ][:list].each_pair do |key, value|
              if value == local[typ][:list][key]
                #@logger.info "Match! #{key}"
              else
                @logger.info "Mismatch! #{key}"
                mismatch << key
              end
            end

            if mismatch.size > 0
              case typ
              when :pack
                # direct unpack of gz into working folder
                # Update file
                if online
                  # TODO: Progress bar
                  if mismatch.count > (remote[typ][:list].count / 4)
                    @logger.info "Many files mismatched (#{mismatch.count}), running full update on .pack folder"
                    arr_opts = []
                    arr_opts << PARAMS
                    arr_opts << File.join(host, '.pack/.')
                    arr_opts << esc(File.join(@rsync_work_dir, '.pack'))

                    command('', arr_opts)

                  else
                    c = mismatch.size
                    i = 0
                    mismatch.each do |e|
                      # TODO: Nicer progress bar...
                      i += 1
                      @logger.info "Fetching #{i}/#{c}: #{e}"
                      fetch_file(File.join(".pack", e), host)
                    end
                  end
                end
              when :wd
                c = mismatch.size
                i = 0
                mismatch.each do |e|
                  # TODO: Nicer progress bar...
                  i += 1
                  @logger.info "Unpacking #{i}/#{c}: #{e}"
                  unpack(:path => "#{e}.gz")
                end
              end
            end

            del = []
            local[typ][:list].each_pair do |key, value|
              if remote[typ][:list][key].nil?
                @logger.info "File does not exist in remote! #{key}"
                del << key
              end
            end
            @logger.info "To delete: #{del.join(',')}" if del.size > 0
            del.each { |e| del_file(e, typ) }
            write_sums(typ)
          end
        end

        def compare_sums(online = true)
          local, remote = Hash.new, Hash.new
          hosts = config[:hosts].clone
          done = true

          ## Pack
          if online
            done = false
            while hosts.size > 0 && !done do
              host = hosts.sample
              hosts -= [host]
              begin
                verfile = File.join(".pack", ".version")
                fetch_file(verfile, host)
                ver = read_version

                verfile = File.join(@rsync_work_dir, '.rsync', '.version')
                if FileTest.exist?(verfile)
                  File.open(verfile) {|file| @version = file.read.to_i }
                end

                @version = 0 unless @version
                if @version > ver # && !force
                  @logger.warn "WARNING, version on server is OLDER, aborting!"
                  raise RsyncExecuteError
                end
                fetch_file(File.join(".pack", ".sums.yml"), host)
                done = true
              rescue
                @logger.debug "Failed #{host}, trying next.."
              end
            end
          end
          if done
            # TODO: Don't do actions when not online
            compare_set(local, remote, :pack, host)

            ## Working Directory
            fetch_file('.sums.yml', host) if online
            compare_set(local, remote, :wd, host)

            @version = read_version
            write_version
          end
        end

        def read_version
          verfile = File.join(@rsync_work_dir, '.pack', '.version')
          if FileTest.exist?(verfile)
            File.open(verfile) {|file| file.read.to_i }
          end
        end

        def write_version
          File.open(File.join(@rsync_work_dir, '.rsync/.version'), 'w') {|file| file.puts @version }
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
            rsync_cmd.gsub!(drive, "\"/cygdrive/#{$1}")
          end

          out = nil
          if chdir && (Dir.getwd != path)
            Dir.chdir(path) { out = run_command(rsync_cmd, &block) }
          else
            out = run_command(rsync_cmd, &block)
          end

          if @logger
            @logger.debug(rsync_cmd)
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
