# encoding: utf-8
# Format: user@host_or_ip:/path/to/rsync/store
# Use with public/private key combo
ARGV.each do |repo|
        puts
        puts "Processing: #{repo}"
        system "rsync -e ssh --exclude bis --include .repository.yml --include .version --include .sums.yml --times -O --no-whole-file -r --delete --stats --progress /var/scm/rsync/. #{repo}"
        puts
end
