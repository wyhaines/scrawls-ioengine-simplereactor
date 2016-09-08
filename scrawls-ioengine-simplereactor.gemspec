# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'scrawls/ioengine/simplereactor/version'

Gem::Specification.new do |spec|
  spec.name          = "scrawls-ioengine-simplereactor"
  spec.version       = Scrawls::Ioengine::Simplereactor::VERSION
  spec.authors       = ["Kirk Haines"]
  spec.email         = ["wyhaines@gmail.com"]

  spec.summary       = %q{An event based IO engine for Scrawls that uses the pure ruby reactor, SimpleReactor.}
  spec.description   = %q{This os a bare bones event based reactor engine for Scrawls.}
  spec.homepage      = "http://github.com/wyhaines/scrawls-ioengine-simplereactor"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.12"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_runtime_dependency "scrawls-ioengine-single", ">= 0.1"
end
