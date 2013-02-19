# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'model_filter/version'

Gem::Specification.new do |gem|
  gem.name          = "model_filter"
  gem.version       = ModelFilter::VERSION
  gem.authors       = ["Aliaksandr Ausiankin"]
  gem.email         = ["alex.ausiankin@gmail.com"]
  gem.description   = %q{provides simple model filtering (with Arel)}
  gem.summary       = %q{model filtering plugin}
  gem.homepage      = ""

  # gem.files         = `git ls-files`.split($/)
  gem.files         = Dir["{app,config,db,lib}/**/*"] + ['MIT-LICENSE', 'Rakefile', 'README.rdoc']
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
  gem.add_dependency "arel"
end
