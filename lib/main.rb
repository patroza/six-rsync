=begin
  7za.exe can be used to unpack the gzips!
  TODO: Move all tool downloads and fetches (even server gits?) to rsync ;-)

2 methods:
  a) Put the modfolder into a .7z, distribute this .7z together with the updater. The updater will unpack it, and then rsync future updates, with uncompressed files.
  b) Put each addon in an --rsyncable gzip, initial installation and future updates happen over rsync, with .gz files.

exclude root\.six

Am I Up2date checks seems to be heavy on large repositories
Hash, in yaml, with md5 sums, and version number sounds like the only logical solution ?,
verify this file in server for verifying same status ?
maybe also write md5 checklist of client too.

second thought, without -I,  and with   --times, it goes quick as fuck due to filedate/size comparison!
rsync --times -O --no-whole-file -r --delete --stats --progress rsync://dev-heaven.net/rel/caa1 .

However, better to work with an md5 sum file :D
Just 2 lists to maintain :O unpacked and packed :O
  

=end

require 'log4r'
require 'six/rsync'

COMPONENT = 'six-rsync'

# Create loggers
log = Log4r::Logger.new(COMPONENT)
format1 = Log4r::PatternFormatter.new(:pattern => "[%l] %d: %m", :date_pattern => '%H:%M:%S')
format2 = Log4r::PatternFormatter.new(:pattern => "[%l] %c %d: %m", :date_pattern => '%H:%M:%S')

if not defined?(Ocra)
  # Create Outputters
  o_file = Log4r::FileOutputter.new "#{COMPONENT}-file",
    'level' => 0, # All
  :filename => "#{COMPONENT}.log",
    'formatter' =>  format2
  #:maxsize => 1024

  log.outputters << o_file

  o_out = Log4r::StdoutOutputter.new "#{COMPONENT}-stdout",
    'level' => 2, # no DEBUG
  'formatter' =>  format1

  o_err = Log4r::StderrOutputter.new "#{COMPONENT}-stderr",
    'level' => 4, # Error and Up
  'formatter' =>  format1

  log.outputters << o_out << o_err
end

#sync_remote('rsync://git.dev-heaven.net/rel/caa1', 'C:/temp/temp')
include Six::Repositories

=begin
host = "C:/temp/rsync/folder1/."
dir, folder = "C:/temp/rsync", 'folder2'
log.info "Test"

rs = Rsync.open(File.join(dir,folder), :log => log)
rs.update
p rs
=end

#dir = "C:/games/arma2"
dir = "C:/packaging/rsync"
host = "rsync://dev-heaven.net/rel"
repositories = ["beta"] #["cba", "ace", "acex", "six", "beta"] #, "caa1"]
repositories.each do |r|
  url = File.join(host, r, '/.')
  #Rsync.clone(url, "@#{r}test", :path => dir, :log => log)

  rs = Rsync.open(File.join(dir, r), :log => log)
  #rs = Rsync.open(File.join(dir, "@#{r}test"), :log => log)
  #rs.reset(:hard => true)
  rs.update
end
=begin
repositories.each do |r|
  url = File.join(host, r, '/.')
  begin
    Rsync.clone(url, r, :path => dir, :log => log)
  rescue
    log.error "Survived exception!"
  end
end
=end
#rs = Rsync.clone(host, folder, :path => dir, :log => log)
#rs = Rsync.open(dir)

module Six
  module Repositories
    module Rsync
    end

  end
end

=begin

--bwlimit=KBPS
This option allows you to specify a maximum transfer rate in kilobytes per second for the data the daemon sends. The client can still specify a smaller --bwlimit value, but their requested value will be rounded down if they try to exceed it. See the client version of this option (above) for some extra details.

  rsync -a --progress . rsync://dev-heaven.net/rel/caa1
rsync -a --progress rsync://dev-heaven.net/rel/caa1 .

-v, --verbose increase verbosity
-q, --quiet decrease verbosity
-c, --checksum always checksum
-a, --archive archive mode. It is a quick way of saying you want recursion and want to preserve everything.
-r, --recursive recurse into directories
-R, --relative use relative path names
-u, --update update only (don't overwrite newer files)
-t, --times preserve times
-n, --dry-run show what would have been transferred
-W, --whole-file copy whole files, no incremental checks
-I, --ignore-times Normally rsync will skip any files that are already the same length and have the same time-stamp. This option turns off this behavior.
--existing only update files that already exist
--delete delete files that don't exist on the sending side
--delete-after delete after transferring, not before
--force force deletion of directories even if not empty
-c, --checksum always checksum
--size-only only use file size when determining if a file should be transferred
--progress show progress during transfer
-z, --compress compress file data
--exclude=PATTERN exclude files matching PATTERN
--daemon run as a rsync daemon
--password-file=FILE get password from FILE

--bwlimit=KBPS
This option allows you to specify a maximum transfer rate in kilobytes per second for the data the daemon sends. The client can still specify a smaller --bwlimit value, but their requested value will be rounded down if they try to exceed it. See the client version of this option (above) for some extra details.
=end
