module RubyQmail
  
  # The "qmail-queue" protocol base class, from which multiple methods can derived (queue, qmqpc, etc.) This
  # protocol is chainable, the output of one can be input into another until the last one in the chain, where
  # the email is deposited into the mail queue.
  class Queue
    attr_accessor( :return_path, :message, :recipients, :options, :response, :success)
    QMAIL_QUEUE_SUCCESS = 0
    QMAIL_ERRORS = {
      -1 => "Unknown Error",
       0 => "Success",
      11 => "Address too long",
      31 => "Mail server permanently refuses to send the message to any recipients.",
      51 => "Out of memory.",
      52 => "Timeout.",
      53 => "Write error; e.g., disk full.",
      54 => "Unable to read the message or envelope.",
      55 => "Unable to read a configuration file.",
      56 => "Problem making a network connection from this host.",
      61 => "Problem with the qmail home directory.",
      62 => "Problem with the queue directory.",
      63 => "Problem with queue/pid.",
      64 => "Problem with queue/mess.",
      65 => "Problem with queue/intd.",
      66 => "Problem with queue/todo.",
      71 => "Mail server temporarily refuses to send the message to any recipients.",
      72 => "Connection to mail server timed out.",
      73 => "Connection to mail server rejected. ",
      74 => "Connection to mail server  succeeded,  but  communication  failed.",
      81 => "Internal bug; e.g., segmentation fault.",
      91 => "Envelope format error"
    }
    
    # Class Method to place the message into the Qmail queue.
    def self.enqueue(return_path, recipients, message, *options)
      QueueBase.new(return_path, recipients, message, *options).qmail_queue
    end
    
    # Recipients can be a filename, array or other object that responds to :each, or #to_s resolves to an email address
    # Message can be a filename, string, or other object that responds to :each
    def initialize(return_path, recipients, message, *options)
      parameters(return_path, recipients, message, options)
    end
      
    def parameters(return_path, recipients, message, options) #:nodoc:
      @return_path ||= return_path
      @options     = RubyQmail::Config.load_file(RUBY_QMAIL_CONFIG, options.last || {})
      @recipients  ||= recipients
      @recipients  = File.new(@recipients) if @recipients.is_a?(String) && File.exists?(@recipients)
      @recipients  = [ @recipients.to_s ] unless @recipients.respond_to?(:each)
      @message     ||= message
      @message     = File.new(@message) if @message.is_a?(String) && File.exists?(@message)
      @message     = [ @message.to_s ] unless @message.respond_to?(:each)      
    end
    
    # This calls the Qmail-Queue program, so requires qmail to be installed (does not require it to be currently running).
    def qmail_queue(return_path, recipients, message, *options)
      parameters(return_path, recipients, message, options)
    
      # Set up pipes and qmail-queue child process
      @pipe_msg_read, @pipe_msg_write = IO.pipe
      @pipe_env_read, @pipe_env_write = IO.pipe
      @child=start_qmail_queue()
      @pipe_msg_read.close
      @pipe_env_read.close
      
      # Send the Message
      @message.each { |m| @pipe_msg_write.puts(m) }
      
      # Send the Envelope
      @pipe_env_write.write('F' + @return_path + "\0")
      @recipients.each { |r| @pipe_env_write.write('T' + r + "\0") }      
      @pipe_env_write.write("\0")

      # Clean up, wait for response
      @pipe_msg_write.close
      @pipe_env_write.close
      wait(@child)
      
      @success = $? >> 8
      return @success = true if @success == QMAIL_QUEUE_SUCCESS
      @options[:logger].error(self.qmail_queue_error_message(@success))
      raise self.qmail_queue_error_message(@success)
    end
    
    # Starts 'qmail-queue' to insert the message into the mail queue, returnomg the child process id.
    # Note that qmail-queue can be any other program implenting the qmail-queue protocol (suck as 
    # qmail-qmqpc), chaining until the mail is ultimate deposited into a mail queue somewhere. 
    # It exits 0 on success or another code on failure. 
    # Qmail-queue Protocol: Reads mail message from File Descriptor 0, then reads Envelope from FD 1
    # Envelope Stream: 'F' + sender_email + "\0" + ("T" + recipient_email + "\0") ... + "\0"
    def self.start_qmail_queue
      @child=fork # child? nil : childs_process_id
      return @child if @child 

      ## Set child's stdin(0) to pipe_msg
      $stdin.close # FD=0
      @pipe_msg_read.dup
      @pipe_msg_read.close
      @pipe_msg_write.close

      ## Set child's stdout(1) to pipe_env
      $stdout.close # FD=1
      @pipe_env_read.dup
      @pipe_env_read.close
      @pipe_env_write.close

      # Change directory and load command
      Dir.chdir(@options[:qmail_base])
      exec(@options[:qmail_queue])
      raise "Exec qmail-queue failed"
    end

    # Maps the qmail-queue exit code to the error message
    def self.qmail_queue_error_message(code) #:nodoc:
      "RubyQmail::Queue Error #{code}:" + QMAIL_ERRORS.has_key?(code) ? QMAIL_ERRORS[code]:QMAIL_ERRORS[-1]
    end
    
    # Builds the QMQP request, and opens a connection to the QMQP Server and sends
    # This implemtents the QMQP protocol, so does not need Qmail installed on the host system.
    # System defaults will be used if no ip or port given.
    def qmail_qmqpc(return_path, recipients, message, *options)
      parameters(return_path, recipients, message, options)
      
      begin
        ip ||= @options[:ip] || File.readlines(QMQP_SERVERS).first.chomp
        socket = TCPSocket.new(ip, port || @options[:qmqp_port])
        raise "QMQP can not connect to #{@opt[:qmqp_ip]}:#{@options[:qmqp_port]}" unless socket
        
        nstr = @message.each { |m| m }.join("\t").to_netstring
        nstr += "F#{@return_path}".to_netstring
        nstr = @recipients.each { |r| "T#{@return_path}".to_netstring }.join
        socket.send( mstr.to_netstring )
        
        @response = socket.recv(1000) # "23:Kok 1182362995 qp 21894,"
        @options[:logger].info("RubyQmail QMQP [#{@opt[:qmqp_ip]}:#{@options[:qmqp_port]}]: #{@response}")
        socket.close
        
        if @response =~ /^\d+:([KZD])(.+),$/
          @options[:logger].debug("QMQP #{@return_path} to #{@recipient_count} recipients including #{@last_recipient}: #{$1+$2}")
        end
        @success = case $1
          when 'K' : true  # success
          when 'Z' : nil   # deferral
          when 'D' : false # failure
        end
      rescue e
        @options[:logger].error("QMQP exception #{e}")
        raise e
      ensure
        socket.close if socket
      end
    end
    
  end
  
  # Like #qmail_queue, but writes directly to the queue, not via the qmail-queue program
  # Is this a good idea? It expects a unique PID per message.
  def qmail_queue_direct(return_path, recipients, message, *options)
    parameters(return_path, recipients, message, options)
  end
  
  # Sends email directly via qmail-remote. It does not store in the queue, It will halt the process
  # and wait for the network event to complete.
  def qmail_remote(return_path, recipients, message, *options)
    parameters(return_path, recipients, message, options)
    # Each recipient has to be processed independently to honor VERP.
    @recipients.each do |recip|
      mailbox, host = recip.split(/@/)
      rp1, rp2 = @return_path.split(/@/)
      verp = (rp1.ends_with?('-') ? rp1 : rp1+'-') + mailbox + '=' + host + '@' + rp2
      @message.rewind if @message.respond_to?(:rewind)
      success, result = self.qmail_spawn("#{@options[:qmail_base]}+/bin/qmail-remote #{host} #{verp} #{recip}") do |send|
        @message.each { |m| send.puts m }
      end
    end
  end
      
  # Forks, sets up stdin and stdout pipes, and starts the command. Returns {:send=>, :recieve=>, :pid=>}
  # qmail-queue does not work with this as it reads from both pipes, and only returns the exit code.
  def self.qmail_spawn(command, &block)
    child_read, parent_write = IO.pipe # From parent to child(stdin)
    parent_read, child_write = IO.pipe # From child(stdout) to parent
    @child = fork

    # Child process
    unless @child # 
      $stdin.close # closes FD==0
      child_read.dup # copies to FD==0
      child_read.close
      
      $stdout.close # closed FD==1
      child_write.dup # copes to FD==1
      child_write.close

      Dir.chdir(@options[:qmail_base])
      exec(command)
      raise "Exec qmail_pipe #{command} failed"
    end
    
    # Parent Process with block
    if block_given?
      yield(parent_write)
      parent_write.close
      @result = parent_read.readpartial(1000)
      parent_read.close
      wait(@child)
      @success = $? >> 8
      return [@sucess, @result]
    end
    
    # Parent process, no block
    {:send=>parent_write, :receive=>parent_read, :pid=>@child}
  end

end