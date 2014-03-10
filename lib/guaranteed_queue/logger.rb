require 'logger'

require 'colorize'

module GuaranteedQueue
  class Logger < ::Logger

    def initialize *args
      super *args unless args.empty?

      filedev = self.class.log_path
      super(filedev)
    end

    def bright text, message=nil
      info "* #{text}".magenta
    end

    def warn text, message=nil
      super "! #{text}#{' ' + stringify(message) if message}".yellow
    end

    def error text, message=nil
      super "! #{text}#{' ' + stringify(message) if message}".red
    end

    def success text, message=nil
      info "! #{text}#{' ' + stringify(message) if message}".green
    end

    def start text, message=nil
      info "^ #{text}#{' ' + stringify(message) if message}".colorize(:green).on_white
    end

    def stop text, message=nil
      info "$ #{text}#{' ' + stringify(message) if message}".colorize(:red).on_white
    end

    def message_sent text
      info "> #{text}".cyan
    end

    def message_received msg
      info "< #{stringify msg}".green
    end

    class << self

      [:info, :bright, :warn, :error, :success, :start, :stop, :message_sent, :message_received].each do |method|
        define_method method do |*args|
          $GQ_LOG.send(method, *args)
        end
      end

      def log_path
        "#{Dir.pwd}/log/guaranteed_queue.log"
      end

      def prefix
        "[GuaranteedQueue]"
      end

      def stringify msg
        "#{msg.id[0...6]} (#{msg.body})"
      end

    end

  end
end

$GQ_LOG = GuaranteedQueue::Logger.new.tap do |logger|
  logger.formatter = proc do |severity, datetime, progname, msg|
    "#{severity} #{datetime.strftime("%Y-%m-%d %H:%M:%S")} #{logger.class.prefix} #{msg}\n"
  end
end
