# configure.rb
GuaranteedQueue.config(
  max_threads: 8,
  access_key_id: ENV['AWS_ACCESS_KEY_ID'] || 'test',
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'] || 'test',
  region: ENV['AWS_REGION'] || 'us-east-1',
  dead_letter_poll_interval_seconds: 30,
  message_failures_allowed: 0,
  stub_requests: ENV['RACK_ENV'] == 'test' || ENV['RAILS_ENV'] == 'test' || ENV['RAILS_ENV'] == 'development',
  whitelisted_exceptions: [ 'ActiveRecord::RecordNotFound' ]
)
