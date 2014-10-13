module GuaranteedQueue

  module Delay
    
    # The main method called to delay a method call.
    # In your class, use:
    #    
    #    delay :resize
    #
    # By default in a model called Image (if no args are passed)
    # the resulting rake task will look like:
    #
    #    Rake.application.invoke_task "image:resize[1]"
    # 
    # where 'image' is the lowercase class name, resize is the method,
    # and 1 is the ID of the instance.
    # 
    # In the above example, both image and the ID are determined automatically.
    def delay task_name, options={}
      namespace = options.delete(:namespace) || self.class.name
      body = "#{namespace.underscore.downcase}:#{task_name}[#{id}]".gsub(/^:/,'')
      if GuaranteedQueue.config[:stub_requests]
        begin
          # Ensure private methods are called.
          self.method(task_name).()
        rescue NoMethodError => e
          if e.message.include?("undefined method `#{task_name}'")
            raise "Not sure how to queue task '#{body}' because there is no method #{self.class}##{task_name}: #{$!}"
          else
            raise e
          end
        end
      else
        GuaranteedQueue::Manager.new(options).send_message body
      end
    end

  end

end
