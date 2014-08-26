require 'aws-sdk'
require 'rake'
require 'celluloid'

basedir = File.dirname(__FILE__).split('/')
basedir.pop
$LOAD_PATH << basedir.join('/') + '/spec/lib'

require "guaranteed_queue/logger"

module GuaranteedQueue

  def self.config opts={}
    @config ||= opts
    @config.merge! opts if opts
    logger(true) unless opts.empty?
    @config
  end

  def self.logger reload=false
    if !@logger or reload
      @logger = GuaranteedQueue::Logger.build
    end

    @logger
  end
end

require "guaranteed_queue/version"
require "guaranteed_queue/configure"
require "guaranteed_queue/delay"
require "guaranteed_queue/poller"
require "guaranteed_queue/manager"
load "tasks/GQ.rake"
