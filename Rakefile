
require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList[%w(test/**/*_test.rb test/**/*_spec.rb)]
  # t.pattern = ["test/test_*.rb", "test/**/test_*.rb"]
  t.verbose = true
end
