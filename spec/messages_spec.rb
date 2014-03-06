require 'spec_helper'

describe GuaranteedQueue::Manager do

  subject do
    GuaranteedQueue::Manager.new
  end

  let(:main_queue) { subject.main_queue }
  let(:dead_letter_queue) { subject.dead_letter_queue }

  before do
    subject.reset_receive!
    subject.poll.should be_nil
  end

  it 'should initialize an SQS queue' do
    subject.main_queue.should_not be_nil
    subject.dead_letter_queue.should_not be_nil
  end

  it 'should receive a test message that it sends itself' do
    msg = subject.send :stub_send_message!
    subject.receive_message.id.should == msg[:message_id]
  end

  it 'should handle a test message that it sends itself' do
    FileIncrement.prepare!

    msg = subject.send :stub_send_message!, "file:increment_by[1]"

    received = subject.receive_message
    expect { subject.handle received }.to change{ subject.accepted }.by 1

    sleep 1

    subject.completed.should == 1

    subject.receive_message.should be_nil # no more messages in queue
  end

  it 'should reject a failed message' do
    msg = subject.send :stub_send_message!, "non_existent_task"

    received = subject.receive_message
    expect { subject.handle received }.to change{ subject.accepted }.by 1

    sleep 1

    subject.failed.should == 1

    subject.receive_message.id.should == received.id # message should still be in queue
  end

  it 'should move a failed message to dead-letter after enough rejections' do

    msg = subject.send :stub_send_message!, "non_existent_task"

    # reject count is 2
    2.times do
      msg = subject.poll main_queue
      sleep 2 # wait for job to be accepted and run
      subject.should_not be_busy
    end

    # jobs all fail immediately
    subject.failed.should == 2
    subject.accepted.should == 2
    subject.instance_variable_get(:@threads).should be_empty

    # since AWS would handle this for us, stub the receive methods in between
    main_queue.stub(:receive_message).and_return nil
    dead_letter_queue.stub(:receive_message).and_return msg

    expect { subject.poll main_queue }.to change { subject.accepted }.by 0
    expect { subject.poll dead_letter_queue }.to change { subject.accepted }.by 1
  end

  it 'should freeze a message that waits' do
    msg = subject.send :stub_send_message!, "$wait=5"
    msg = subject.poll main_queue

    sleep 1

    msg.should be_frozen
  end

end
