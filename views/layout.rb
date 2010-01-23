class SinatraMPD
  module Views
    class Layout < Mustache
      def title 
        @title || "Sinatra-MPD"
      end
    end
  end
end
