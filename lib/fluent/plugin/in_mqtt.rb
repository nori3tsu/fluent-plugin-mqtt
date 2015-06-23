module Fluent
  class MqttInput < Input
    Plugin.register_input('mqtt', self)

    include Fluent::SetTagKeyMixin
    config_set_default :include_tag_key, false

    include Fluent::SetTimeKeyMixin
    config_set_default :include_time_key, true

    config_param :port, :integer, :default => 1883
    config_param :bind, :string, :default => '127.0.0.1'
    config_param :username, :string
    config_param :password, :string
    config_param :topic, :string, :default => '#'
    config_param :format, :string, :default => 'none'

    require 'mqtt'

    def configure(conf)
      super
      @bind ||= conf['bind']
      @topic ||= conf['topic']
      @port ||= conf['port']
      @username ||= conf['username']
      @password ||= conf['password']

      configure_parser(conf)
    end

    def configure_parser(conf)
      @parser = Plugin.new_parser(@format)
      @parser.configure(conf)
    end

    # Return [time (if not available return now), message]
    def parse(message)
      return @parser.parse(message)[1], @parser.parse(message)[0] || Fluent::Engine.now
    end

    def start
      $log.debug "start mqtt #{@bind}"
      @connect = MQTT::Client.connect({remote_host: @bind,
                                       remote_port: @port,
                                       username: @username,
                                       password: @password})
      @connect.subscribe(@topic)

      @thread = Thread.new do
        @connect.get do |topic,message|
          topic.gsub!("/","\.")
          $log.debug "#{topic}: #{message}"
          begin
            parsed_message = self.parse(message)
          rescue Exception => e
            $log.error e
          end
          emit topic, parsed_message[0], parsed_message[1]
        end
      end
    end

    def emit topic, message, time = Fluent::Engine.now
      if message.class == Array
        message.each do |data|
          $log.debug "#{topic}: #{data}"
          Fluent::Engine.emit(topic , time , data)
        end
      else
        Fluent::Engine.emit(topic , time , message)
      end
    end

    def shutdown
      @thread.kill
      @connect.disconnect
    end
  end
end

