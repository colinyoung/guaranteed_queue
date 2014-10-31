require 'extensions/aws/sqs/received_message'

module GuaranteedQueue
  
  class Manager

    class BusyWorkersException < Exception; end

    class << self
      def run! options={}
        Logger.info "Started"
        self.new(options).poll!
      end
    end

    attr_reader :sqs, :queued, :accepted, :completed, :failed
    attr_accessor :whitelisted_exceptions

    def initialize options={}
      @options = options
      @threads = []
      @queued = []
      @running = []
      @whitelisted_exceptions = config[:whitelisted_exceptions] || []
      @accepted = 0
      @completed = 0
      @failed = 0

      AWS::SQS.new(config).tap do |sqs|
        @sqs = sqs

        if config[:stub_requests]
          require 'guaranteed_queue/manager/stubs'
          self.class.send :include, Stubs
          stub!
        end
      end
    end

    def config
      GuaranteedQueue.config
    end

    def main_queue
      @queues ||= get_queues
      queues = @queues.find {|q| !q.url[/deadletter$/i] }
    end

    def dead_letter_queue
      @queues ||= get_queues
      @queues.find {|q| q.url[/deadletter$/i] }
    end

    def get_queues
      queues = sqs.queues.to_a
      host = %x{hostname}.split('.').first rescue nil
      return queues unless defined? ::Rails
      queues.select do |q|
        if queue_name = (@options[:queue_name] || config[:queue_name] || ENV['GUARANTEED_QUEUE_NAME'])
          q.url[/#{queue_name}$/]
        elsif queue_env = config[:queue_env]
          q.url.downcase.include? queue_env
        elsif host and ['edge', 'staging', 'production'].include?(host)
          q.url[/#{host}$/]
        else
          q.url.downcase.include? Rails.env.to_s
        end
      end
    end
    private :get_queues

    # Receive messages once, on demand
    def poll queue=main_queue
      limit = max_limit - busy

      # 100% utilization of threads
      if limit == 0
        return Logger.warn "Waiting for another loop - 100% utilization of workers"
      end

      # Wait over 50% utilization
      if threshold = GuaranteedQueue.config[:utilization_threshold]
        if (busy.to_f / max_limit) > threshold
          return Logger.warn "Waiting for another loop - past utilization threshold of #{threshold}."
        end
      end

      begin
        Logger.info "Receiving up to #{limit} messages on #{queue_name(queue)} (#{busy}/#{limit} threads are busy)"
        queue.receive_message(:limit => limit) do |message|
          handle message
        end
      rescue SignalException => e
        raise e
      rescue Exception => e
        Logger.error $!
        poll!(restart: true)
      end
    end

    # Receive messages
    def poll!
      @poller = Poller.new(manager: self).tap {|p| p.async.run(main_queue) }
      Signal.trap("HUP") do
        # gracefully shutdown
        shutdown!
      end
      sleep
    end

    def shutdown!
      if busy == 0
        Logger.info 'Shutting down due to SIGHUP'
        exit!
      else
        Logger.warn 'Cannot shutdown, running jobs'
      end
    end

    def handle msg, queue=main_queue
      Logger.message_received msg
      receive msg, queue
    end

    def status
      Logger.bright "#{busy}/#{max_limit} threads alive. #{@completed} completed, #{@accepted} accepted, #{@queued.count} queued, #{@failed} failed"
      prune_threads!
    end

    def method_missing *args
      name = args.shift
      main_queue.send name, *args
    end

    def send_message message, opts={}
      receipt = main_queue.send_message message, opts
      Logger.message_sent "#{message} (#{queue_name(main_queue)})"
      Logger.info receipt.inspect
    end

    def receive message, queue=main_queue
      # do something with the message here

      if @running.include? message.id
        Logger.warn "Message is already running, you may want to increase :running_visibility_timeout", message
        reject message, queue
      elsif busy?
        reject message, queue
      else
        accept message, queue
      end

      message
    end

    def accept message, queue=main_queue
      Logger.info_with_message "Accepted on thread #{next_thread_index} from #{queue == main_queue ? 'main queue' : 'DL queue'}", message
      @accepted += 1

      message.freeze! # ensure message cannot be deleted during processing

      i = next_thread_index

      @threads[next_thread_index] = Thread.new do
        begin
          Logger.start "Performing job for", message
          @running << message.id

          # Perform task
          if internal_action? message
            internal_action! message
          else
            parts = message.body.match(/^(.+)\[(.+)\]|(.+)/)
            task_name = parts[1]
            task_args = parts[2] || ''
            task_name ||= parts[3] # no args given for this task

            begin
              task = task_name
              task += "[#{task_args.gsub(/"/,'')}]" if !task_args.nil? && task_args.length > 0

              if defined? ActiveRecord
                ActiveRecord::Base.connection_pool.with_connection do
                  Rake.application.invoke_task(task)
                end
              else
                Rake.application.invoke_task(task)
              end
            rescue RuntimeError
              if $!.to_s == "Don't know how to build task '#{task_name}'"
                args = message.body.gsub(/\b([\[\]:])\b{1}/, ',').gsub(/[,\]]$/, '')
                begin
                  Rake.application.invoke_task "GQ:build_and_run[#{args}]"
                rescue Exception => exception
                  # exit thread
                  fail! message, exception
                end
              else
                raise "#{task_name}: #{$!}"
              end
            ensure
              Rake::Task['GQ:build_and_run'].reenable # required
              Rake::Task[task_name].reenable rescue nil # also required
              Logger.info "Re-enabled #{task_name}"
            end
          end

          complete message unless failed?(message)
        rescue Exception => exception
          fail! message, exception
          raise exception # fail the message
        ensure
          Thread.new { prune_threads! } # after this thread dies, prune it
        end
      end
    end

    def reject message, queue=main_queue
      if queue == dead_letter_queue
        ct = message.approximate_receive_count
        max = config[:message_failures_allowed]
        expired = ct > max if ct

        if max < 1
          Logger.info_with_message "Expiration is disabled, message will be retried forever", message
        elsif ct != nil
          # Dead letter rejects must expire (really) old jobs
          Logger.warn "DeadLetter message received ~#{ct} times - " +
                      expired ? "expired permanently" :
                      "keeping until #{max} failures reached", message
          # delete message if expired
        end
      else
        Logger.info_with_message "All workers busy. Message will be retried after visibility timeout", message
        raise BusyWorkersException
      end

      prune_threads!
    end

    def complete message
      @completed += 1
      @accepted -= 1
      @queued.delete_if {|msg| msg[:message_id] == message.id }

      delete message

      Logger.stop "Job finished", message

      prune_threads!
    end

    def delete message
      message.delete!
      Logger.success "Deleting and completing ", message
      reset_receive! if config[:stub_requests]
    end

    def fail! message, exception
      @failed += 1
      @running.delete message.id
      Logger.error $!, message
      Logger.failed message, exception

      if @whitelisted_exceptions.include? exception.class.name or @whitelisted_exceptions.include? exception.class
        message.unfreeze!
        message.delete!
        Logger.deleted "Deleted message due to unrecoverable exception #{exception.class.name}: ", message, exception
      end
    end

    def failed? message
      !@running.include?(message.id)
    end

    def busy?
      return false if @threads.empty?
      if @threads.count < GuaranteedQueue.config[:max_threads]
        false
      else
        @threads.all? {|t| t.alive? }
      end
    end

    def queued? message
      @queued.any? {|q| q[:message_id] == message.id }
    end

    private

    def internal_action? message
      message.body.match /^\$/ # starts with a $
    end

    def internal_action! message
      cmd, arg = message.body.split('=')
      case cmd
      when '$wait'
        sleep Integer(arg)
      when '$fail'
        raise "Failed job"
      when '$exception'
        raise Kernel.const_get(arg)
      end
    end

    def next_thread_index
      return 0 if @threads.empty?

      GuaranteedQueue.config[:max_threads].times do |i|
        return i unless @threads[i] and @threads[i].status
      end
    end

    def unique_id prefix=''
      OpenSSL::Digest::SHA1.new(prefix.to_s + Time.now.to_s).to_s
    end

    def md5 str
      OpenSSL::Digest::MD5.new(str).to_s
    end

    def hashify message
      case message
      when AWS::SQS::ReceivedMessage
        {
          message_id: message.id,
          body: message.body,
          md5_of_body: message.md5,
          receipt_handle: message.handle
        }
      end
    end

    def prune_threads!
      @threads.delete_if {|t| !t.alive? }
    end

    def poll_options
      { :batch_size => [10, GuaranteedQueue.config[:max_threads]].min }
    end

    def receive_options
      { :limit => poll_options[:batch_size] }
    end

    def busy
      @threads.compact.count {|t| t.alive? }
    end
    alias :alive :busy

    def max_limit
      receive_options[:limit]
    end

    def queue_name queue
      queue.url.split('/').last
    end
  end
end
