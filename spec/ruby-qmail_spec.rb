require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

describe "RubyQmail" do
  
  it "should add a #to_netstring method to the string class" do
    "qmail".to_netstring.should == "5:qmail,"
  end
  
end

def self.test #:nodoc:
  puts RubyQmail::Qmqp.sendmail("allen-listmaster-test@biglist.com", ["allen-admin@biglist.com", "allen-admin2@biglist.com"], 
%q(To: allen-admin@biglist.com
From: allen-listmaster@biglist.com
Subject: Testing Qmail Ruby

testing 1 2 3. 
later!
), :qmqp_ip=>'74.0.4.28', :qmqp_port=>631)
end
