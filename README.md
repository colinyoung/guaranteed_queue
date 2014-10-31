# GuaranteedQueue

An Amazon SQS (<b>S</b>imple <b>Q</b>ueue <b>S</b>ervice) backed rake task queue with one goal: RUN ALL THE JOBS.

It's super basic in design. It runs jobs in threads, with a focus on getting all your jobs processed.

### Important!

GQ requires you to use Dead-Letter SQS queues, [which you can read about here](http://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/SQSDeadLetterQueue.html).

Use two queues with the following format and settings. Note that you create the dead-letter queue first.

| Queue 1 ||
| ----------| ------------- |
| Name | MyQueue_DeadLetter |
| Receive Message Wait Time | 20 |
| Delivery Delay | 2 minutes* |

*This allow failed jobs to retry at a reasonable interval

| Queue 2 ||
| ---------|-------------- |
| Name | MyQueue |
| Receive Message Wait Time | 20 |
| Delivery Delay | 0 |
| Use Redrive Policy | Yes |
| Dead Letter Queue | MyQueue_DeadLetter |

Once these are done, read in Usage below to how to name your queues.

## Installation

First, set up two queues in SQS:

Add this line to your application's Gemfile:

    gem 'guaranteed_queue'

And then execute:

    $ bundle

## Usage

Run (and hopefully monitor with something like monit) the guaranteed_queue executable:

    $ ./bin/guaranteed_queue {sqs_queue_name}

in your application directory.

For example, if your main SQS queue is named `ProdQueue`, your dead-letter queue
must be named `ProdQueue_DeadLetter`, so you can start the executable with:

    $ export AWS_ACCESS_KEY_ID="your id"
    $ export AWS_SECRET_ACCESS_KEY="your secret"
    $ ./bin/guaranteed_queue ProdQueue

If you only have two queues that your AWS user can see (one called `ProdQueue` and one called `ProdQueue_DeadLetter`), you don't need to specify a name.

## Management

    $ bundle exec guaranteed_queue start
    $ bundle exec guaranteed_queue stop # will only stop if jobs are not running

## Rails Integration

To queue a rake task in SQS, do the following (this is using a Rails model as a demo):

    # post.rb
    class Post < ActiveRecord::Base
      include GuaranteedQueue::Delay

      after_destroy :delete_s3_images

      def delete_s3_images
        delay :clean_s3_bucket
      end
    end

This means that every time the `Post#delete_s3_images` method is called, the following message will be sent to the SQS queue:

    post:clean_s3_bucket[1] # 1 is the sample ID of the relevant Post.

Note that tasks are namespaced by default. If you prefer not to namespace your tasks, you can exclude or change it manually in `delay`:

    delay :clean_s3_bucket, nil # exclude namespace
    delay :clean_s3_bucket, "buckets" # change namespace to "buckets", final task would be "buckets:clean_s3_bucket"

If you prefer not to define rake tasks for simplicity, instead simply define a method on your models like so:

    def my_task
      # acts on model here
    end

And then call delay as usual:

    # post.rb
    class Post < ActiveRecord::Base
      include GuaranteedQueue::Delay

      after_destroy :delete_s3_images

      def delete_s3_images
        delay :clean_s3_bucket
      end

      private

      def clean_s3_bucket
        # Will be called by GQ.
        puts self.inspect # => <Post id="1" name="my post">
      end
    end

## Integrating with Rails

If you are running GuaranteedQueue as a queue for a Rails app, then your chosen queue will need to be named for the environment:

    development:
      main_queue: RailsApp_development
      deadletter_queue: RailsApp_development_deadletter

    production:
      main_queue: RailsApp_production
      deadletter_queue: RailsApp_production_deadletter

## Whitelisted Exceptions

Sometimes, you will have errors which occur that are unrecoverable. In this instance, you don't want to have those jobs clogging up GQ. You can fix this by adding (stringified) exceptions to the config hash:

    GuaranteedQueue.config(
      ...
      whitelisted_exceptions: [ 'ActiveRecord::RecordNotFound' ]
      ...
    )

## Configuration options

```ruby
GuaranteedQueue.config(
  :queue_env => 'edge', # set the queue's env for queue name like *_#{queue_env}
  :max_threads => 10, # your ActiveRecord connection pool should be 2x this number
  :utilization_threshold => 0.5 # jobs will not be started if jobs running / max_threads > this ratio
)
```

## Testing

If your application is running in a `RAILS_ENV` or `RACK_ENV` of `test`, you're good to go. Otherwise, just add `stub_requests => true` to your call to `GuaranteedQueue.config` like so:

    GuaranteedQueue.config(stub_requests: true)

## Contributing

1. Fork it ( http://github.com/colinyoung/guaranteed_queue/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
