module GuaranteedQueue
  class Manager
    module Stubs

      def stub!
        resp = @sqs.client.stub_for(:list_queues)
        resp.data[:queue_urls] = ["https://sqs.us-east-1.amazonaws.com/12345678/StubbedQueue_Test",
                                  "https://sqs.us-east-1.amazonaws.com/12345678/StubbedQueue_Test_DeadLetter"]
      end

      def stub_periodically_send_messages!
        # Send a random receive message every 10 seconds or so
        Thread.new do
          sleep 2
          stub_send_message!
        end
      end

      def stub_send_message! body=nil
        body ||= "test_message:#{Random.rand(9)}"
        resp = @sqs.client.stub_for(:send_message)
        resp.data = msg = {
          message_id: unique_id(body),
          md5_of_message_body: md5(body)
        }

        send_message body, delay_seconds: 1

        # Receive this message
        stub_receive_messages [ msg.merge(body: body) ]

        Thread.new do
          sleep Random.rand(6) + 4 # between 2-6 seconds
          stub_send_message!
        end

        msg
      end

      def stub_receive_messages messages
        messages = messages + queued
        resp = @sqs.client.stub_for(:receive_message)
        resp.data[:messages] = messages.collect do |msg|
          msg.merge md5_of_body: msg[:md5_of_body] || msg.delete(:md5_of_message_body), receipt_handle: unique_id
        end
      end

      def reset_receive!
        resp = @sqs.client.stub_for(:receive_message)
        resp.data[:messages] = []
      end

    end
  end
end
