class SinatraMPD
  module Views
    class Index < Mustache
      def state
        @state || 'unknown'
      end

      def is_playing
        @state == 'play'
      end
      
      def is_not_playing
        @state != 'play'
      end

      def song
        song_or_file(@mpd.currentsong)
      end

      def playlist
        i = 0
        @mpd.playlistinfo.map do |song|
          { :entry => song_or_file(song), :id => i+=1, :current => @mpd.currentsong == song }
        end
      end

      private
      def song_or_file(song)
        if song.artist && song.title
          "#{song.artist} - #{song.title}"
        else
          song.file
        end
      end
    end
  end
end
