# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'guaranteed_queue/version'

Gem::Specification.new do |spec|
  spec.name          = "guaranteed_queue"
  spec.version       = GuaranteedQueue::VERSION
  spec.authors       = ["Colin Young"]
  spec.email         = ["me@colinyoung.com"]
  spec.summary       = %q{An SQS-based queue with one goal: process jobs - guaranteed}
  spec.description   = %q{Jobs are sent to SQS, which is long-polled. Jobs run, and any errors are recorded.}
  spec.homepage      = "http://www.colinyoung.com"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "activerecord"
  spec.add_dependency "aws-sdk"
  spec.add_dependency "colorize"
end
