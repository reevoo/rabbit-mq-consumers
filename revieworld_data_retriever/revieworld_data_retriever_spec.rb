require 'rspec'
require 'evented-spec'
require 'pry'
require 'pry-nav'
require_relative 'revieworld_data_retriever'

module Helpers
  def send_message_and_store_response(query)
    @channel.queue("", :exclusive => true, :auto_delete => true) do |replies_queue|
      replies_queue.subscribe do |metadata, payload|
        @result_data = JSON.parse payload
      end

      @exchange.publish(
        query,
        :routing_key => "revieworld.data-request.#{query[:class]}",
        :message_id  => Kernel.rand(10101010).to_s,
        :reply_to    => replies_queue.name
      )
    end
  end
end

describe 'It writes data to torque' do
  include EventedSpec::AMQPSpec
  include Helpers

  let(:message) { {'message' => 'hash'} }
  let(:missing_response) { double(:response, code: '404', body: '<<error>>') }
  let(:response) { double(:response, code: '202', body: message.to_json) }

  amqp_before do
    # initializing amqp channel
    @channel   = AMQP::Channel.new
    # using default amqp exchange
    @exchange = @channel.topic(RevieworldDataRetriever::TOPIC_NAME)
  end

  it 'will return data' do
    Net::HTTP.stub(get_response: response)

    RevieworldDataRetriever.new(@channel).run!

    send_message_and_store_response({class: :reviews, format: :torque, conditions: {id: 120}})

    done(0.2) {
      # After #done is invoked, it launches an optional callback
      @channel.queue(RevieworldDataRetriever::QUEUE_NAME).delete
      # Here goes the main check
      @result_data.should == message
    }
  end

  it 'will wait for data to appear' do
    Net::HTTP.stub(:get_response).and_return(missing_response, response)

    RevieworldDataRetriever.new(@channel, timeout: 0.1).run!

    send_message_and_store_response({class: :reviews, format: :torque, conditions: {id: 120}})

    done(0.2) {
      # After #done is invoked, it launches an optional callback
      @channel.queue(RevieworldDataRetriever::QUEUE_NAME).delete
      # Here goes the main check
      @result_data.should == message
    }

  end
end