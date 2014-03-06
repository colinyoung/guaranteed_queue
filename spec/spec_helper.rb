require 'guaranteed_queue'

GuaranteedQueue.config(stub_requests: true)

path = File.dirname(__FILE__) + '/lib/tasks/*.rake'
Dir.glob(path).each { |r| load r }
