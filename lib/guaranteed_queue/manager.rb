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
        if queue_name = ENV['GUARANTEED_QUEUE_NAME']
          q.url[/#{queue_name}$/]
        elsif host and ['edge', 'staging', 'production'].include?(host)
          q.url[/#{host}$/]
        else
          q.url.downcase.include? Rails.env.to_s or q.url[/deadletter$/i]
        end
      end
    end
    private :get_queues

    # Receive messages once, on demand
    def poll queue=main_queue
      msg = queue.receive_message
      handle msg, queue if msg
    end

    # Continuously receive messages
    def poll! options={}
      unless options[:restart]

        Logger.info "Started polling #{main_queue.url}"
        Logger.info "Started polling retries from #{dead_letter_queue.url}" if dead_letter_queue

        # Set the status timer
        every_few_seconds :status

        # Poll deadletter queue also
        if dead_letter_queue
          Thread.new do
            begin
              Logger.info "Will poll from DeadLetter queue every #{config[:dead_letter_poll_interval_seconds]} seconds."
              while true do
                Logger.info "Polling DeadLetter queue."
                poll dead_letter_queue
                sleep config[:dead_letter_poll_interval_seconds]
              end
            rescue Exception
              Logger.error $!
              raise e
            end
          end
        end
      end

      # poll main queue indefinitely
      begin
        main_queue.poll do |message|
          handle message
        end
      rescue SignalException => e
        raise e
      rescue Exception => e
        Logger.error $!
        poll!(restart: true)
      end
    end

    def handle msg, queue=main_queue
      Logger.message_received msg
      receive msg, queue
    end

    def status
      Logger.bright "#{@threads.compact.count {|t| t.alive? }} threads alive. #{@completed} completed, #{@accepted} accepted, #{@queued.count} queued, #{@failed} failed"
      prune_threads!
    end

    def method_missing *args
      name = args.shift
      main_queue.send name, *args
    end

    def send_message message, opts={}
      Logger.message_sent message
      main_queue.send_message message, opts
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

      @threads[next_thread_index] = Thread.new do
        begin
          Logger.start "Performing job for", message
          @running << message.id

          # Perform task
          if internal_action? message
            internal_action! message
          else
            task_name = message.body.split('[').first
            begin
              Rake.application.invoke_task message.body
            rescue RuntimeError
              if $!.to_s == "Don't know how to build task '#{task_name}'"
                args = message.body.gsub(/[\[\]:]/, ',').gsub(/,$/, '')
                Rake.application.invoke_task "GQ:build_and_run[#{args}]"
              else
                raise "No match for task #{task_name}"
              end
            ensure
              Rake::Task['GQ:build_and_run'].reenable # required
              Rake::Task[task_name].reenable rescue nil # also required
              Logger.info "Re-enabled #{task_name}"
            end
          end

          complete message
        rescue Exception => exception
          @failed += 1
          @running.delete message.id
          Logger.error $!, message

          if @whitelisted_exceptions.include? exception.class.name or @whitelisted_exceptions.include? exception.class
            message.unfreeze!
            message.delete!
            Logger.deleted "Deleted message due to unrecoverable exception #{exception.class.name}: ", message, exception
          end

          Thread.new { prune_threads! } # after this thread dies, prune it
          raise exception # fail the message
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

    def every_few_seconds method, timeout=10
      Thread.new do
        while true do
          send(method)
          sleep timeout
        end
      end
    end

    def prune_threads!
      @threads.delete_if {|t| !t.alive? }
    end

  end
end
