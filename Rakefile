require "rake/clean"
CLEAN.include ["rdoc", "*.gem"]

require "rdoc/task"
RDoc::Task.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.generator = 'hanna'
  rdoc.title = "hanna-nouveau #{version}"
  rdoc.options = ['--main', 'README.rdoc', '--title', 'Hanna-nouveau: RDoc generator designed with simplicity, beauty and ease of browsing in mind']
  rdoc.rdoc_files.add %w"README.rdoc LICENSE lib"
end
