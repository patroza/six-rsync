$stdout.sync = true
system "#{ARGV.join(" ")} 2>&1"
puts "SIX-SHEBANG: #{$?.pid}, #{$?.exitstatus}"
