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

          @config_local = {:pack => Hash.new, :wd => Hash.new, :version => 0}
          @config_remote = {:pack => Hash.new, :wd => Hash.new, :version => 0}

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
            #return
          end
          if FileTest.exist? @rsync_work_dir
            @logger.error "Seems to already be a folder, Aborting!"
            raise RsyncExecuteError
            #return
          end
          FileUtils.mkdir_p rsync_path
          # TODO: .pack path should be formulized
          FileUtils.mkdir_p File.join(@rsync_work_dir, '.rsync', '.pack')
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

          # begin
          init

          # TODO: Eval move to update?
          arr_opts = []
          arr_opts << "-I" if opts[:force]
          #  begin
          update('', arr_opts)
          #  rescue
          #   @logger.error "Unable to sucessfully update, aborting..."
          # Dangerous? :D
          #   FileUtils.rm_rf @rsync_work_dir
          # end
          #rescue
          #  @logger.error "Unable to initialize"
          #end

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
            arr_opts << esc(File.join(@rsync_work_dir, '.rsync', '.pack'))

            command(cmd, arr_opts)
            [:pack, :wd].each do |t|
              @config_local[t] = calc_sums(t)
            end
            save_config
          else
            #reset(:hard => true)
            [:pack, :wd].each do |t|
              @config_local[t] = calc_sums(t)
            end
            save_config

            # fetch latest sums and only update when changed
            compare_sums
          end          
        end

        # TODO: Allow local-self healing, AND remote healing. reset and fetch?
        def reset(opts = {})
          @logger.info "Resetting!"
          if opts[:hard]
            @config = read_config
            [:pack, :wd].each do |t|
              @config_local[t] = calc_sums(t)
            end
            save_config

            compare_sums(false)
          end
        end

        def add(file)
          @logger.error "Please use commit instead!"
          return
          @logger.info "Adding #{file}"
          if (file == ".")
            load_config(:remote)
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
                if checksum != @config_remote[:wd][relative]
                  change = true
                  @logger.info "Packing #{i}/#{ar.size}: #{file}"
                  gzip(file)
                  @config_remote[:wd][relative] = checksum
                  @config_remote[:pack]["#{relative}.gz"] = md5("#{file}.gz")
                  FileUtils.mv("#{file}.gz", File.join(@rsync_work_dir, '.rsync', '.pack', "#{relative}.gz"))
                end
              end
            end
            if change
              save_config
              #File.open(File.join(@rsync_work_dir, '.sums.yml'), 'w') { |file| file.puts remote_wd[:list].sort.to_yaml }
              #File.open(File.join(@rsync_work_dir, '.rsync', '.pack', '.sums.yml'), 'w') { |file| file.puts remote_pack[:list].sort.to_yaml }
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

          load_config(:local)
          load_config(:remote)
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
              if checksum != @config_remote[:wd][relative]
                relative[/(.*)\/(.*)/]
                folder = $1
                change = true
                @logger.info "Packing #{i}/#{ar.size}: #{relative}"
                gzip(file)
                @config_local[:wd][relative] = checksum
                @config_local[:pack]["#{relative}.gz"] = md5("#{file}.gz")
                FileUtils.mkdir_p File.join(@rsync_work_dir, '.rsync', '.pack', folder) if folder
                FileUtils.mv("#{file}.gz", File.join(@rsync_work_dir, '.rsync', '.pack', "#{relative}.gz"))
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
              if @config_local[:wd][local].nil?
                relative[/(.*)\/(.*)/]
                folder = $1
                change = true
                @logger.info "Deleting #{i}/#{ar2.size}: #{relative}"
                @config_local[:wd].delete local
                @config_local[:pack].delete relative
               # FileUtils.rm_f(file)
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
            load_config(:remote)
            if @config_local[:version] < @config_remote[:version] # && !force
              @logger.warn "WARNING, version on server is NEWER, aborting!"
              raise RsyncExecuteError
            end
            @config_local[:version] += 1
            @config_remote[:version] = @config_local[:version]
            @config_remote[:pack] = @config_local[:pack].clone
            @config_remote[:wd] = @config_local[:wd].clone
            save_config(:remote)
            save_config(:local)

            # TODO: UNCLUSTERFUCK
            arr_opts = []
            arr_opts << PARAMS

            # Upload .pack changes
            if host[/\A(\w)*\@/]
              arr_opts << "-e ssh"
            end
            arr_opts << esc(File.join(@rsync_work_dir, '.rsync', '.pack/.'))
            arr_opts << esc(File.join(host, '.pack'))

            command(cmd, arr_opts)

            # TODO: UNCLUSTERFUCK
            arr_opts = []
            arr_opts << PARAMS
=begin
            if host[/\A(\w)*\@/]
              arr_opts << "-e ssh"
            end

            arr_opts << esc(File.join(@rsync_work_dir, '.rsync', '.pack', '.repository.yml'))
            arr_opts << esc(File.join(host, '.pack'))
            command(cmd, arr_opts)
=end
          end
        end

        private
        def unpack_file(file, path)
          Dir.chdir(path) do |dir|
            zip7(file)
            if file[/\.tar\.?/]
              file[/(.*)\/(.*)/]
              fil = $2
              fil = file unless fil
              f2 = fil.gsub('.gz', '')
              zip7(f2)
              FileUtils.rm_f f2
            end
          end
        end

        def zip7(file)
          out = %x[7za x #{esc(file)} -y]
          @logger.debug out
          out
        end

        def unpack(opts = {})
          items = if opts[:path]
            [File.join(@rsync_work_dir, '.rsync', '.pack', opts[:path])]
          else
            Dir[File.join(@rsync_work_dir, '.rsync', '.pack/**/*')]
          end

          items.each do |file|
            unless File.directory? file
              relative = file.clone
              relative.gsub!(@rsync_work_dir, '')
              relative.gsub!(/\A[\\|\/]\.rsync[\\|\/]\.pack[\\|\/]/, '')
              #puts "WorkDir: #{@rsync_work_dir}"
              #relative = file.gsub(/#{@rsync_work_dir}[\\|\/]\.pack[\\|\/]/, '')
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

        def rsync_path
          File.join(@rsync_work_dir, '.rsync')
        end

        def read_config
          if FileTest.exists?(File.join(@rsync_work_dir, '.pack'))
            FileUtils.mv(File.join(@rsync_work_dir, '.pack'), File.join(@rsync_work_dir, '.rsync', '.pack'))
          end
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
          arr_opts << esc(File.join(@rsync_work_dir, '.rsync', folder))

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
            ar = Dir[File.join(@rsync_work_dir, '.rsync', '/.pack/**/*')]
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

        def save_config(typ = :local)
          file, config = nil, nil
          case typ
          when :local
            file = File.join(@rsync_work_dir, '.rsync', '.repository.yml')
            config = @config_local.clone
          when :remote
            file = File.join(@rsync_work_dir, '.rsync', '.pack', '.repository.yml')
            config = @config_remote.clone
          end
          config[:pack] = config[:pack].sort
          config[:wd] = config[:wd].sort
          File.open(file, 'w') { |file| file.puts config.to_yaml }

          # TODO: Remove cleanup
          [File.join(@rsync_work_dir, '.rsync/.version'), File.join(@rsync_work_dir, '.rsync/sums_pack.yml'), File.join(@rsync_work_dir, '.rsync/sums_wd.yml')].each do |f|
            FileUtils.rm_f f  if FileTest.exists? f
          end
        end

        def load_config(typ)
          config = Hash.new
          case typ
          when :local
            File.open(File.join(@rsync_work_dir, '.rsync', '.repository.yml')) { |file| config = YAML::load(file) }
          when :remote
            if FileTest.exists?(File.join(@rsync_work_dir, '.rsync', '.pack', '.repository.yml'))
              File.open(File.join(@rsync_work_dir, '.rsync', '.pack', '.repository.yml')) { |file| config = YAML::load(file) }
            else
              # Deprecated
              config[:pack] = File.open(File.join(@rsync_work_dir, '.rsync', '.pack', '.sums.yml')) { |file| YAML::load(file) }
              config[:wd] = File.open(File.join(@rsync_work_dir, '.sums.yml')) { |file| YAML::load(file) }
              config[:version] = File.open(File.join(@rsync_work_dir, '.rsync', '.pack', '.version')) { |file| file.read.to_i }
            end
          end
          [:wd, :pack].each do |t|
            h = Hash.new
            config[t].each { |e| h[e[0]] = e[1] }
            config[t] = h
          end
          case typ
          when :local
            @config_local = config
          when :remote
            @config_remote = config
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

        def compare_set(typ, host, online = true)
          
          load_config(:local)
          load_config(:remote)
          #if local[typ][:md5] == remote[typ][:md5]
          #  @logger.info "#{typ} Match!"
          #else
          # @logger.info "#{typ} NOT match, updating!"

          mismatch = []
          @config_remote[typ].each_pair do |key, value|
            if value == @config_local[typ][key]
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
                if mismatch.count > (@config_remote[typ].count / 4)
                  @logger.info "Many files mismatched (#{mismatch.count}), running full update on .pack folder"
                  arr_opts = []
                  arr_opts << PARAMS
                  arr_opts << File.join(host, '.pack/.')
                  arr_opts << esc(File.join(@rsync_work_dir, '.rsync', '.pack'))

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
          @config_local[typ].each_pair do |key, value|
            if @config_remote[typ][key].nil?
              @logger.info "File does not exist in remote! #{key}"
              del << key
            end
          end
          @logger.info "To delete: #{del.join(',')}" if del.size > 0
          del.each { |e| del_file(e, typ) }
          @config_local[typ] = calc_sums(typ)
          @config_local[:version] = @config_remote[:version]
          save_config
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

              fetch_file(".pack/.repository.yml", host)

              if FileTest.exists? File.join(@rsync_work_dir, '.rsync', '.pack/.repository.yml')
                [File.join(@rsync_work_dir, '.rsync', '.pack/.version'), File.join(@rsync_work_dir, '.rsync', '.pack/.sums.yml'), File.join(@rsync_work_dir, '.sums.yml')].each do |f|
                  FileUtils.rm_f f  if FileTest.exists? f
                end
              end

              load_config(:remote)
              load_config(:local)

              if @config_local[:version] > @config_remote[:version] # && !force
                @logger.warn "WARNING, version on server is OLDER, aborting!"
                raise RsyncExecuteError
              end
              done = true
              # rescue
              #   @logger.debug "Failed #{host}, trying next.."
              # end
            end
          end
          if done
            # TODO: Don't do actions when not online
            compare_set(:pack, host)
            compare_set(:wd, host)
            save_config
          end
        end

        #        def write_version
        #          File.open(File.join(@rsync_work_dir, '.rsync/.version'), 'w') {|file| file.puts @version }
        #        end

        def del_file(file, typ, opts = {})
          file = case typ
          when :pack
            File.join('.pack', file)
          when :wd
            file
          end
          FileUtils.rm_f File.join(@rsync_work_dir, file)
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

        def escape(s)
          "\"" + s.to_s.gsub('\"', '\"\\\"\"') + "\""
        end
      end
    end
  end
end
