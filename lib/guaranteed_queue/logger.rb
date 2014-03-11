require 'logger'

require 'colorize'

module GuaranteedQueue
  class Logger < ::Logger

    def self.build *args
      if ENV['RACK_ENV'] == "development" || ENV['RAILS_ENV'] == "development" || GuaranteedQueue.config[:stub_requests]
        return new($stdout)
      end

      FileUtils.mkdir_p File.dirname(log_path)
      new(log_path)
    end

    def info_with_message text, message=nil
      info "- #{text}#{' ' + stringify(message) if message}".white
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

    private

    def stringify msg
      "#{msg.id[0...6]} (#{msg.body})"
    end

    class << self

      [:info,:info_with_message, :bright, :warn, :error, :success, :start, :stop, :message_sent, :message_received].each do |method|
        define_method method do |*args|
          GuaranteedQueue.logger.__send__(method, *args)
        end
      end

      def log_path
        "#{Dir.pwd}/log/guaranteed_queue.log"
      end

      def prefix
        "[GuaranteedQueue]"
      end

    end

  end
end

