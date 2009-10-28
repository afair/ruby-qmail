module RubyQmail
  
  class Queue
    include Process
    attr_accessor( :return_path, :message, :recipients, :options, :response, :success )
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
    def self.insert(return_path, recipients, message, *options)
      q = Queue.new(return_path, recipients, message, *options)
      if q.options.has_key?[:ip] || q.options[:method]==:qmqp 
        q.qmqp
      else
        q.qmail_queue
      end
    end
    
    # Recipients can be a filename, array or other object that responds to :each, or #to_s resolves to an email address
    # Message can be a filename, string, or other object that responds to :each
    def initialize(return_path=nil, recipients=nil, message=nil, *options)
      parameters(return_path, recipients, message, options)
    end
      
    def parameters(return_path, recipients, message, options) #:nodoc:
      @return_path = return_path if return_path
      @options     = RubyQmail::Config.load_file( nil, options.last || {})
      @recipients  = recipients if recipients
      @recipients  = File.new(@recipients) if @recipients.is_a?(String) && File.exists?(@recipients)
      @recipients  = [ @recipients.to_s ] unless @recipients.respond_to?(:each)
      @message     = message if message
      @message     = File.new(@message) if @message.is_a?(String) && File.exists?(@message)
      @message     = @message.split(/\n/) if @message.is_a?(String)

      # Edits the return path for VERP. bounces@example.com => bounces-@example.com-@[]
      if return_path && !@options.has_key?(:noverp)
        rp1, rp2 = return_path.split(/@/)
        @return_path = "#{rp1}#{@options[:delimiter]}@#{rp2}" if (rp1.match(/(.)$/)[1] != @options[:delimiter])
        @return_path += '-@[]' unless @return_path =~ /-@\[\]$/
      end
    end
    
    # This calls the Qmail-Queue program, so requires qmail to be installed (does not require it to be currently running).
    def queue(return_path=nil, recipients=nil, message=nil, *options)
      parameters(return_path, recipients, message, options)
      @success = run_qmail_queue() do |msg, env|
        # Send the Message
        @message.each { |m| msg.puts(m) }
        msg.close

        env.write('F' + @return_path + "\0")
        @recipients.each { |r| env.write('T' + r + "\0") }      
        env.write("\0") # End of "file"
      end
      @options[:logger].info("RubyQmail Queue exited:#{@success} #{Queue.qmail_queue_error_message(@success)}")
      return true if @success == QMAIL_QUEUE_SUCCESS
      raise Queue.qmail_queue_error_message(@success)
    end
    
    # Maps the qmail-queue exit code to the error message
    def self.qmail_queue_error_message(code) #:nodoc:
      "RubyQmail::Queue Error #{code}:" + QMAIL_ERRORS.has_key?(code) ? QMAIL_ERRORS[code]:QMAIL_ERRORS[-1]
    end
    
    # Builds the QMQP request, and opens a connection to the QMQP Server and sends
    # This implemtents the QMQP protocol, so does not need Qmail installed on the host system.
    # System defaults will be used if no ip or port given.
    # Returns true on success, false on failure (see @response), or nul on deferral
    def qmqp(return_path=nil, recipients=nil, message=nil, *options)
      parameters(return_path, recipients, message, options)
      
      begin
        ip = @options[:ip] || File.readlines(QMQP_SERVERS).first.chomp
        #puts "CONNECT #{:ip}, #{@options[:qmqp_port]}"
        socket = TCPSocket.new(ip, @options[:qmqp_port])
        raise "QMQP can not connect to #{ip}:#{@options[:qmqp_port]}" unless socket
        
        # Build netstring of messagebody+returnpath+recipient...
        nstr = (@message.map.join("\n")+"\n").to_netstring # { |m| m }.join("\t").to_netstring
        nstr += @return_path.to_netstring
        nstr += @recipients.map { |r| r.to_netstring }.join
        socket.send( nstr.to_netstring, 0 )

        @response = socket.recv(1000) # "23:Kok 1182362995 qp 21894," (its a netstring)
        @success = case @response.match(/^\d+:([KZD])(.+),$/)[1]
          when 'K' : true  # success
          when 'Z' : nil   # deferral
          when 'D' : false # failure
          else false
        end
        logmsg = "RubyQmail QMQP [#{ip}:#{@options[:qmqp_port]}]: #{@response} return:#{@success}"
        @options[:logger].info(logmsg)
        puts logmsg
        @success
      rescue Exception => e
        @options[:logger].error( "QMQP can not connect to #{@opt[:qmqp_ip]}:#{@options[:qmqp_port]} #{e}" )
        raise e
      ensure
        socket.close if socket
      end
    end
    
    # # Like #qmail_queue, but writes directly to the queue, not via the qmail-queue program
    # # Is this a good idea? It expects a unique PID per message.
    # def qmail_queue_direct(return_path=nil, recipients=nil, message=nil, *options)
    #   parameters(return_path, recipients, message, options)
    # end

    # def sendmail(return_path=nil, recipients=nil, message=nil, *options)
    #   parameters(return_path, recipients, message, options)
    # end

    # Sends email directly via qmail-remote. It does not store in the queue, It will halt the process
    # and wait for the network event to complete. If multiple recipients are passed, it will run
    # qmail-remote delivery for each at a time to honor VERP return paths.
    def qmail_remote(return_path=nil, recipients=nil, message=nil, *options)
      parameters(return_path, recipients, message, options)
      rp1, rp2 = @return_path.split(/@/,2)
      rp = @return_path
      @recipients.each do |recip|
        unless @options[:noverp]
          mailbox, host = recip.split(/@/)
          rp = "#{rp1}#{mailbox}=#{host}@#{rp2}"
        end

        @message.rewind if @message.respond_to?(:rewind)
        cmd = "#{@options[:qmail_root]}+/bin/qmail-remote #{host} #{rp} #{recip}"
        @success = self.spawn_command(cmd) do |send, recv|
          @message.each { |m| send.puts m }
          send.close
          @response = recv.readpartial(1000)
        end

        @options[:logger].info("RubyQmail Remote #{recip} exited:#{@success} responded:#{@response}")
      end
      return [ @success, @response ] # Last one
    end
        
    # Forks, sets up stdin and stdout pipes, and starts the command. 
    # IF a block is passed, yeilds to it with [sendpipe, receivepipe], 
    # returing the exit code, otherwise returns {:send=>, :recieve=>, :pid=>}
    # qmail-queue does not work with this as it reads from both pipes.
    def spawn_command(command, &block)
      child_read, parent_write = IO.pipe # From parent to child(stdin)
      parent_read, child_write = IO.pipe # From child(stdout) to parent
      @child = fork

      # Child process
      unless @child # 
        $stdin.close # closes FD==0
        child_read.dup # copies to FD==0
        child_read.close
        
        $stdout.close # closes FD==1
        child_write.dup # copies to FD==1
        child_write.close

        Dir.chdir(@options[:qmail_root]) unless @options[:nochdir]
        exec(command)
        raise "Exec spawn_command #{command} failed"
      end
      
      # Parent Process with block
      if block_given?
        yield(parent_write, parent_read)
        parent_write.close
        parent_read.close
        wait(@child)
        @success = $? >> 8
        return @sucess
      end
      
      # Parent process, no block
      {:send=>parent_write, :receive=>parent_read, :pid=>@child}
    end

    # Forks, sets up stdin and stdout pipes, and starts qmail-queue. 
    # IF a block is passed, yields to it with [sendpipe, receivepipe], 
    # and returns the exist cod, otherwise returns {:msg=>pipe, :env=>pipe, :pid=>@child}
    # It exits 0 on success or another code on failure. 
    # Qmail-queue Protocol: Reads mail message from File Descriptor 0, then reads Envelope from FD 1
    # Envelope Stream: 'F' + sender_email + "\0" + ("T" + recipient_email + "\0") ... + "\0"
    def run_qmail_queue(command=nil, &block)
      # Set up pipes and qmail-queue child process
      msg_read, msg_write = IO.pipe
      env_read, env_write = IO.pipe
      @child=fork # child? nil : childs_process_id

      unless @child 
        ## Set child's stdin(0) to read from msg
        $stdin.close # FD=0
        msg_read.dup
        msg_read.close
        msg_write.close

        ## Set child's stdout(1) to read from env
        $stdout.close # FD=1
        env_read.dup
        env_read.close
        env_write.close

        # Change directory and load command
        Dir.chdir(@options[:qmail_root])
        exec( command || @options[:qmail_queue] )
        raise "Exec qmail-queue failed"
      end

      # Parent Process with block
      if block_given?
        yield(msg_write, env_write)
      # msg_write.close
        env_write.close
        wait(@child)
        @success = $? >> 8
        # puts "#{$$} parent waited for #{@child} s=#{@success} #{$?.inspect}"
        return @sucess
      end
      
      # Parent process, no block
      {:msg=>msg_write, :env=>env_write, :pid=>@child}
    end

  end

end
