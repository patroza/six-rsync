# 
# To change this template, choose Tools | Templates
# and open the template in the editor.
 

require 'rubygems'
require 'rake'
require 'rake/clean'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'rake/testtask'

spec = Gem::Specification.new do |s|
  s.name = 'six-rsync'
  s.version = '0.7.1'
  s.has_rdoc = true
  s.extra_rdoc_files = ['README', 'LICENSE']
  s.summary = 'Your summary here'
  s.description = s.summary
  s.author = 'Sickboy'
  s.email = 'sb@dev-heaven.net'
  #s.add_dependency('faster_require', '>= 0.5.2')
  s.add_dependency('log4r', '>= 1.1.2')
  s.files = %w(LICENSE README Rakefile) + Dir.glob("{bin,spec}/**/*") + Dir.glob("lib/*/**/*.rb")
  s.require_path = "lib"
  s.bindir = "bin"
  s.executables = ['six-rsync', 'six-rsync-mirror']
end

Rake::GemPackageTask.new(spec) do |p|
  p.gem_spec = spec
  p.need_tar = true
  p.need_zip = true
end

Rake::RDocTask.new do |rdoc|
  files =['README', 'LICENSE', "lib/*/**/*.rb"]
  rdoc.rdoc_files.add(files)
  rdoc.main = "README" # page to start on
  rdoc.title = "six-updater-gui Docs"
  rdoc.rdoc_dir = 'doc/rdoc' # rdoc output folder
  rdoc.options << '--line-numbers'
end

Rake::TestTask.new do |t|
  t.test_files = FileList['test/**/*.rb']
end
