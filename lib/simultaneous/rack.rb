# encoding: UTF-8

require 'rack/async'

module Simultaneous
  module Rack
    # A Rack handler that allows you to create a HTML5 Server-Sent Events
    # endpoint built using EventMachine in order to easily handle multiple
    # open connections simultaneously
    #
    # To use, first create an instance of the EventSource class:
    #
    #   messenger = Simultaneous::Rack::EventSource.new
    #
    # Then map this onto a URL in your application, e.g. in a RackUp file
    #
    #   app = ::Rack::Builder.new do
    #     map "/messages" do
    #       run messenger.app
    #     end
    #   end
    #   run app
    #
    # In your web-page, set up an EventSource using the new APIs
    #
    #   source = new EventSource('/messages');
    #   source.addEventListener('message', function(e) {
    #     alert(e.data);
    #   }, false);
    #
    #
    # Then when you want to send a messages to all your clients you
    # use your (Ruby) EventSource instance like so:
    #
    #   messenger.deliver("Hello!")
    #
    # IMPORTANT:
    #
    # This will only work when run behind Thin or some other, EventMachine
    # driven webserver. See <https://github.com/matsadler/rack-async> for more
    # info.
    #
    class EventSource

      def initialize
        @lock = Mutex.new
        @timer = nil
        @clients = []
      end

      def app
        ::Rack::Async.new(self)
      end

      def call(env)
        stream = env['async.body']
        stream.errback { cleanup!(stream) }

        @lock.synchronize { @clients << stream }

        [200, {"Content-type" => "text/event-stream"}, stream]
      end

      def deliver(message)
        data = "data: #{message}\n\n"
        @clients.each do |client|
          client << data
        end
        puts "#{Time.now}: Message #{message.inspect}; Clients: #{@clients.length}"
      end

      private

      def cleanup!(connection)
        @lock.synchronize { @clients.delete(connection) }
      end
    end
  end
end