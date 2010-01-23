class SinatraMPD
  module Views
    class Error < Mustache
      def mpd_host
        @options.mpd_host
      end
      
      def mpd_port
        @options.mpd_port
      end
    end
  end
end
