# encoding: UTF-8

module Six
  module Repositories
    module Rsync
      DIR_RSYNC = '.rsync'
      DIR_PACK = File.join(DIR_RSYNC, '.pack')

      class RsyncExecuteError < StandardError; end
      class RsyncError < StandardError; end

      class Lib
        attr_accessor :verbose
        PROTECTED = false
        WINDRIVE = /\"(\w)\:/
        DEFAULT_CONFIG = {:hosts => [], :exclude => []}.to_yaml
        DEFAULT_TIMEOUT = 60
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
          @logger = logger

          case RUBY_PLATFORM
            when /-mingw32$/, /-mswin32$/
              key = CONFIG[:key] ? CONFIG[:key] : ""
              @rsh = "-r --rsh=\"'cygnative.exe' plink.exe#{" -i #{key}" unless key.empty?}\""
            else
              @rsh = ""
          end

          # which rsync - should return on linux the bin location
          rsync_installed = begin; %x[rsync --version]; true; rescue; false; end
          unless rsync_installed
            puts "rsync command not found"
            raise RsyncError
          end

          @repos_local = {:pack => Hash.new, :wd => Hash.new, :version => 0}
          @repos_remote = {:pack => Hash.new, :wd => Hash.new, :version => 0}

          if base.is_a?(Rsync::Base)
            @rsync_dir = base.repo.path
            @rsync_work_dir = base.dir.path if base.dir
          elsif base.is_a?(Hash)
            @rsync_dir = base[:repository]
            @rsync_work_dir = base[:working_directory]
          end
        end

        def status
          @logger.info "Showing changes on #{@rsync_work_dir}"
          handle_config

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
              @logger.info "Modified: #{i}/#{@repos_local[:wd].size}: #{key}"
            end
          end

          # Deleted files
          @logger.info "Checking for deleted files..."

          i = 0
          @repos_remote[:wd].each_pair do |key, value|
            i += 1
            if @repos_local[:wd][key].nil?
              @logger.info "Removed: #{key}"
            end
          end

          @repos_local[:pack].each_pair do |key, value|
            i += 1
            localkey = "#{key}"
            localkey.gsub!(/\.gz$/, "")
            if @repos_local[:wd][localkey].nil?
              @logger.info "Removed: #{key}"
            end
          end

        end

        def init
          @logger.info "Processing: #{rsync_path}"
          if File.exists? rsync_path
            @logger.error "Seems to already be an Rsync repository, Aborting!"
            raise RsyncError
          end
          if File.exists? @rsync_work_dir
            unless Dir[File.join(@rsync_work_dir, '*')].empty?
              @logger.error "Folder not empty, Aborting!"
              raise RsyncError
            end
          end
          FileUtils.mkdir_p pack_path
          save_config(config)
          save_repos(:local)
          save_repos(:remote)
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
            ar.each_with_index do |file, i|
              unless file[/\.gz$/]
                relative = file.clone
                relative.gsub!(@rsync_work_dir, '')
                relative.gsub!(/^[\\|\/]/, '')

                checksum = md5(file)
                if checksum != @repos_remote[:wd][relative]
                  change = true
                  @logger.info "Packing #{i + 1}/#{ar.size}: #{file}"
                  gzip(file)
                  @repos_remote[:wd][relative] = checksum
                  @repos_remote[:pack]["#{relative}.gz"] = md5("#{file}.gz")
                  FileUtils.mv("#{file}.gz", pack_path("#{relative}.gz"))
                end
              end
            end
            save_repos if change
          else

          end
        end

        def commit
          cfg = CONFIG[:commit] ? CONFIG[:commit] : Hash.new
          @logger.info "Committing changes on #{@rsync_work_dir}"
          handle_config
          handle_hosts

          load_repos(:local)
          load_repos(:remote)

=begin
  # TODO: Rewrite
          if cfg[:force_downcase]
            # Run through all files, only in the working folder!, and downcase those which are not
            Dir.glob(File.join(@rsync_work_dir, '**', '*')).each do |entry|
              dirname, base = File.dirname(entry), File.basename(entry)
              if base[/[A-Z]/]
                part = entry.sub("#{@rsync_work_dir}", '')
                part.sub!(/^\//, "")
                if @repos_local[:wd][part]
                  @repos_local[:wd].delete part
                  @repos_local[:wd][]
                end
                rename(entry, File.join(dirname, base.downcase))
              end
            end
          end
=end

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
              folder = File.dirname(file)
              folder.gsub!(@rsync_work_dir, '')
              gzip(file)
              @repos_local[:pack]["#{key}.gz"] = md5("#{file}.gz")
              FileUtils.mkdir_p pack_path(folder) if folder.size > 0
              FileUtils.mv("#{file}.gz", pack_path("#{key}.gz"))
            end
          end

          # Deleted files
          @logger.info "Checking for deleted files..."

          i = 0
          @repos_remote[:wd].each_pair do |key, value|
            i += 1
            if @repos_local[:wd][key].nil?
              packed = "#{key}.gz"
              change = true
              file = pack_path(packed)

              @logger.info "Removing: #{packed}"
              @repos_local[:wd].delete key
              @repos_local[:pack].delete packed              
              FileUtils.rm_f(file) if File.exists?(file)
            end
          end

          @repos_local[:pack].each_pair do |key, value|
            i += 1
            localkey = "#{key}"
            localkey.gsub!(/\.gz$/, "")
            if @repos_local[:wd][localkey].nil?
              @logger.info "Removing: #{key}"

              change = true
              file = pack_path(key)
              @repos_local[:pack].delete key
              FileUtils.rm_f(file) if File.exists?(file)
            end
          end
          

          if change
            @logger.info "Changes found!"
            save_repos(:local)

            host = config[:hosts].sample

            verfile_srv = File.join(".pack", ".repository.yml")
            verbose = @verbose
            @verbose = false
            begin
              fetch_file(verfile_srv, host)
            rescue => e
              # FIXME: Should never assume that :)
              @logger.warn "Unable to retrieve version file from server, repository probably doesnt exist!"
              @logger.debug "ERROR: #{e.class} #{e.message} #{e.backtrace.join("\n")}"
              # raise RsyncExecuteError
            end
            @verbose = verbose

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
          handle_config
          handle_hosts

          host = config[:hosts].sample unless host
          arr_opts = []
          arr_opts << PARAMS
          arr_opts << @rsh if host[/^(\w)*\@/]
          arr_opts << esc(pack_path('.'))
          arr_opts << esc(File.join(host, '.pack'))

          # Upload .pack changes
          command('', arr_opts)
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

          # TODO: Eval move to update?
          arr_opts = []
          arr_opts << "-I" if opts[:force]

          init
          update('', arr_opts, {:force => true})
          opts[:bare] ? {:repository => @rsync_work_dir} : {:working_directory => @rsync_work_dir}
        end

        def update(cmd, x_opts = [], opts = {})
          @logger.debug "Checking for updates..."

          handle_config
          handle_hosts

          load_repos(:local)
          begin
            load_repos(:remote)
          rescue
            @logger.warn "WARN: .pack/.repository.yml seems corrupt, forcing full check"
            opts[:force] = true
          end

          hosts = config[:hosts].clone
          host = hosts.sample

          if opts[:force]
            done = false
            b, i = false, 0
            #verbose = @verbose
            #@verbose = false
            until hosts.empty? || done do
              i += 1
              # FIXME: Nasty
              host = hosts.sample if b
              b = true
              hosts -= [host]
              @logger.info "Trying #{i}/#{config[:hosts].size}: #{host}"
              begin
                arr_opts = []
                arr_opts << PARAMS
                arr_opts += x_opts
                arr_opts << @rsh if host[/^(\w)*\@/]
                arr_opts << esc(File.join(host, '.pack/.'))
                arr_opts << esc(pack_path)
                command(cmd, arr_opts)
                load_repos(:remote)
                done = true
              rescue => e
                @logger.debug "#{e.class}: #{e.message} #{e.backtrace.join("\n")}"
              end
            end
            #@verbose = verbose
            if done
              calc
              save_repos
              @logger.info "Verifying Unpacked files..."
              compare_set(:wd)
              # Bump version and make final save
              @repos_local[:version] = @repos_remote[:version]
              save_repos
            else
              @logger.warn "Exhausted all mirrors, please retry!"
              raise RsyncError
            end
          else
            #reset(:hard => true)
            calc
            save_repos

            # fetch latest sums and only update when changed
            compare_sums(true, host)
          end
        end

        def compare_sums(online = true, host = config[:hosts].sample)
          load_repos(:local)
          done = false

          if online
            hosts = config[:hosts].clone
            b, i = false, 0
            verbose = @verbose
            @verbose = false

            until hosts.empty? || done do
              i += 1
              # FIXME: Nasty
              host = hosts.sample if b
              b = true
              hosts -= [host]
              @logger.info "Trying #{i}/#{config[:hosts].size}: #{host}"

              begin
                FileUtils.cp(pack_path(".repository.yml"), rsync_path(".repository-pack.yml")) if File.exists?(pack_path(".repository.yml"))
                fetch_file(".pack/.repository.yml", host)
                load_repos(:remote)

                if @repos_local[:version] > @repos_remote[:version] # && !force
                  @logger.warn "WARNING, version on server is OLDER, aborting!"
                  raise RsyncError
                end
                done = true
              rescue => e
                @logger.debug "#{e.class} #{e.message}: #{e.backtrace.join("\n")}"
                FileUtils.cp(rsync_path(".repository-pack.yml"), pack_path(".repository.yml")) if File.exists?(rsync_path(".repository-pack.yml"))
              ensure
                FileUtils.rm(rsync_path(".repository-pack.yml")) if File.exists?(rsync_path(".repository-pack.yml"))
              end
            end
            @verbose = verbose
          else
            load_repos(:remote)
          end

          if done && online
            @logger.info "Verifying Packed files..."
            compare_set(:pack, host)

            @logger.info "Verifying Unpacked files..."
            compare_set(:wd, host)

            # Bump version and make final save
            @repos_local[:version] = @repos_remote[:version]
            save_repos
          end
        end

        def compare_set(typ, host = nil, online = true)
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
              done = false

              ## Pack
              if online
                hosts = config[:hosts].clone
                host = hosts.sample unless host
                b, i = false, 0
                until hosts.empty? || done do
                  i += 1
                  # FIXME: Nasty
                  if b
                    host = hosts.sample
                    @logger.info "Trying #{i}/#{config[:hosts].size}: #{host}"
                  end
                  slist = nil
                  b = true
                  hosts -= [host]

                  # TODO: Progress bar
                  arr_opts = []
                  arr_opts << PARAMS
                  arr_opts << @rsh if host[/^(\w)*\@/]

                  if mismatch.size > (@repos_remote[typ].size / 2)
                    # Process full folder
                    @logger.info "Many files mismatched (#{mismatch.size}), running full update on .pack folder"
                  else
                    # Process only selective
                    @logger.info "Fetching #{mismatch.size} files... Please wait"
                    slist = File.join(TEMP_PATH, ".six-rsync_#{rand 9999}-list")
                    slist.gsub!("\\", "/")
                    File.open(slist, 'w') { |f| mismatch.each { |e| f.puts e } }

                    arr_opts << "--files-from=#{win2cyg("\"#{slist}\"")}"
                  end

                  begin
                    arr_opts << esc(File.join(host, '.pack/.'))
                    arr_opts << esc(pack_path)
                    command('', arr_opts)

                    done = true
                  rescue => e
                    @logger.debug "ERROR: #{e.class} #{e.message} #{e.backtrace.join("\n")}"
                  ensure
                    FileUtils.rm_f slist if slist
                  end
                end
                unless done
                  @logger.warn "Exhausted all mirrors, please retry!"
                  raise RsyncError
                end
              end
            when :wd
              mismatch.each_with_index do |e, index|
                # TODO: Nicer progress bar...
                @logger.info "Unpacking #{index + 1}/#{mismatch.size}: #{e}"
                unpack(:path => "#{e}.gz")
              end
            end
          end

          @repos_local[typ].each_pair do |key, value|
            del_file(key, typ) unless config[:exclude].include?(key) || !@repos_remote[typ][key].nil?
          end

          # Calculate new sums
          @repos_local[typ] = calc_sums(typ)

          # Save current progress, incase somewhere else goes wrong.
          save_repos
        end


        private
        def handle_config
          @config = load_config
          unless @config
            @logger.error "Not an Rsync repository!"
            raise RsyncError
          end
        end

        def handle_hosts
          unless config[:hosts].size > 0
            @logger.error "No hosts configured!"
            raise RsyncError
          end
        end

        def rename(entry, newentry)
          FileUtils.mv(entry, "#{entry}_tmp")
          FileUtils.mv("#{entry}_tmp", newentry)
        end

        def win2cyg(path)
          path = path.clone
          #path.gsub!(WINDRIVE) {|s| "\"/cygdrive/#{s}" }
          while path[WINDRIVE]
            drive = path[WINDRIVE]
            path.gsub!(drive, "\"/cygdrive/#{$1}")
          end
          path
        end

        def esc(val); "\"#{val}\""; end
        def escape(s); "\"" + s.to_s.gsub('\"', '\"\\\"\"') + "\""; end

        def config
          cfg = @config ||= YAML::load(DEFAULT_CONFIG)
          cfg[:exclude] = [] unless cfg[:exclude]
          cfg[:hosts] = [] unless cfg[:hosts]
          cfg
        end

        def rsync_path(path = '')
          p = File.join(@rsync_work_dir, DIR_RSYNC)
          path.size == 0 ? p : File.join(p, path)
        end

        def pack_path(path = '')
          p = File.join(@rsync_work_dir, DIR_PACK)
          path.size == 0 ? p : File.join(p, path)
        end

        def fetch_file(path, host)
          folder = File.dirname(path)
          # Only fetch a specific file
          @logger.debug "Fetching #{path} from  #{host}"
          arr_opts = []
          arr_opts << PARAMS
          arr_opts << @rsh if host[/^(\w)*\@/]
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
            /^[\\|\/]\.rsync[\\|\/]\.pack[\\|\/]/
          when :wd
            ar = Dir[File.join(@rsync_work_dir, '/**/*')]
            /^[\\|\/]/
          end
          h = Hash.new
          ar.each do |file|
            relative = file.clone
            relative.gsub!(@rsync_work_dir, '')
            relative.gsub!(reg, '')

            next if config[:exclude].include?(relative)
            sum = md5(file)
            h[relative] = sum if sum
          end
          h
        end

        def load_config; load_yaml(File.join(rsync_path, 'config.yml')); end

        def load_yaml(file)
          File.exists?(file) ? YAML::load_file(file) : nil
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
        end

        def load_repos(typ)
          config = case typ
          when :local
            YAML::load_file(rsync_path('.repository.yml'))
          when :remote
            YAML::load_file(pack_path('.repository.yml'))
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
          path = case typ
          when :pack
            File.join(@rsync_work_dir, DIR_PACK, file)
          when :wd
            File.join(@rsync_work_dir, file)
          end
          if File.exists?(path)
            FileUtils.rm_f File.join(path)
            @logger.info "Removed: #{file}"
          end
        end

        def md5(path)
          unless @md5_installed ||= begin; %x[md5sum --help]; $? == 0; rescue; false; end
            puts "md5sum command not found"
            raise RsyncError
          end

          unless File.directory? path
            folder, file = File.dirname(path), File.basename(path)
            Dir.chdir(folder) do
              r = %x[md5sum #{esc(file)}]
              @logger.debug r
              r[/^\w*/]
            end
          end
        end

        def zip7(file)
          unless @zip7_installed ||= begin; %x[7z --help]; $? == 0; rescue; false; end
            puts "7z command not found"
            raise RsyncError
          end
          out = %x[7z x #{esc(file)} -y]
          @logger.debug out
          raise RsyncError if $? != 0
          out
        end

        def gzip(file)
          unless @gzip_installed ||= begin; %x[gzip --rsyncable --help]; $? == 0; rescue; false; end
            puts "gzip command not found, or doesn't support --rsyncable"
            raise RsyncError
          end
          @logger.debug "Gzipping #{file}"
          out = %x[gzip -f --best --rsyncable --keep #{esc(file)}]
          @logger.debug out
          raise RsyncError if $? != 0
          out
        end

        def unpack_file(file, path)
          Dir.chdir(path) do |dir|
            zip7(file)
            # TODO: Evaluate if this is actually wanted / useful at all..
=begin
            if file[/\.tar\.?/]
              fil = File.basename(file)
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
              relative.gsub!(/^[\\|\/]\.rsync[\\|\/]\.pack[\\|\/]/, '')
              folder = File.dirname(relative)
              fil = File.basename(relative)
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
          opts << "--timeout=#{DEFAULT_TIMEOUT}"

          opts = [opts].flatten.map {|s| s }.join(' ') # escape()
          rsync_cmd = win2cyg("rsync #{cmd} #{opts} #{redirect}") # 2>&1

          @logger.debug(rsync_cmd) if @logger

          out = chdir && (Dir.getwd != path) ? Dir.chdir(path) { run_command(rsync_cmd, &block) } : run_command(rsync_cmd, &block) 
          out
        end

        def run_command(rsync_cmd, &block)
          out, err = '', ''
          buff = []
          status = nil
          oldsync = STDOUT.sync
          STDOUT.sync = true

          po = Open3.popen3(rsync_cmd) do |io_in, io_out, io_err, waitth|
            io_out.each_byte do |buffer|
              char = buffer.chr
              buff << char
              if ["\n", "\r"].include?(char)
                b = buff.join("")
                print b if @verbose                
                out << b
                buff = []
              end
            end

            io_err.each do |line|
              print line
              case line
              when /max connections \((.*)\) reached/
                @logger.warn "Server reached maximum connections."
              end
              err << line
            end
            status = waitth.value
          end

          unless buff.empty?
            b = buff.join("")
            print b if @verbose
            out << b
          end

          @logger.debug "Status: #{status}"
          @logger.debug "Err: #{err}" # TODO: Throw this into the info/error log?
          @logger.debug "Output: #{out}"

          if status.exitstatus > 0
            #return 0 if status.exitstatus == 1 && out == ''
            raise Rsync::RsyncExecuteError.new(rsync_cmd + ':' + err + ':' + out)
          end

          STDOUT.sync = false unless STDOUT.sync == oldsync

          status
        end

=begin
          # Simpler method but on windows the !? exitstatus is not working properly..
          # Does nicely display error output in logwindow though
          io = IO.popen(rsync_cmd)
          io.sync = true

          #io.each do |buffer|
          #  process_msg buffer
          #  out << buffer
          #end
          out[/rsync error: .* \(code ([0-9]*)\)/]
          status = $1 ? $1.to_i : 0
            case out
              when /max connections \((.*)\) reached/
                @logger.warn "Server reached maximum connections."
            end
=end
      end
    end
  end
end
