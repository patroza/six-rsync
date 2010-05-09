$stdout.sync = true
system ARGV.join(" ") # redirect 2>&1   ?
puts "SIX-SHEBANG: #{$?.pid}, #{$?.exitstatus}"
