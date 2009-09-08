=begin
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


require 'six/rsync'
module Six
  module Rsync
    sync_remote('rsync://git.dev-heaven.net/rel/caa1', 'C:/temp/temp')
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
