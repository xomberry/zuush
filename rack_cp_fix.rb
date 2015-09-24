module Rack
  module Multipart
    class Parser
      def get_filename(head)
        filename = nil
        if head =~ RFC2183
          filename = Hash[head.scan(DISPPARM)]['filename']
          filename = $1 if filename and filename =~ /^"(.*)"$/
        elsif head =~ BROKEN_QUOTED
          filename = $1
        elsif head =~ BROKEN_UNQUOTED
          filename = $1
        end

        if filename && filename.scan(/%.?.?/).all? { |s| s =~ /%[0-9a-fA-F]{2}/ }
          filename = Utils.unescape(filename)
        end
        
        # added this
        if filename && !filename.valid_encoding? 
          filename = filename.force_encoding('cp1251').encode('utf-8')
        end
        # end

        if filename && filename !~ /\\[^\\"]/
          filename = filename.gsub(/\\(.)/, '\1')
        end
        filename
      end
    end
  end
end
