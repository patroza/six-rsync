# encoding: UTF-8

# Docu: http://www.ruby-doc.org/stdlib/libdoc/optparse/rdoc/classes/OptionParser.html
require 'optparse'

module Six
  module Repositories
    module Rsync
      @@host = ''
      module_function
      def parse_options
        todo = [] #, general_todo, second_todo = [], [], []

        options = Hash.new
        OptionParser.new do |opts|
          $0[/.*\/(.*)/]
          opts.banner = "Usage: #{$1} [folder] [options]"

          opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
            options[:verbose] = v
          end

          opts.on("-i", "--init", "Initializes Repository") do |bool|
            todo << :init if bool
          end

          opts.on("-s", "--status", "Status of Repository") do |bool|
            todo << :status if bool
          end

          opts.on("-u", "--update", "Updates Repository") do |bool|
            todo << :update if bool
          end

          opts.on("-c", "--commit", "Commits changes to Repository") do |bool|
            todo << :commit if bool
          end

          opts.on("-n", "--convert", "Converts into repository") do |bool|
            todo << :convert if bool
          end

          opts.on("--clone S", String, "Clones a Repository") do |s|
            todo << :clone
            @@host = s
          end

          opts.on("-l", "--log", "Write logfile") do |bool|
            options[:logging] = bool if bool
          end
        end.parse!

        [options, todo]
      end

    end
  end
end

