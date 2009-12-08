# encoding: UTF-8

# TODO: Add Rsync add, commit and push (Update should be pull?), either with staging like area like Git, or add is pack into .pack, and commit is update sum ?
# TODO: Seperate command lib from custom layer over rsync?

module Six
  module Repositories
    module Rsync
      # TODO: Configure somewhere!
      KEY = "C:/users/sb/documents/keys/id_rsa.ppk"
      RSH = "-r --rsh=\"'#{File.join(BASE_PATH, "tools", "bin", "cygnative.exe")}' plink.exe -i #{KEY}\""
      DIR_RSYNC = '.rsync'
      DIR_PACK = File.join(DIR_RSYNC, '.pack')
      REGEX_FOLDER = /(.*)[\\|\/](.*)/

      class RsyncExecuteError < StandardError
      end

      class RsyncError < StandardError
      end

      class Lib
        attr_accessor :verbose
        PROTECTED = false
        WINDRIVE = /\"(\w)\:/
        DEFAULT_CONFIG = {:hosts => [], :exclude => []}.to_yaml
        PARAMS = if PROTECTED
          "--dry-run --times -O --no-whole-file -r --delete --progress -h --exclude=.rsync"
        else
          "--times -O --no-whole-file -r --delete --progress -h --exclude=.rsync"
        end

        def initialize(base = nil, logger = nil)
          @rsync_dir = nil
          @rsync_work_dir = nil
          @path = nil
          @stats = false
          @verbose = true

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
            raise RsyncError
          end
          if FileTest.exist? @rsync_work_dir
            @logger.error "Seems to already be a folder, Aborting!"
            raise RsyncError
          end
          FileUtils.mkdir_p pack_path
          save_config(config)
          save_repos(:local)
          save_repos(:remote)
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
            rescue RsyncError
              @logger.error "Unable to sucessfully update, aborting..."
              @logger.debug "#{$!}"
              # Dangerous? :D
              FileUtils.rm_rf @rsync_work_dir if File.exists?(@rsync_work_dir)
              #rescue
              #  FileUtils.rm_rf @rsync_work_dir if File.exists?(@rsync_work_dir)
            end
          rescue RsyncError
            @logger.error "Unable to initialize"
            @logger.debug "#{$!}"
          end

          opts[:bare] ? {:repository => @rsync_work_dir} : {:working_directory => @rsync_work_dir}
        end

        def update(cmd, x_opts = [], opts = {})
          @logger.debug "Checking for updates..."
          @config = load_config
          unless @config
            @logger.error "Not an Rsync repository!"
            raise RsyncError
          end

          unless config[:hosts].size > 0
            @logger.error "No hosts configured!"
            raise RsyncError
          end

          #unpack

          # FIXME: This does not work when not forced, as host is sampled in comparesums :)
          host = config[:hosts].sample

          if opts[:force]
            @logger.info "Trying: #{host}, please wait..."
            arr_opts = []
            arr_opts << PARAMS
            arr_opts += x_opts
            if host[/\A(\w)*\@/]
              arr_opts << RSH#"-e ssh"
            end

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
            compare_sums(true, host)
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
            @logger.info "Calculating Checksums..."
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

          @logger.info "Calculating Checksums..."
          @repos_local[:wd] = calc_sums(:wd)
          # Added or Changed files
          ar = Dir[File.join(@rsync_work_dir, '/**/*')]


          change = false
          i = 0
          @repos_local[:wd].each_pair do |key, value|
            i += 1
            if value != @repos_remote[:wd][key]
              change = true
              @logger.info "Packing #{i}/#{@repos_local[:wd].size}: #{key}"
              file = File.join(@rsync_work_dir, key)
              file[REGEX_FOLDER]
              folder = $1
              folder.gsub!(@rsync_work_dir, '')
              gzip(file)
              @repos_local[:pack]["#{key}.gz"] = md5("#{file}.gz")
              FileUtils.mkdir_p pack_path(folder) if folder
              FileUtils.mv("#{file}.gz", pack_path("#{key}.gz"))
            end
          end

=begin
          i = 0
          ar.each do |file|
            i += 1
            unless file[/\.gz\Z/]
              relative = file.clone
              relative.gsub!(@rsync_work_dir, '')
              relative.gsub!(/\A[\\|\/]/, '')
              #checksum = md5(file)
              if @repos_local[:wd][relative] != @repos_remote[:wd][relative]
                relative[/(.*)\/(.*)/]
                folder = $1
                change = true
                @logger.info "Packing #{i}/#{ar.size}: #{relative}"
                gzip(file)
                #@repos_local[:wd][relative] = checksum
                @repos_local[:pack]["#{relative}.gz"] = md5("#{file}.gz")
                FileUtils.mkdir_p pack_path(folder) if folder
                FileUtils.mv("#{file}.gz", pack_path("#{relative}.gz"))
              end
            end
          end
=end
          # Deleted files
          @logger.info "Checking for deleted files..."

          @repos_remote[:wd].each_pair do |key, value|
            i += 1
            if @repos_local[:wd][key].nil?
              packed = "#{key}.gz"
              change = true
              file = pack_path(packed)
              file[REGEX_FOLDER]
              folder = $2

              @logger.info "Removing #{i}/#{@repos_remote[:wd].size}: #{packed}"
              @repos_local[:wd].delete key
              @repos_local[:pack].delete packed              
              FileUtils.rm_f(file) if File.exists?(file)
            end
          end

=begin
          p @repos_local[:wd]
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
              p file
              p local
              p @repos_local[:wd][local]
              puts
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
=end

          #gets
          if change
            @logger.info "Changes found!"
            cmd = ''
            save_repos(:local)

            host = config[:hosts].sample

            verfile_srv = File.join(".pack", ".repository.yml")
            begin
              verbose = @verbose
              @verbose = false
              fetch_file(verfile_srv, host)
              @verbose = verbose
            rescue
              @verbose = verbose
              # FIXME: Should never assume that :)
              @logger.warn "Unable to retrieve version file from server, repository probably doesnt exist!"
              @logger.debug "#{$!}"
              # raise RsyncExecuteError
            end
            load_repos(:remote)
            if @repos_local[:version] < @repos_remote[:version] # && !force
              @logger.warn "WARNING, version on server is NEWER, aborting!"
              raise RsyncError
            end
            @repos_local[:version] += 1
            @repos_remote[:version] = @repos_local[:version]
            @repos_remote[:pack] = @repos_local[:pack].clone
            @repos_remote[:wd] = @repos_local[:wd].clone
            save_repos(:remote)
            save_repos(:local)
            push(host)
          else
            @logger.info "No changes found!"
          end
        end

        def push(host = nil)
          @logger.info "Pushing..."
          @config = load_config
          host = config[:hosts].sample unless host
          # TODO: UNCLUSTERFUCK
          arr_opts = []
          arr_opts << PARAMS

          # Upload .pack changes
          if host[/\A(\w)*\@/]
            arr_opts << RSH
          end
          arr_opts << esc(pack_path('.'))
          arr_opts << esc(File.join(host, '.pack'))

          command('', arr_opts)
        end

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
                hosts = config[:hosts].clone
                done = false

                ## Pack
                if online
                  b = false
                  while hosts.size > 0 && !done do
                    # FIXME: Nasty
                    if b
                      host = hosts.sample
                      @logger.info "Trying #{host}"
                    end
                    b = true
                    hosts -= [host]
                    begin
                      # TODO: Progress bar
                      if mismatch.count > (@repos_remote[typ].count / 2)
                        @logger.info "Many files mismatched (#{mismatch.count}), running full update on .pack folder"
                        arr_opts = []
                        arr_opts << PARAMS
                        if host[/\A(\w)*\@/]
                          arr_opts << RSH
                        end

                        arr_opts << esc(File.join(host, '.pack/.'))
                        arr_opts << esc(pack_path)
                        command('', arr_opts)
                      else
                        c = mismatch.size
                        @logger.info "Fetching #{mismatch.size} files... Please wait"
                        slist = File.join(TOOLS_PATH, ".six-updater_#{rand 9999}-list")
                        File.open(slist, 'w') do |f|
                          mismatch.each { |e| f.puts e }
                        end
                        arr_opts = []
                        arr_opts << PARAMS
                  
                        arr_opts << RSH if host[/\A(\w)*\@/]

                        slist = "\"#{slist}\""

                        while slist[WINDRIVE] do
                          drive = slist[WINDRIVE]
                          slist.gsub!(drive, "\"/cygdrive/#{$1}")
                        end
                        arr_opts << "--files-from=#{slist}"

                        arr_opts << esc(File.join(host, '.pack/.'))
                        arr_opts << esc(pack_path)

                        command('', arr_opts)
                        FileUtils.rm_f slist
                      end
                      done = true
                    rescue
                      @logger.warn "Failure"
                      @logger.debug "#{$!}"
                    end
                  end
                  @logger.warn "There was a problem during updating, please retry!" unless done
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
              del << key unless config[:exclude].include?(key)
            end
          end
          del.each { |e| del_file(e, typ) }
          @repos_local[typ] = calc_sums(typ)
          @repos_local[:version] = @repos_remote[:version]
          save_repos
        end

        def compare_sums(online = true, host = config[:hosts].sample)
          hosts = config[:hosts].clone
          done = false

          ## Pack
          if online
            b = false
            while hosts.size > 0 && !done do
              # FIXME: Nasty
              host = hosts.sample if b
              b = true
              hosts -= [host]
              @logger.info "Trying #{host}"

              begin
                verbose = @verbose
                @verbose = false
                fetch_file(".pack/.repository.yml", host)
                @verbose = verbose

                load_repos(:remote)
                load_repos(:local)

                if @repos_local[:version] > @repos_remote[:version] # && !force
                  @logger.warn "WARNING, version on server is OLDER, aborting!"
                  raise RsyncError
                end
                done = true
              rescue
                @logger.debug "#{$!}"
              end
            end
            # TODO: CLEANUP, Should depricate in time.
            if FileTest.exists? pack_path('.repository.yml')
              [pack_path('.version'), pack_path('.sums.yml'), File.join(@rsync_work_dir, '.sums.yml')].each do |f|
                FileUtils.rm_f f if FileTest.exists? f
              end
            end
          end
          if done || online
            # TODO: Don't do actions when not online
            @logger.info "Verifying Packed files..."
            compare_set(:pack, host)
            @logger.info "Verifying Unpacked files..."
            compare_set(:wd, host)
            save_repos
          end
        end

        private
        def config
          cfg = @config ||= YAML::load(DEFAULT_CONFIG)
          cfg[:exclude] = [] unless cfg[:exclude]
          cfg[:hosts] = [] unless cfg[:hosts]
          cfg
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

        def esc(val)
          "\"#{val}\""
        end

        def escape(s)
          "\"" + s.to_s.gsub('\"', '\"\\\"\"') + "\""
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
            arr_opts << RSH
          end
          arr_opts << esc(File.join(host, path))
          arr_opts << esc(rsync_path(folder))

          command('', arr_opts)
        end

        def calc
          @logger.info "Calculating checksums"
          [:pack, :wd].each { |t| @repos_local[t] = calc_sums(t) }
        end

        def calc_sums(typ)
          @logger.debug "Calculating checksums of #{typ} files"
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
            h[relative] = sum if sum && !config[:exclude].include?(relative)
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

        def save_config(config = YAML::load(DEFAULT_CONFIG))
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
              config[:wd] = File.open(File.join(@rsync_work_dir, '.sums.yml')) { |file| YAML::load(file) }
              config[:pack] = File.open(pack_path('.sums.yml')) { |file| YAML::load(file) }
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

        def del_file(file, typ, opts = {})
          file = case typ
          when :pack
            File.join(DIR_PACK, file)
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
              r = %x[md5sum #{esc(file)}]
              @logger.debug r
              r[/\A\w*/]
            end
          end
        end

        def zip7(file)
          out = %x[7z x #{esc(file)} -y]
          @logger.debug out
          out
        end

        def gzip(file)
          @logger.debug "Gzipping #{file}"
          out = %x[gzip -f --best --rsyncable --keep #{esc(file)}]
          @logger.debug out
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

        def command_lines(cmd, opts = [], chdir = true, redirect = '')
          command(cmd, opts, chdir).split("\n")
        end

        def command(cmd, opts = [], chdir = true, redirect = '', &block)
          path = @rsync_work_dir || @rsync_dir || @path

          opts << "--stats" if @stats

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

          if @logger
            @logger.debug(rsync_cmd)
          end

          out = nil
          if chdir && (Dir.getwd != path)
            Dir.chdir(path) { out = run_command(rsync_cmd, &block) }
          else
            out = run_command(rsync_cmd, &block)
          end

          #@logger.debug(out)

          out
        end

        def run_command(rsync_cmd, &block)
          # TODO: Make this switchable? Verbosity ?
          # Or actually parse this live for own stats?
          #puts rsync_cmd
          s = nil
          out = ''
          $stdout.sync = true # Seems to fix C:/Packaging/six-updater/NEW - Copy/ruby/lib/ruby/gems/1.9.1/gems/log4r-1.0.5/lib/log4r/outputter/iooutputter.rb:43:in `flush': Broken pipe (Errno::EPIPE)

          # Simpler method but on windows the !? exitstatus is not working properly..
          # Does nicely display error output in logwindow though
          #io = IO.popen(rsync_cmd)
          #io.sync = true
          #io.each do |buffer|
          #  process_msg buffer
          #  out << buffer
          #end
          status = Open3.popen3(rsync_cmd) { |io_in, io_out, io_err, waitth|
            io_out.sync = true
            io_err.sync = true

            io_out.each do |buffer|
              process_msg buffer
              out << buffer
            end

            #while !io_out.eof?
            #  buffer = io_out.readline
            #  # print buf#.gsub("\r", '')
            #  process_msg buffer
            #  out << buffer
            #end
            error = io_err.gets
            if error
              @logger.debug "Error: " + error.chomp
              #     exit
            end
            #   puts "Result: " + io_out.gets
            s = waitth.value
          }
          # FIXME: This doesn't work with the new popen or is there a way?
          if s.exitstatus > 0
            @logger.debug "Exitstatus: #{s.exitstatus}"
            if (s.exitstatus == 1 && out.size == 0)# || s.exitstatus == 5
              return ''
            end
            if out.to_s =~ /max connections \((.*))\ reached/
              @logger.warn "Server reached maximum connections."
            end
            raise Rsync::RsyncExecuteError.new(rsync_cmd + ':' + out.to_s)
          end
          status
        end

        def process_msg(msg)
          if msg[/[k|m|g]?B\/s/i]
            msg.gsub!("\n", '')
            print "#{msg}\r" if @verbose
          else
            @logger.debug msg
            print msg if @verbose
          end
          msg

=begin
          m = nil
          if msg[/\r/]
            # TODO; must still be written even if there is no next message :P

            if @write
              print msg
            end
            m = msg.gsub("\r", '')
            #@previous = m
          else
            m = msg
            #if @previous
            #  @logger.debug @previous
            #  @previous = nil
            #end
            #unless @previous
            #  @logger.debug m
            #end
            @logger.debug m
            puts m if @write
          end
          m
=end
        end
      end
    end
  end
end
