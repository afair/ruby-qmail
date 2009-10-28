module RubyQmail
  require 'logger'

  # Configuration for the Qmail system. Loads a configuration YAML file, and accepts a Hash of run-time overrides.
  class Config
    attr_reader :options
    DEFAULTS = {
      :qmqp_port => 628,
      :qmail_root => '/var/qmail',
      :delimiter => '-',
      :logger    => Logger.new("#{ENV['HOME']}/logs/ruby-qmail.log")
    }
    QMQP_SERVERS = '/control/qmqpservers'
    QMAIL_QUEUE  = '/bin/qmail-queue'
        
    def self.load_file(config_file, options={})
      @options = DEFAULTS.merge(options)
      if config_file && File.exists?(config_file)
        @options = YAML.load_file(config_file).merge(@options)
      end
      @options[:qmail_queue] ||= @options[:qmail_root] + QMAIL_QUEUE
      @options[:qmqp_servers] ||= @options[:qmail_root] + QMQP_SERVERS
      @options
    end
    
    def method_missing(method)
      @options[method.to_sym]
    end
    
  end
end
