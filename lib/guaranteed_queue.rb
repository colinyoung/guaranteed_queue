require 'aws-sdk'
require 'rake'
require "guaranteed_queue/logger"

basedir = File.dirname(__FILE__).split('/')
basedir.pop
$LOAD_PATH << basedir.join('/') + '/spec/lib'

module GuaranteedQueue

  def self.config opts={}
    @config ||= opts
    @config.merge! opts if opts
    @config
  end

end

require "guaranteed_queue/version"
require "guaranteed_queue/configure"
require "guaranteed_queue/delay"
require "guaranteed_queue/manager"
load "tasks/GQ.rake"