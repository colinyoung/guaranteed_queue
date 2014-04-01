require 'aws-sdk'

class AWS::SQS::ReceivedMessage

  @@old_delete = instance_method :delete

  # Disables deletes for running jobs, requires #delete! to be sent only
  def freeze!
    @frozen = true
    self.class.send :define_method, :delete do |*args|
      # pass
      GuaranteedQueue::Logger.warn "Frozen message will not be deleted"
    end
  end

  def unfreeze!
    @frozen = false
    self.class.send :define_method, :delete do |*args|
      delete!
    end
  end

  def delete!
    @@old_delete.bind(self).()
    @deleted = true
  end

  def frozen?
    @frozen
  end

  def deleted?
    @deleted
  end

end
