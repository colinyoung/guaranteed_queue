require 'colorize'

module GuaranteedQueue

  class Logger

    class << self

      def info text, message=nil
        puts "- #{prefix} --- #{text}#{' ' + stringify(message) if message}".white
      end

      def bright text, message=nil
        puts "* #{prefix} --- #{text}".magenta
      end

      def warn text, message=nil
        puts "! #{prefix} --- #{text}#{' ' + stringify(message) if message}".yellow
      end

      def error text, message=nil
        puts "! #{prefix} --- #{text}#{' ' + stringify(message) if message}".red
      end

      def success text, message=nil
        puts "! #{prefix} --- #{text}#{' ' + stringify(message) if message}".green
      end

      def start text, message=nil
        puts "^ #{prefix} --- #{text}#{' ' + stringify(message) if message}".colorize(:green).on_white
      end

      def stop text, message=nil
        puts "$ #{prefix} --- #{text}#{' ' + stringify(message) if message}".colorize(:red).on_white
      end

      def message_sent text
        puts "> #{prefix} --- #{text}".cyan
      end

      def message_received msg
        puts "< #{prefix} --- #{stringify msg}".green
      end

      private

      def prefix
        "[GuaranteedQueue] #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}"
      end

      def stringify msg
        "#{msg.id[0...6]} (#{msg.body})"
      end

    end

  end

end
