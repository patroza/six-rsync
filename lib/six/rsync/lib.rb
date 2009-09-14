# TODO: Add Rsync add, commit and push (Update should be pull?), either with staging like area like Git, or add is pack into .pack, and commit is update sum ?
# TODO: Seperate command lib from custom layer over rsync?

module Six
  module Repositories
    module Rsync
      DIR_RSYNC = '.rsync'
      DIR_PACK = File.join(DIR_RSYNC, '.pack')

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

          @repos_local = {:pack => Hash.new, :wd => Hash.new, :version => 0}
          @repos_remote = {:pack => Hash.new, :wd => Hash.new, :version => 0}

          if base.is_a?(Rsync::Base)
            @rsync_dir = base.repo.path
            @rsync_work_dir = base.dir.path if base.dir
          elsif base.is_a?(Hash)
            @rsync_dir = base[:repository]
            @rsync_work_dir = base[:working_directory]
          end
          @logger = logger

          etc = File.join(TOOLS_PATH, 'etc')
          FileUtils.mkdir_p etc
          fstab = File.join(etc, 'fstab')
          str = ""
          str = File.open(fstab) {|file| file.read} if FileTest.exist?(fstab)
          unless str[/cygdrive/]
            str += "\nnone /cygdrive cygdrive user,noacl,posix=0 0 0\n"
            File.open(fstab, 'w') {|file| file.puts str}
          end
        end

        def init
          @logger.info "Processing: #{rsync_path}"
          if FileTest.exist? rsync_path
            @logger.error "Seems to already be an Rsync repository, Aborting!"
            raise RsyncExecuteError
          end
          if FileTest.exist? @rsync_work_dir
            @logger.error "Seems to already be a folder, Aborting!"
            raise RsyncExecuteError
          end
          FileUtils.mkdir_p pack_path
          save_config(config)
        end

        def clone(repository, name, opts = {})
          @path = opts[:path] || '.'
          @rsync_work_dir = opts[:path] ? File.join(@path, name) : name

          # TODO: Solve logger mess completely.
          @logger = opts[:log] if opts[:log]

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
          @config = load_config
          unless @config
            @logger.error "Not an Rsync repository!"
            raise RsyncExecuteError
          end

          unless config[:hosts].size > 0
            @logger.error "No hosts configured!"
            raise RsyncExecuteError
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
            arr_opts << esc(pack_path)

            command(cmd, arr_opts)
            calc
            save_repos
          else
            #reset(:hard => true)
            calc
            save_repos

            # fetch latest sums and only update when changed
            compare_sums
          end          
        end


        # TODO: Allow local-self healing, AND remote healing. reset and fetch?
        def reset(opts = {})
          @logger.info "Resetting!"
          if opts[:hard]
            @config = load_config
            calc
            save_repos
            compare_sums(false)
          end
        end

        # TODO: WIP
        def add(file)
          @logger.error "Please use commit instead!"
          return
          @logger.info "Adding #{file}"
          if (file == ".")
            load_repos(:remote)
            ar = Dir[File.join(@rsync_work_dir, '/**/*')]

            change = false
            i = 0
            ar.each do |file|
              i += 1
              unless file[/\.gz\Z/]
                relative = file.clone
                relative.gsub!(@rsync_work_dir, '')
                relative.gsub!(/\A[\\|\/]/, '')

                checksum = md5(file)
                if checksum != @repos_remote[:wd][relative]
                  change = true
                  @logger.info "Packing #{i}/#{ar.size}: #{file}"
                  gzip(file)
                  @repos_remote[:wd][relative] = checksum
                  @repos_remote[:pack]["#{relative}.gz"] = md5("#{file}.gz")
                  FileUtils.mv("#{file}.gz", pack_path("#{relative}.gz"))
                end
              end
            end
            if change
              save_repos
              #File.open(File.join(@rsync_work_dir, '.sums.yml'), 'w') { |file| file.puts remote_wd[:list].sort.to_yaml }
              #File.open(pack_path('.sums.yml'), 'w') { |file| file.puts remote_pack[:list].sort.to_yaml }
            end
          else

          end
        end

        def commit
          @logger.info "Committing changes on #{@rsync_work_dir}"
          @config = load_config
          unless @config
            @logger.error "Not an Rsync repository!"
            return
          end

          unless config[:hosts].size > 0
            @logger.error "No hosts configured!"
            return
          end

          load_repos(:local)
          load_repos(:remote)
          # Added or Changed files
          ar = Dir[File.join(@rsync_work_dir, '/**/*')]

          change = false
          i = 0
          ar.each do |file|
            i += 1
            unless file[/\.gz\Z/]
              relative = file.clone
              relative.gsub!(@rsync_work_dir, '')
              relative.gsub!(/\A[\\|\/]/, '')
              checksum = md5(file)
              if checksum != @repos_remote[:wd][relative]
                relative[/(.*)\/(.*)/]
                folder = $1
                change = true
                @logger.info "Packing #{i}/#{ar.size}: #{relative}"
                gzip(file)
                @repos_local[:wd][relative] = checksum
                @repos_local[:pack]["#{relative}.gz"] = md5("#{file}.gz")
                FileUtils.mkdir_p pack_path(folder) if folder
                FileUtils.mv("#{file}.gz", pack_path("#{relative}.gz"))
              end
            end
          end

          # Deleted files
          ar2 = Dir[File.join(@rsync_work_dir, '/.rsync/.pack/**/*')]
          i = 0
          ar2.each do |file|
            i += 1
            if file[/\.gz\Z/]
              relative = file.clone
              relative.gsub!(@rsync_work_dir, '')
              relative.gsub!(/\A[\\|\/]\.rsync[\\|\/]\.pack[\\|\/]/, '')
              local = relative.clone
              local.gsub!(/\.gz\Z/, '')
              if @repos_local[:wd][local].nil?
                relative[/(.*)\/(.*)/]
                folder = $1
                change = true
                @logger.info "Deleting #{i}/#{ar2.size}: #{relative}"
                @repos_local[:wd].delete local
                @repos_local[:pack].delete relative
                FileUtils.rm_f(file)
              end
            end
          end

          if change
            cmd = ''

            # TODO: Change to repositories.yml
            host = config[:hosts].sample
            verfile_srv = File.join(".pack", ".repository.yml")
            begin
              fetch_file(verfile_srv, host)
            rescue
              # FIXME: Should never assume that :)
              @logger.warn "Unable to retrieve version file from server, repository probably doesnt exist!"
              raise RsyncExecuteError
            end
            load_repos(:remote)
            if @repos_local[:version] < @repos_remote[:version] # && !force
              @logger.warn "WARNING, version on server is NEWER, aborting!"
              raise RsyncExecuteError
            end
            @repos_local[:version] += 1
            @repos_remote[:version] = @repos_local[:version]
            @repos_remote[:pack] = @repos_local[:pack].clone
            @repos_remote[:wd] = @repos_local[:wd].clone
            save_repos(:remote)
            save_repos(:local)

            # TODO: UNCLUSTERFUCK
            arr_opts = []
            arr_opts << PARAMS

            # Upload .pack changes
            if host[/\A(\w)*\@/]
              arr_opts << "-e ssh"
            end
            arr_opts << esc(pack_path('.'))
            arr_opts << esc(File.join(host, '.pack'))

            command(cmd, arr_opts)

            # TODO: UNCLUSTERFUCK
            arr_opts = []
            arr_opts << PARAMS
          end
        end

        private
        def compare_set(typ, host, online = true)
          load_repos(:local)
          load_repos(:remote)

          #if local[typ][:md5] == remote[typ][:md5]
          #  @logger.info "#{typ} Match!"
          #else
          # @logger.info "#{typ} NOT match, updating!"

          mismatch = []
          @repos_remote[typ].each_pair do |key, value|
            if value == @repos_local[typ][key]
              #@logger.info "Match! #{key}"
            else
              @logger.debug "Mismatch! #{key}"
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
                if mismatch.count > (@repos_remote[typ].count / 4)
                  @logger.info "Many files mismatched (#{mismatch.count}), running full update on .pack folder"
                  arr_opts = []
                  arr_opts << PARAMS
                  arr_opts << File.join(host, '.pack/.')
                  arr_opts << esc(pack_path)

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
          @repos_local[typ].each_pair do |key, value|
            if @repos_remote[typ][key].nil?
              @logger.info "File does not exist in remote! #{key}"
              del << key
            end
          end
          del.each { |e| del_file(e, typ) }
          @repos_local[typ] = calc_sums(typ)
          @repos_local[:version] = @repos_remote[:version]
          save_repos
        end

        def compare_sums(online = true)
          hosts = config[:hosts].clone
          host = hosts.sample
          done = true

          ## Pack
          if online
            done = false
            while hosts.size > 0 && !done do
              host = hosts.sample
              hosts -= [host]

              begin
                fetch_file(".pack/.repository.yml", host)

                # TODO: CLEANUP, Should depricate in time.
                if FileTest.exists? pack_path('.repository.yml')
                  [pack_path('.version'), pack_path('.sums.yml'), File.join(@rsync_work_dir, '.sums.yml')].each do |f|
                    FileUtils.rm_f f if FileTest.exists? f
                  end
                end

                load_repos(:remote)
                load_repos(:local)

                if @repos_local[:version] > @repos_remote[:version] # && !force
                  @logger.warn "WARNING, version on server is OLDER, aborting!"
                  raise RsyncExecuteError
                end
                done = true
              rescue
                @logger.debug "Failed #{host}, trying next.."
              end
            end
          end
          if done
            # TODO: Don't do actions when not online
            compare_set(:pack, host)
            compare_set(:wd, host)
            save_repos
          end
        end

        def config
          @config ||= YAML::load(DEFAULT)
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
          arr_opts << esc(rsync_path(folder))

          command('', arr_opts)
        end

        def calc
          [:pack, :wd].each { |t| @repos_local[t] = calc_sums(t) }
        end

        def calc_sums(typ)
          ar = []
          reg = case typ
          when :pack
            ar = Dir[pack_path('**/*')]
            /\A[\\|\/]\.rsync[\\|\/]\.pack[\\|\/]/
          when :wd
            ar = Dir[File.join(@rsync_work_dir, '/**/*')]
            /\A[\\|\/]/
          end
          h = Hash.new
          ar.each do |file|
            relative = file.clone
            relative.gsub!(@rsync_work_dir, '')
            relative.gsub!(reg, '')

            sum = md5(file)
            h[relative] = sum if sum
          end
          h
        end

        def load_config
          # TODO: Remove after a while, depricated .pack
          old = File.join(@rsync_work_dir, '.pack')
          FileUtils.mv(old, pack_path) if FileTest.exists?(old)
          load_yaml(File.join(rsync_path, 'config.yml'))
        end

        def load_yaml(file)
          if FileTest.exist?(file)
            YAML::load_file(file)
          else
            nil
          end
        end

        def save_default_config
          FileUtils.mkdir_p rsync_path
          save_config(config)
        end

        def save_config(config = YAML::load(DEFAULT))
          File.open(File.join(rsync_path, 'config.yml'), 'w') { |file| file.puts config.to_yaml }
        end

        def save_repos(typ = :local)
          file, config = nil, nil
          case typ
          when :local
            file = rsync_path('.repository.yml')
            config = @repos_local.clone
          when :remote
            file = pack_path('.repository.yml')
            config = @repos_remote.clone
          end
          config[:pack] = config[:pack].sort
          config[:wd] = config[:wd].sort
          File.open(file, 'w') { |file| file.puts config.to_yaml }

          # TODO: CLEANUP, Should depricate in time.
          [File.join(@rsync_work_dir, '.rsync/.version'), File.join(@rsync_work_dir, '.rsync/sums_pack.yml'), File.join(@rsync_work_dir, '.rsync/sums_wd.yml')].each do |f|
            FileUtils.rm_f f  if FileTest.exists? f
          end
        end

        def load_repos(typ)
          config = Hash.new
          case typ
          when :local
            File.open(rsync_path('.repository.yml')) { |file| config = YAML::load(file) }
          when :remote
            if FileTest.exists?(pack_path('.repository.yml'))
              File.open(pack_path('.repository.yml')) { |file| config = YAML::load(file) }
            else
              # Deprecated
              config[:pack] = File.open(pack_path('.sums.yml')) { |file| YAML::load(file) }
              config[:wd] = File.open(File.join(@rsync_work_dir, '.sums.yml')) { |file| YAML::load(file) }
              config[:version] = File.open(pack_path('.version')) { |file| file.read.to_i }
            end
          end
          [:wd, :pack].each do |t|
            h = Hash.new
            config[t].each { |e| h[e[0]] = e[1] }
            config[t] = h
          end
          case typ
          when :local
            @repos_local = config
          when :remote
            @repos_remote = config
          end
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

        def del_file(file, typ, opts = {})
          file = case typ
          when :pack
            File.join(DIR_PACK, file)
          when :wd
            file
          end
          FileUtils.rm_f File.join(@rsync_work_dir, file)
        end

        def unpack_file(file, path)
          Dir.chdir(path) do |dir|
            zip7(file)
            # TODO: Evaluate if this is actually wanted / useful at all..
=begin
            if file[/\.tar\.?/]
              file[/(.*)\/(.*)/]
              fil = $2
              fil = file unless fil
              f2 = fil.gsub('.gz', '')
              zip7(f2)
              FileUtils.rm_f f2
            end
=end
          end
        end

        def zip7(file)
          out = %x[7za x #{esc(file)} -y]
          @logger.debug out
          out
        end

        def unpack(opts = {})
          items = if opts[:path]
            [pack_path(opts[:path])]
          else
            Dir[pack_path('**/*')]
          end

          items.each do |file|
            unless File.directory? file
              relative = file.clone
              relative.gsub!(@rsync_work_dir, '')
              relative.gsub!(/\A[\\|\/]\.rsync[\\|\/]\.pack[\\|\/]/, '')
              fil = relative
              folder = "."
              folder, fil = $1, $2 if relative[/(.*)\/(.*)/]
              #puts "Relative: #{relative}, Folder: #{folder}, File: #{fil} (Origin: #{file})"

              path = File.join(@rsync_work_dir, folder)
              FileUtils.mkdir_p path
              unpack_file(file, path)
            end
          end
        end

        def gzip(file)
          @logger.info "Packing #{file}"
          out = %x[gzip -f --best --rsyncable --keep #{esc(file)}]
          @logger.debug out
        end

        def md5(path)
          unless File.directory? path
            path[/(.*)[\/|\\](.*)/]
            folder, file = $1, $2
            Dir.chdir(folder) do
              r = %x[md5sum #{esc(file)}]
              @logger.debug r
              r[/\A\w*/]
            end
          end
        end

        def rsync_path(path = '')
          p = File.join(@rsync_work_dir, DIR_RSYNC)
          p = File.join(p, path) unless path.size == 0
          p
        end

        def pack_path(path = '')
          p = File.join(@rsync_work_dir, DIR_PACK)
          p = File.join(p, path) unless path.size == 0
          p
        end

        def escape(s)
          "\"" + s.to_s.gsub('\"', '\"\\\"\"') + "\""
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
            #if ENV['six-app-root']
            #  rsync_cmd.gsub!(drive, "\"#{ENV['six-app-root']}") # /cygdrive/#{$1}
            #else
            rsync_cmd.gsub!(drive, "\"/cygdrive/#{$1}")
            #end
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
      end
    end
  end
end
