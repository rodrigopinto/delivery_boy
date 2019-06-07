require "logger"
require "kafka"
require "delivery_boy/version"
require "delivery_boy/instance"
require "delivery_boy/fake"
require "delivery_boy/config"
require "delivery_boy/railtie" if defined?(Rails)

module DeliveryBoy
  class << self

    # Write a message to a specified Kafka topic synchronously.
    #
    # Keep in mind that the client will block until the message has been
    # delivered.
    #
    # @param value [String] the message value.
    # @param topic [String] the topic that the message should be written to.
    # @param key [String, nil] the message key.
    # @param partition [Integer, nil] the topic partition that the message should
    #   be written to.
    # @param partition_key [String, nil] a key used to deterministically assign
    #   a partition to the message.
    # @return [nil]
    # @raise [Kafka::BufferOverflow] if the producer's buffer is full.
    # @raise [Kafka::DeliveryFailed] if delivery failed for some reason.
    def deliver(value, topic:, **options)
      instance.deliver(value, topic: topic, **options)
    end

    # Like {.deliver_async!}, but handles +Kafka::BufferOverflow+ errors
    # by logging them and just going on with normal business.
    #
    # @return [nil]
    def deliver_async(value, topic:, **options)
      deliver_async!(value, topic: topic, **options)
    rescue Kafka::BufferOverflow
      logger.error "Message for `#{topic}` dropped due to buffer overflow"
    end

    # Like {.deliver}, but returns immediately.
    #
    # The actual delivery takes place in a background thread.
    #
    # @return [nil]
    def deliver_async!(value, topic:, **options)
      instance.deliver_async!(value, topic: topic, **options)
    end

    # Like {.produce!}, but handles +Kafka::BufferOverflow+ errors
    # by logging them and just going on with normal business.
    #
    # @return [nil]
    def produce(value, topic:, **options)
      produce!(value, topic: topic, **options)
    rescue Kafka::BufferOverflow
      logger.error "Message for `#{topic}` dropped due to buffer overflow"
    end

    # Appends the given message to the producer buffer but does not send it until {.deliver_messages} is called.
    #
    # @param value [String] the message value.
    # @param topic [String] the topic that the message should be written to.
    # @param key [String, nil] the message key.
    # @param partition [Integer, nil] the topic partition that the message should
    #   be written to.
    # @param partition_key [String, nil] a key used to deterministically assign
    #   a partition to the message.
    # @return [nil]
    # @raise [Kafka::BufferOverflow] if the producer's buffer is full.
    def produce!(value, topic:, **options)
      instance.produce(value, topic: topic, **options)
    end

    # Delivers the items currently in the producer buffer.
    #
    # @return [nil]
    # @raise [Kafka::DeliveryFailed] if delivery failed for some reason.
    def deliver_messages
      instance.deliver_messages
    end

    # Shut down DeliveryBoy.
    #
    # Automatically called when the process exits.
    #
    # @return [nil]
    def shutdown
      instance.shutdown
    end

    # The logger used by DeliveryBoy.
    #
    # @return [Logger]
    def logger
      @logger ||= Logger.new($stdout).tap do |logger|
        if config.log_level
          logger.level = Object.const_get("Logger::#{config.log_level.upcase}")
        end
      end
    end

    attr_writer :logger

    # The configuration used by DeliveryBoy.
    #
    # @return [DeliveryBoy::Config]
    def config
      @config ||= DeliveryBoy::Config.new(env: ENV)
    rescue KingKonf::ConfigError => e
      raise ConfigError, e.message
    end

    # Configure DeliveryBoy in a block.
    #
    #     DeliveryBoy.configure do |config|
    #       config.client_id = "yolo"
    #     end
    #
    # @yield [DeliveryBoy::Config]
    # @return [nil]
    def configure
      yield config
    end

    def test_mode!
      @instance = testing
    end

    def testing
      @testing ||= Fake.new
    end

    private

    def instance
      @instance ||= Instance.new(config, logger)
    end
  end
end

at_exit { DeliveryBoy.shutdown }
