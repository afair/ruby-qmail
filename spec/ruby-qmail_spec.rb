require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "RubyQmail" do

  before(:all) do
    @rqq = RubyQmail::Queue.new()
    @rpath = 'allen-whitelist@biglist.com'
    @recip = %w( allen-1@biglist.com allen-2@biglist.com )
    @msg   = %q(To: allen-admin@biglist.com
From: allen-listmaster@biglist.com
Subject: ruby-qmail

testing 1 2 3. 
later!
)
  end
  
  it "should add a #to_netstring method to the string class" do
    "qmail".to_netstring.should == "5:qmail,"
  end

  # it "should submit a message by qmail-queue" do
  #   @rqq.queue( @rpath, @recip, @msg ).should_be true
  # end

  it "should submit a message by QMQP" do
    @rqq.qmqp( @rpath, @recip, @msg, :ip=>'173.161.130.227', :qmqp_port=>631 ).should_be true
  end


end
