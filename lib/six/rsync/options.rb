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

          opts.on("-u", "--update", "Updates Repository") do |bool|
            todo << :update if bool
          end

          opts.on("-c", "--commit", "Commits changes to Repository") do |bool|
            todo << :commit if bool
          end

          opts.on("--clone S", String, "Clones a Repository") do |s|
            todo << :clone
            @@host = s
          end

=begin
        opts.on("--depth I", Integer, "Clone depth, default: #{@config[:depth]}. Set to 0 to clone all history") do |s|
          options[:depth] = s
        end

        opts.on("--mods S", String, "Additional Mods") do |s|
          options[:mods] = s
        end
=end
        end.parse!
        @@options = todo
=begin
      default = if (todo + second_todo + general_todo).size > 0
        false
      else
        true
      end

      # TODO: Move this to Updater ?
      @todo = if todo.size > 0
        todo
      else
        log.info "No parameters given, running the default"
        #options[:wait] = true
        if default
          @config[:defaultactions]
        else
          []
        end
      end
      @general_todo = if general_todo.size > 0
        general_todo
      else
        if default
          @config[:defaultgeneralactions]
        else
          []
        end
      end

      @second_todo = if second_todo.size > 0
        second_todo
      else
        if default
          @config[:defaultsecondactions]
        else
          []
        end
      end
      @config = @config.merge(options)
=end
      end

    end
  end
end

