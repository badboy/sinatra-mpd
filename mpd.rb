#!/usr/bin/ruby -w
require 'socket'

#== mpd.rb
#
#mpd.rb is the Ruby MPD Library
#
#Written for MPD 0.11.5 (see http://www.musicpd.org for MPD itself)
#
#The MPD class provides an interface for communicating with an MPD server (MPD = Music Player
#Daemon, a 'jukebox' server that plays various audio files like mp3, Ogg Vorbis, etc -- see
#www.musicpd.org for more about MPD itself). Method names largely correspond to the same command
#with the MPD protocol itself, and other MPD tools, like mpc.  Some convenience methods for
#writing clients are included as well.
#
#== Usage
# 
#The default host is 'localhost'. The default port is 6600.
#If the user has environment variables MPD_HOST or MPD_PORT set, these
#will override the default settings.
#
#mpd.rb makes no attempt to keep the socket alive. If it dies it just opens a new socket.
#
#If your MPD server requires a password, you will need to use MPD#password= or MPD#password(pass)
#before you can use any other server command. Once you set a password with an instance it will
#persist, even if your session is disconnected.
#
#Unfortunately there is no way to do callbacks from the server. For example, if you want to do
#something special when a new song begins, the best you can do is monitor MPD#currentsong.dbid for a
#new ID number and then do that something when you notice a change. But given latency you are
#unlikely to be able to stop the next song from starting. What I'd like to see is a feature added to
#MPD where when each song finishes it loads the next song and then waits for a "continue" signal
#before beginning playback. In the meantime the only way to do this would be to constantly maintain
#a single song playlist, swapping out the finished song for a new song each time.
#
#== Example
#
# require 'mpd'
#
# m = MPD.new('some_host')
# m.play                   => '256'
# m.next                   => '881'
# m.prev                   => '256'
# m.currentsong.title      => 'Ruby Tuesday'
# m.strf('%a - %t')        => 'The Beatles - Ruby Tuesday'
#
#== About
#
#mpd.rb is Copyright (c) 2004, Michael C. Libby (mcl@andsoforth.com)
# 
#mpd.rb homepage is: http://www.andsoforth.com/geek/MPD.html
#
#report mpd.rb bugs to mcl@andsoforth.com
#
#Translated and adapted from MPD.pm by Tue Abrahamsen. 
#
#== LICENSE
#
#This program is free software; you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation; either version 2 of the License, or
#(at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program; if not, write to the Free Software
#Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#See file LICENSE for details.
#
class MPD
  MPD_VERSION = '0.15.1' #Version of MPD this version of mpd.rb was tested against
  VERSION = '0.2.1'
  DEFAULT_MPD_HOST = ''
  DEFAULT_MPD_PORT = 6600

  # MPD::SongInfo elements are:
  #
  # +file+ :: full pathname of file as seen by server
  # +album+ :: name of the album
  # +artist+ :: name of the artist
  # +dbid+ :: mpd db id for track
  # +pos+ :: playlist array index (starting at 0)
  # +time+ :: time of track in seconds
  # +title+ :: track title
  # +track+ :: track number within album
  #
  SongInfo = Struct.new("SongInfo", "file", "album", "artist", "dbid", "pos", "time", "title", "track")

  # MPD::Error elements are:
  #
  # +number+      :: ID number of the error as Integer
  # +index+       :: Line number of the error (0 if not in a command list) as Integer
  # +command+     :: Command name that caused the error
  # +description+ :: Human readable description of the error
  #
  Error = Struct.new("Error", "number", "index", "command", "description")

  #common regexps precompiled for speed and clarity
  #
  @@re = {
    'ACK_MESSAGE'    => Regexp.new(/^ACK \[(\d+)\@(\d+)\] \{(.+)\} (.+)$/),
    'DIGITS_ONLY'    => Regexp.new(/^\d+$/),
    'OK_MPD_VERSION' => Regexp.new(/^OK MPD (.+)$/),  
    'NON_DIGITS'     => Regexp.new(/^\D+$/),
    'LISTALL'        => Regexp.new(/^file:\s/),
    'PING'           => Regexp.new(/^OK/),
    'PLAYLIST'       => Regexp.new(/^(\d+?):(.+)$/),
    'PLAYLISTINFO'   => Regexp.new(/^(.+?):\s(.+)$/),
    'STATS'          => Regexp.new(/^(.+?):\s(.+)$/),
    'STATUS'         => Regexp.new(/^(.+?):\s(.+)$/),
  }

  # If the user has environment variables MPD_HOST or MPD_PORT set, these will override the default
  # settings. Setting host or port in MPD.new will override both the default and the user settings.
  # Defaults are defined in class constants MPD::DEFAULT_MPD_HOST and MPD::DEFAULT_MPD_PORT.
  #
  def initialize(mpd_host = nil, mpd_port = nil)
    #behavior-related
    @overwrite_playlist = true
    @allow_toggle_states = true
    @debug_socket = false

    @mpd_host = mpd_host || ENV['MPD_HOST'] || DEFAULT_MPD_HOST
    @mpd_port = mpd_port || ENV['MPD_PORT'] || DEFAULT_MPD_PORT

    @socket = nil
    @mpd_version = nil
    @password = nil
    @error = nil
  end

  # Add song at <i>path</i> to the playlist. <i>path</i> is the relative path as seen by the server,
  # not the actual path name of the file on the filesystem.
  #
  def add(path)
    socket_puts("add \"#{path}\"")
  end

  # Clear the playlist of all entries. Consider MPD#save first.
  #
  def clear
    socket_puts("clear")
  end

  # Clear the error element in status info. 
  # Rare that you will need or want to do this. Most error info is cleared automatically anytime a
  # valid play type command is issued or continues to function.
  #
  def clearerror
    @error = nil
    socket_puts("clearerror")
  end
  
  # Close the connection to the server. 
  #
  def close
    return nil unless is_connected?
    socket_puts("close")
    @socket = nil
  end

  # Private method for creating command lists.
  #
  def command_list_begin
    @command_list = ["command_list_begin"]
  end

  # Wish this would take a block, but haven't quite figured out to get that to work
  # For now just put commands in the list.
  #
  def command(cmd)
    @command_list << cmd
  end

  # Closes and executes a command list.
  #
  def command_list_end
    @command_list << "command_list_end"
    sp = @command_list.flatten.join("\n")
    @command_list = []
    socket_puts(sp)
  end

  # Activate a closed connection. Will automatically send password if one has been set.
  #
  def connect
    unless is_connected? then
      warn "connecting to socket" if @debug_socket
      @socket = TCPSocket.new(@mpd_host, @mpd_port)
      if md = @@re['OK_MPD_VERSION'].match(@socket.readline) then
        @mpd_version = md[1]
        if @mpd_version > MPD_VERSION then
          warn "MPD server version newer than mpd.rb version - expect the unexpected"
        end
        unless @password.nil? then
          warn "connect sending password" if @debug_socket
          @socket.puts("password #{@password}")
          get_server_response
        end
      else
        warn "Connection error (Invalid Version Response)"
      end
    end
    return true
  end

  # Clear every entry from the playlist but the current song.
  #
  def crop
    # this really ought to just generate a list and send that to delete()
    command_list_begin
    (playlistlength.to_i - 1).downto(currentsong.pos + 1) do |i|
      command( "delete #{i}" )
    end
    (currentsong.pos - 1).downto(0) do |i|
      command( "delete #{i}" )
    end
    command_list_end
  end

  # Sets the crossfade value (in seconds)
  #
  def crossfade(fade_value)
    socket_puts("crossfade #{fade_value}")
    status['xfade']
  end

  # Returns an instance of Struct MPD::SongInfo.
  #
  def currentsong
    response_to_songinfo(@@re['PLAYLISTINFO'],
                         socket_puts("currentsong")
                         )[0]
  end

  # Turns off socket command debugging.
  #
  def debug_off
    @debug_socket = false
  end

  # Turns on socket command debugging (prints each socket command to STDERR as well as the socket)
  #
  def debug_on
    @debug_socket = true
  end

  # <i>song</i> is one of:
  # * a song's playlist number,
  # * a song's MPD database ID (if <i>from_id</i> is set to true),
  # * any object that implements a <i>collect</i> function that ultimately boils down to a set of integers. :)
  # 
  # Examples:
  # <tt>MPD#delete(1)                  # delete second song (remember playlist starts at index 0)</tt>
  # <tt>MPD#delete(0..4)               # delete first five songs</tt>
  # <tt>MPD#delete(['1', '2', '3'])    # delete songs two, three, and four</tt>
  # <tt>MPD#delete(1..3, 45..48, '99') # delete songs two thru four, forty-six thru forty-nine, and one hundred
  #
  # When <i>from_id</i> is true, the argument(s) will be treated as MPD database IDs.
  # It is not recommended to use ranges with IDs since they are unlikely to be consecutive.
  # An array of IDs, however, would be handy. And don't worry about using indexes in a long list.
  # The function will convert all references to IDs before deleting (as well as removing duplicates).
  def delete(song, from_id = false)
    cmd = from_id ? 'deleteid' : 'delete'
    slist = expand_list(song).flatten.uniq

    if slist.length == 1 then
      return nil unless @@re['DIGITS_ONLY'].match(slist[0].to_s)
      return socket_puts("#{cmd} #{slist[0]}")
    else
      unless from_id then
        # convert to ID for list commands, otherwise as soon as first delete happens
        # the rest of the indexes won't be accurate
        slist = slist.map{|x| playlistinfo(x).dbid }
      end
      command_list_begin
      slist.each do |x|
        next unless @@re['DIGITS_ONLY'].match(slist[0].to_s)
        command("deleteid #{x}")
      end
      return command_list_end
    end
  end

  # Returns a Struct MPD::Error,
  #
  def error
    @error
  end

  # Alias for MPD#delete(song_id, true)
  def deleteid(song_id)
    delete(song_id, true)
  end
  
  # Takes and prepares any <i>collect</i>able list to be flattened and uniq'ed.
  # That is, it converts <tt>[0..2, '3', [4, 5]]</tt> into <tt>[0, 1, 2, '3', [4, 5]]</tt>.
  # Essentially it expands Range objects and the like.
  #
  def expand_list(d)
    if d.respond_to?("collect") then
      if d.collect == d then
        return d.collect{|x| expand_list(x)}
      else
        dc = d.collect
        if dc.length > 1 then
          return d.collect{|x| expand_list(x)}
        else
          return [d]
        end
      end
    else
      return [d]
    end
  end

  # Finds exact matches of <i>find_string</i> in the MPD database.
  # <i>find_type</i> is limited to 'album', 'artist', and 'title'.
  #
  # Returns an array containing an instance of MPD::SongInfo (Struct) for every song in the current
  # playlist.
  #
  # Results from MPD#find() do not have valid information for dbid or pos
  #
  def find(find_type, find_string)
    response_to_songinfo(@@re['PLAYLISTINFO'],
                         socket_puts("find #{find_type} \"#{find_string}\"")
                         )
  end

  # Runs MPD#find using the given parameters and automatically adds each result
  # to the playlist. Returns an Array of MPD::SongInfo structs.
  #
  def find_add(find_type, find_string)
    flist = find(find_type, find_string)
    command_list_begin
    flist.each do |x|
      command("add #{x.file}")
    end
    command_list_end
    flist
  end

  # Private method for handling the messages the server sends. 
  #
  def get_server_response
    response = []
    while line = @socket.readline.chomp do
      # Did we cause an error? Save the data!
      if md = @@re['ACK_MESSAGE'].match(line) then
        @error = Error.new(md[1].to_i, md[2].to_i, md[3], md[4])
        raise "MPD Error #{md[1]}: #{md[4]}"
      end
      return response if @@re['PING'].match(line)
      response << line
    end
    return response
  end

  # Internal method for converting results from currentsong, playlistinfo, playlistid to
  # MPD::SongInfo structs
  #
  def hash_to_songinfo(h)
    SongInfo.new(h['file'],
                 h['Album'],
                 h['Artist'],
                 h['Id'].nil? ? nil : h['Id'].to_i, 
                 h['Pos'].nil? ? nil : h['Pos'].to_i, 
                 h['Time'],
                 h['Title'],
                 h['Track']
                 )
  end

  # Pings the server and returns true or false depending on whether a response was receieved.
  #
  def is_connected?
    return false if @socket.nil? || @socket.closed?
    warn "is_connected to socket: ping" if @debug_socket
    @socket.puts("ping")
    if @@re['PING'].match(@socket.readline) then
      return true
    end
    return false
  rescue
    return false
  end
  
  # Kill the MPD server.
  # No way exists to restart it from here, so be careful.
  #
  def kill
    socket_puts("kill")
  rescue #kill always causes a readline error in get_server_response
    @error = nil
  end

  # Gets a list of Artist names or Album names from the MPD database (not the current playlist).
  # <i>type</i> is either 'artist' (default) or 'album'. The <i>artist</i> parameter is
  # used with <i>type</i>='album' to limit results to just the albums by that artist.
  #
  def list(type = 'artist', artist = '')
    response = socket_puts(type == 'album' ? "list album \"#{artist}\"" : "list artist")
    tmp = []
    response.each do |f|
      if md = /^(?:Artist|Album):\s(.+)$/.match(f) then
        tmp << md[1]
      end
    end
    return tmp
  end

  # Returns a list of all filenames in <i>path</i> (recursively) according to the MPD database.
  # If <i>path</i> is omitted, lists every file in the database.
  #
  def listall(path = '')
    resp = socket_puts("listall \"#{path}\"").grep(@@re['LISTALL']).map{|x| x.sub(@@re['LISTALL'], '')}
    resp.compact
  end

  # Returns an Array containing MPD::SongInfo for each file in <i>path</i> (recursively) according
  # to the MPD database.
  # If <i>path</i> is omitted, lists every file in the datbase.
  def listallinfo(path = '')
    results = []
    hash = {}
    response_to_songinfo(@@re['PLAYLISTINFO'],
                         socket_puts("listallinfo \"#{path}\"")
                         )
  end

  # Load a playlist from the MPD playlist directory.
  #
  def load(playlist)
    socket_puts("load \"#{playlist}\"")
    status['playlistid']
  end

  # Returns Array of strings containing a list of directories, files or playlists in <i>path</i> (as
  # seen by the MPD database).  
  # If <i>path</i> is omitted, uses the root directory.
  def lsinfo(path = '')
    results = []
    element = {}
    socket_puts("lsinfo \"#{path}\"").each do |f|
      if md = /^(.[^:]+):\s(.+)$/.match(f)
        if ['file', 'playlist', 'directory'].grep(md[1]).length > 0 then
          results.push(f)
        end
      end
    end
    return results
  end


  # Returns an Array of playlist paths (as seen by the MPD database).
  #
  def lsplaylists
    lsinfo.grep(/^playlist:\s/).map{|x| x.sub(/^playlist:\s/, '')}.compact
  end

  # Move song at <i>curr_pos</i> to <i>new_pos</i> in the playlist.
  #
  def move(curr_pos, new_pos)
    socket_puts("move #{curr_pos} #{new_pos}")
  end

  # Move song with MPD database ID <i>song_id</i> to <i>new_pos</i> in the playlist.
  #
  def moveid(song_id, new_pos)
    socket_puts("moveid #{song_id} #{new_pos}")
  end

  # Return the version string returned by the MPD server
  #
  def mpd_version
    @mpd_version
  end

  # Play next song in the playlist. See note about shuffling in MPD#set_random
  # Returns songid as Integer.
  #
  def next 
    socket_puts("next")
    currentsong
  end

  # Send the password <i>pass</i> to the server and sets it for this MPD instance. 
  # If <i>pass</i> is omitted, uses any previously set password (see MPD#password=).
  # Once a password is set by either method MPD#connect can automatically send the password if
  # disconnected.  
  #
  def password(pass = @password)
    @password = pass
    socket_puts("password #{pass}")
  end
  
  # Set the password to <i>pass</i>.
  def password=(pass)
    @password = pass
  end

  # Pause playback on the server
  # Returns ('pause'|'play'|'stop'). 
  #
  def pause(value = nil)
    cstatus = status['state']
    return cstatus if cstatus == 'stop'

    if value.nil? && @allow_toggle_states then
      value = cstatus == 'pause' ? '0' : '1'
    end
    socket_puts("pause #{value}")
    status['state']
  end

  # Send a ping to the server and keep the connection alive.
  #
  def ping
    socket_puts("ping")
  end
  
  # Start playback of songs in the playlist with song at index 
  # <i>number</i> in the playlist.
  # Empty <i>number</i> starts playing from current spot or beginning.
  # Returns current song as MPD::SongInfo.
  #
  def play(number = '')
    socket_puts("play #{number}")
    currentsong
  end

  # Start playback of songs in the playlist with song having 
  # mpd database ID <i>number</i>.
  # Empty <i>number</i> starts playing from current spot or beginning.
  # Returns songid as Integer.
  #
  def playid(number = '')
    socket_puts("playid #{number}")
    status['songid']
  end

  # <b>Deprecated</b> Use MPD#playlistinfo or MPD#playlistid instead
  # Returns an Array containing paths for each song in the current playlist
  #
  def playlist
    warn "MPD#playlist is deprecated. Use MPD#playlistinfo or MPD#playlistid instead."
    plist = []
    socket_puts("playlist").each do |f|
      if md = @@re['PLAYLIST'].match(f) then
        plist << md[2]
      end
    end
    plist
  end

  # Returns an array containing an instance of MPD::SongInfo (Struct) for every song in the current
  # playlist or a single instance of MPD::SongInfo (if <i>snum</i> is specified).
  #
  # <i>snum</i> is the song's index in the playlist.
  # If <i>snum</i> == '' then the whole playlist is returned.
  def playlistinfo(snum = '', from_id = false)
    plist = response_to_songinfo(@@re['PLAYLISTINFO'],
                                 socket_puts("playlist#{from_id ? 'id' : 'info'} #{snum}")
                                 )
    return snum == '' ? plist : plist[0]
  end

  # An alias for MPD#playlistinfo with <i>from_id</i> = true.
  # Looks up song <i>sid</i> is the song's MPD ID (<i>dbid</i> in an MPD::SongInfo
  # instance).
  # Returns an Array of Hashes.
  #
  def playlistid(sid = '')
    playlistinfo(sid, true)
  end
  
  # Get the length of the playlist from the server.
  # Returns an Integer
  #
  def playlistlength
    status['playlistlength'].to_i
  end

  # Returns an Array of MPD#SongInfo. The songs listed are either those added since previous
  # playlist version, <i>playlist_num</i>, <b>or</b>, if a song was deleted, the new playlist that
  # resulted. Cumbersome. Eventually methods will be written that help track adds/deletes better.
  #
  def plchanges(playlist_num = '-1')
    response_to_songinfo(@@re['PLAYLISTINFO'],
                         socket_puts("plchanges #{playlist_num}")
                         )
  end

  # Play previous song in the playlist. See note about shuffling in MPD#set_random.
  # Return songid as Integer
  #
  def previous
    socket_puts("previous")
    currentsong
  end
  alias prev previous

  # Sets random mode on the server, either directly, or by toggling (if
  # no argument given and @allow_toggle_states = true). Mode "0" = not 
  # random; Mode "1" = random. Random affects playback order, but not playlist
  # order. When random is on the playlist is shuffled and then used instead
  # of the actual playlist. Previous and next in random go to the previous
  # and next songs in the shuffled playlist. Calling MPD#next and then 
  # MPD#prev would start playback at the beginning of the current song.
  #
  def random(mode = nil)
    return nil if mode.nil? && !@allow_toggle_states
    return nil unless /^(0|1)$/.match(mode) || @allow_toggle_states
    if mode.nil? then
      mode = status['random'] == '1' ? '0' : '1'                                               
    end
    socket_puts("random #{mode}")
    status['random']
  end
  
  # Sets repeat mode on the server, either directly, or by toggling (if
  # no argument given and @allow_toggle_states = true). Mode "0" = not 
  # repeat; Mode "1" = repeat. Repeat means that server will play song 1
  # when it reaches the end of the playlist.
  #
  def repeat(mode = nil)
    return nil if mode.nil? && !@allow_toggle_states
    return nil unless /^(0|1)$/.match(mode) || @allow_toggle_states
    if mode.nil? then
      mode = status['repeat'] == '1' ? '0' : '1'
    end
    socket_puts("repeat #{mode}")
    status['repeat']
  end

  # Private method to convert playlistinfo style server output into MPD#SongInfo list
  # <i>re</i> is the Regexp to use to match "<element type>: <element>".
  # <i>response</i> is the output from MPD#socket_puts.
  def response_to_songinfo(re, response)
    list = []
    hash = {}
    response.each do |f|
      if md = re.match(f) then
        if md[1] == 'file' then
          if hash == {} then
            list << nil unless list == []
          else
            list << hash_to_songinfo(hash)
          end
          hash = {}
        end
        hash[md[1]] = md[2]
      end
    end
    if hash == {} then
      list << nil unless list == []
    else
      list << hash_to_songinfo(hash)
    end
    return list
  end

  # Deletes the playlist file <i>playlist</i>.m3u from the playlist directory on the server.
  #
  def rm(playlist)
    socket_puts("rm \"#{playlist}\"")
  end

  # Save the current playlist as <i>playlist</i>.m3u in the playlist directory on the server.
  # If <i>force</i> is true, any existing playlist with the same name will be deleted before saving.
  #
  def save(playlist, force = @overwrite_playlist)
    socket_puts("save \"#{playlist}\"")
  rescue
    if error.number == 56 && force then
      rm(playlist)
      return socket_puts("save \"#{playlist}\"")
    end
    raise
  end

  # Similar to MPD#find, only search is not strict. It will match <i>search_type</i> of 'artist',
  # 'album', 'title', or 'filename' against <i>search_string</i>.
  # Returns an Array of MPD#SongInfo.
  #
  def search(search_type, search_string)
    response_to_songinfo(@@re['PLAYLISTINFO'],
                         socket_puts("search #{search_type} \"#{search_string}\"")
                         )
  end
  
  # Conducts a search of <i>search_type</i> for <i>search_string</i> and adds the results to the
  # current playlist. Returns the results of the search.
  #
  def search_add(search_type, search_string)
    results = search(search_type, search_string)
    unless results == [] then
      command_list_begin
      results.each do |s|
        command( "add \"#{s.file}\"")
      end
      command_list_end
    end
    return results
  end

  # Seek to <i>position</i> seconds within song number <i>song</i> in the playlist. If no
  # <i>song</i> is given, uses current song.  
  #
  def seek(position, song = currentsong.pos)
    socket_puts("seek #{song} #{position}")
  end

  # Seek to <i>position</i> seconds within song ID <i>song</i>. If no <i>song</i> is given, uses
  # current song.  
  #
  def seekid(position, song_id = currentsong.dbid)
    socket_puts("seekid #{song_id} #{position}")
  end

  # Set the volume to <i>volume</i>. Range is limited to 0-100. MPD#set_volume 
  # will adjust any value passed less than 0 or greater than 100.
  #
  def setvol(vol)
    vol = 0 if vol.to_i < 0
    vol = 100 if vol.to_i > 100
    socket_puts("setvol #{vol}")
    status['volume']
  end

  # Shuffles the current playlist and increments playlist version by 1.
  # This will rearrange your actual playlist with no way to resort it 
  # (other than saving it before shuffling and then reloading it).
  # If you just want random playback use MPD#random.
  #
  def shuffle
    socket_puts("shuffle")
  end

  # Sends a command to the MPD server and optionally to STDOUT if
  # MPD#debug_on has been used to turn debugging on
  #
  def socket_puts(cmd)
    connect unless is_connected?
    warn "socket_puts to socket: #{cmd}" if @debug_socket
    @socket.puts(cmd)
    return get_server_response
  end

  # Returns a hash containing various server stats:
  #
  # +albums+ :: number of albums in mpd database
  # +artists+ :: number of artists in mpd database
  # +db_playtime+ :: sum of all song times in in mpd database
  # +db_update+ :: last mpd database update in UNIX time
  # +playtime+ :: time length of music played during uptime
  # +songs+ :: number of songs in mpd database
  # +uptime+ :: mpd server uptime in seconds
  #
  def stats
    s = {}
    socket_puts("stats").each do |f|
      if md = @@re['STATS'].match(f);
        s[md[1]] = md[2] 
      end
    end
    return s
  end

  # Returns a hash containing various status elements:
  #
  # +audio+ :: '<sampleRate>:<bits>:<channels>' describes audio stream
  # +bitrate+ :: bitrate of audio stream in kbps
  # +error+ :: if there is an error, returns message here
  # +playlist+ :: the playlist version number as String
  # +playlistlength+ :: number indicating the length of the playlist as String
  # +repeat+ :: '0' or '1'
  # +song+ :: playlist index number of current song (stopped on or playing)
  # +songid+ :: song ID number of current song (stopped on or playing)
  # +state+ :: 'pause'|'play'|'stop'
  # +time+ :: '<elapsed>:<total>' (both in seconds) of current playing/paused song
  # +updating_db+ :: '<job id>' if currently updating db
  # +volume+ :: '0' to '100'
  # +xfade+ :: crossfade in seconds
  #
  def status
    s = {}
    socket_puts("status").each do |f|
      if md = @@re['STATUS'].match(f) then
        s[md[1]] = md[2]
      end
    end
    return s
  end
  
  # Stops playback.
  # Returns ('pause'|'play'|'stop').
  #
  def stop
    socket_puts("stop")
    status['state']
  end

  # Pass a format string (like strftime) and get back a string of MPD information.
  #
  # Format string elements are: 
  # <tt>%f</tt> :: filename
  # <tt>%a</tt> :: artist
  # <tt>%A</tt> :: album
  # <tt>%i</tt> :: MPD database ID
  # <tt>%p</tt> :: playlist position
  # <tt>%t</tt> :: title
  # <tt>%T</tt> :: track time (in seconds)
  # <tt>%n</tt> :: track number
  # <tt>%e</tt> :: elapsed playtime (MM:SS form)
  # <tt>%l</tt> :: track length (MM:SS form)
  #
  # <i>song_info</i> can either be an existing MPD::SongInfo object (such as the one returned by
  # MPD#currentsong) or the MPD database ID for a song. If no <i>song_info</i> is given, all
  # song-related elements will come from the current song.
  #
  def strf(format_string, song_info = currentsong) 
    unless song_info.class == Struct::SongInfo
      if @@re['DIGITS_ONLY'].match(song_info.to_s) then
        song_info = playlistid(song_info)
      end
    end

    s = ''
    format_string.scan(/%[EO]?.|./o) do |x|
      case x
      when '%f'
        s << song_info.file.to_s

      when '%a'
        s << song_info.artist.to_s

      when '%A'
        s << song_info.album.to_s

      when '%i'
        s << song_info.dbid.to_s

      when '%p'
        s << song_info.pos.to_s
        
      when '%t'
        s << song_info.title.to_s

      when '%T'
        s << song_info.time.to_s

      when '%n'
        s << song_info.track.to_s

      when '%e'
        t = status['time'].split(/:/)[0].to_f
        s << sprintf( "%d:%02d", t / 60, t % 60 )

      when '%l'
        t = status['time'].split(/:/)[1].to_f
        s << sprintf( "%d:%02d", t / 60, t % 60 )

      else
        s << x.to_s

      end
    end
    return s
  end

  # Swap two songs in the playlist, either based on playlist indexes or song IDs (when <i>from_id</i> is true).
  #
  def swap(song_from, song_to, from_id = false)
    if @@re['DIGITS_ONLY'].match(song_from.to_s) && @@re['DIGITS_ONLY'].match(song_to.to_s) then
      return socket_puts("#{from_id ? 'swapid' : 'swap'} #{song_from} #{song_to}")
    else 
      raise "invalid input for swap"
    end
  end
  
  # Alias for MPD#swap(song_id_from, song_id_to, true)
  #
  def swap_id(song_id_from, song_id_to)
    swap(song_id_from, song_id_to, true)
  end

  # Searches MP3 directory for new music and removes old music from the MPD database.
  # <i>path</i> is an optional argument that specifies a particular directory or 
  # song/file to update. <i>path</i> can also be a list of paths to update.
  # If <i>path</i> is omitted, the entire database will be updated using the server's 
  # base MP3 directory.
  #
  def update(path = '')
    ulist = expand_list(path).flatten.uniq
    if ulist.length == 1 then
      return socket_puts("update #{ulist[0]}")
    else
      command_list_begin
      ulist.each do |x|
        command("update #{x}")
      end
      return command_list_end
    end
  end
  
  # Returns the types of URLs that can be handled by the server.
  #
  def urlhandlers
    handlers = []
    socket_puts("urlhandlers").each do |f|
      handlers << f if /^handler: (.+)$/.match(f)
    end
    return handlers
  end

  # <b>Deprecated</b> Use MPD#setvol instead.
  # Increase or decrease volume (depending on whether <i>vol_change</i> is positive or
  # negative. Volume is limited to the range of 0-100 (server ensures that change
  # does not take volume out of range).
  # Returns volume.
  #
  def volume(vol_change)
    warn "MPD#volume is deprecated. Use MPD#setvol instead."
    socket_puts("volume #{vol_change}")
    status['volume']
  end

  private :command, :command_list_begin, :command_list_end, :expand_list
  private :connect, :get_server_response, :socket_puts
  private :hash_to_songinfo, :response_to_songinfo
end
