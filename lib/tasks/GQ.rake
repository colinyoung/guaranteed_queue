namespace :GQ do
  desc "builds and runs a job from component parts"
  task :build_and_run, [:klass, :method, :id] do |t, args|
    raise "No Rails environment" unless defined? ::Rails
    klass     = args[:klass]
    method    = args[:method]
    id        = args[:id]
    GuaranteedQueue::Logger.info "#{klass}##{method} invoked with #{id}..."
    klass.classify.constantize.find(id).send(method)
  end
end
