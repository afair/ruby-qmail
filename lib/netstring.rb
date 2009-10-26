module RubyQmail
  module Netstring
  
    # Converts the string to a netstring: "length:value,"
    def to_netstring()
      "#{self.size}:#{self},"
    end
  end
end
  
class String#:nodoc:
  include RubyQmail::Netstring
end