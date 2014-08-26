module GuaranteedQueue
  
  class Poller
    include Celluloid

    def initialize(manager:)
      @manager = manager
      @interval = GuaranteedQueue.config[:poll_interval_seconds] || 2
    end

    def run(queue)
      @manager.poll(queue)

      GQ::Logger.info "Polled #{queue.url}, waiting #{@interval}s..."

      after( @interval ) do
        run(queue)
      end
    end
  end
end
