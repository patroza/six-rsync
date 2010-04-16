# encoding: utf-8
# six-rsync-mirror /var/rsync hosts
# hosts format: user@host_or_ip:/path/to/rsync/store
# Use with public/private key combo
PATH = ARGV[0]
ARGV -= [PATH]
ARGV.each do |repo|
        puts
        puts "Processing: #{repo}"
        system "rsync -e ssh --exclude bis --include .repository.yml --times -O --no-whole-file -r --delete --stats --progress #{PATH}. #{repo}"
        puts
end
