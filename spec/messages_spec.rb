require 'spec_helper'

class WhitelistedException < Exception; end
class NotWhitelistedException < Exception; end

describe GuaranteedQueue::Manager do

  subject do
    GuaranteedQueue::Manager.new
  end

  let(:main_queue) { subject.main_queue }
  let(:dead_letter_queue) { subject.dead_letter_queue }
  let(:original_whitelist) { subject.config[:whitelisted_exceptions] }

  before do
    subject.reset_receive!
    expect(subject.poll).to be_nil
    subject.whitelisted_exceptions = original_whitelist
  end

  it 'should initialize an SQS queue' do
    expect(subject.main_queue).not_to be_nil
    expect(subject.dead_letter_queue).not_to be_nil
  end

  it 'should receive a test message that it sends itself' do
    msg = subject.send :stub_send_message!
    expect(subject.receive_message.id).to eq(msg[:message_id])
  end

  it 'should handle a test message that it sends itself' do
    FileIncrement.prepare!

    msg = subject.send :stub_send_message!, "file:increment_by[1]"

    received = subject.receive_message
    expect { subject.handle received }.to change{ subject.accepted }.by 1

    sleep 1

    expect(subject.completed).to eq(1)

    expect(subject.receive_message).to be_nil # no more messages in queue
  end

  it 'should reject a failed message' do
    msg = subject.send :stub_send_message!, "non_existent_task"

    received = subject.receive_message
    expect { subject.handle received }.to change{ subject.accepted }.by 1

    sleep 1

    expect(subject.failed).to eq(1)

    expect(subject.receive_message.id).to eq(received.id) # message should still be in queue
  end

  it 'should move a failed message to dead-letter after enough rejections' do

    msg = subject.send :stub_send_message!, "non_existent_task"

    # reject count is 2
    2.times do
      msg = subject.poll main_queue
      sleep 2 # wait for job to be accepted and run
      expect(subject).not_to be_busy
    end

    # jobs all fail immediately
    expect(subject.failed).to eq(2)
    expect(subject.accepted).to eq(2)
    expect(subject.instance_variable_get(:@threads)).to be_empty

    # since AWS would handle this for us, stub the receive methods in between
    allow(main_queue).to receive(:receive_message).and_return nil
    allow(dead_letter_queue).to receive(:receive_message) do |&block|
      block.call(msg)
    end

    expect { subject.poll main_queue }.to change { subject.accepted }.by 0
    expect { subject.poll dead_letter_queue }.to change { subject.accepted }.by 1
  end

  it 'should freeze a message that waits' do
    msg = subject.send :stub_send_message!, "$wait=5"
    msg = subject.poll main_queue

    sleep 1

    expect(msg).to be_frozen
  end

  it 'should delete a message that throws a whitelisted exception' do
    subject.whitelisted_exceptions << 'WhitelistedException' unless subject.whitelisted_exceptions.include? 'WhitelistedException'
    msg = subject.send :stub_send_message!, "$exception=WhitelistedException"
    msg = subject.poll main_queue

    sleep 1

    expect(msg).not_to be_frozen
    expect(msg).to be_deleted
  end

  it 'should delete a message that throws a RecordNotFound by default' do
    require 'active_record'
    require 'active_record/errors'
    msg = subject.send :stub_send_message!, "$exception=ActiveRecord::RecordNotFound"
    msg = subject.poll main_queue

    sleep 1

    expect(msg).not_to be_frozen
    expect(msg).to be_deleted
  end

  it 'should not delete a message that throws a whitelisted exception' do
    msg = subject.send :stub_send_message!, "$exception=NotWhitelistedException"
    msg = subject.poll main_queue

    sleep 1

    expect(msg).to be_frozen
    expect(msg).not_to be_deleted
  end

end
