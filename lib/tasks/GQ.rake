namespace :GQ do
  desc "builds and runs a job from component parts"
  task :build_and_run, [:class_name, :method, :id] do |t, args|
    raise "No Rails environment" unless defined? ::Rails
    klass       = args[:class_name].classify
    method      = args[:method]
    id          = args[:id]
    separator   = id.present? ? '#' : '.'
    GuaranteedQueue::Logger.info "#{klass}#{separator}#{method} invoked with #{id || 'no args'}..."
    ActiveRecord::Base.connection_pool.with_connection do
      if id
        klass.constantize.find(id).send(method)
      else
        klass.constantize.send(method)
      end
    end
  end
end
