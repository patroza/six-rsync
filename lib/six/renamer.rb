require 'fileutils'
module Six
	module Renamer
		module_function
		def rename(entry, new = nil)
			tmp = "#{entry}tmp"
			new = File.join(File.dirname(entry), File.basename(entry).downcase) if new.nil?
			FileUtils.mv(entry, tmp)
			FileUtils.mv(tmp, new)
		end
		
		def handle_downcase(entry)
			# First handle all entries in directory
			if File.directory?(entry)
				Dir[File.join(entry, "*")].each do |e|
					handle_downcase(e)
				end
			end
		
			# Rename the current item last
			rename(entry)
		end
		
		def handle_downcase_f(entry)
			Dir[File.join(entry, "*")].each do |e|
				handle_downcase(e)
			end	
		end
	end
end		
