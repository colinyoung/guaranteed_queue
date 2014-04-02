require 'logger'

require 'colorize'

module GuaranteedQueue
  class Logger < ::Logger

    def self.build *args
      unless log_to_file?
        return new($stdout).add_formatter!
      end

      FileUtils.mkdir_p File.dirname(log_path)
      new(log_path).add_formatter!
    end

    def add_formatter!
      self.formatter = proc do |severity, datetime, progname, msg|
        "#{severity}#{' ' if severity.length < 5} #{datetime.strftime("%Y-%m-%d %H:%M:%S")} #{self.class.prefix} #{msg}\n"
      end

      self
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

    def deleted text, message, exception
      switch_logdev 'deleted'
      info "! #{text}#{stringify(message)}\nException: #{exception}\n#{exception.backtrace[0...5].join("\n")}\n...etc\n"
      reset_logdev
    end

    def failed message, exception
      switch_logdev 'failed'
      info "! Failed: #{stringify(message)}\nException: #{exception}\n#{exception.backtrace[0...5].join("\n")}\n...etc\n"
      reset_logdev
    end

    def message_sent text
      info "> #{text}".cyan
    end

    def message_received msg
      info "< #{stringify msg}".green
    end

    private

    def switch_logdev suffix=nil
      return unless log_to_file?
      suffix = "." + suffix unless suffix.nil?
      @_original_logdev = @logdev
      @logdev = LogDevice.new(self.class.log_path.gsub('.log', "#{suffix}.log"), shift_age: 0, shift_size: 1048576)
    end

    def reset_logdev
      return unless log_to_file?
      @logdev = @_original_logdev
      @_original_logdev = nil
    end

    def stringify msg
      "#{msg.id[0...6]} (#{msg.body})"
    end

    def log_to_file?
      self.class.log_to_file?
    end

    class << self

      [:info, :info_with_message, :bright, :warn, :error, :success, :start, :stop, :message_sent, :message_received, :deleted, :failed].each do |method|
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

      def log_to_file?
        ENV['RACK_ENV'] != "development" && ENV['RAILS_ENV'] != "development" && !GuaranteedQueue.config[:stub_requests]
      end

    end

  end
end

