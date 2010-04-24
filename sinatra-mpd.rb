#!/usr/bin/env ruby
# encoding: utf-8

require 'mpd'
require 'cgi'

class SinatraMPD < Sinatra::Base
  set :mpd_host, 'localhost'
  set :mpd_port, 6600
  enable :inline_templates

  before do
    if request.env['PATH_INFO'] != '/error'
      begin
        @mpd = MPD.new(options.mpd_host, options.mpd_port)
        @mpd.ping
        headers({ 'Cache-Control' => 'no-cache' })
      rescue Errno::ECONNREFUSED, EOFError
        redirect '/error'
      end
    end
  end

  helpers do
    def song_or_file(song)
      if song.artist && song.title
        "#{song.artist} - #{song.title}"
      else
        song.file
      end
    end

    def control_mpd(command, *args)
      if args && !args.empty?
        @mpd.send(command, *args)
      else
        @mpd.send(command)
      end
    rescue EOFError
      redirect '/error'
    end

    def add_link(file)
      CGI.escape(file.gsub('/', '|').gsub('&', '||'))
    end
  end

  get '/error' do
    @title = 'Sinatra-MPD | error'
    @options = options
    erb :error
  end

  get '/' do
    @title = 'Sinatra-MPD'
    @state = @mpd.status['state']
    @is_playing = @state == 'play'

    @vol = @mpd.status['volume']
    begin
      @vol = Integer(@vol)
    rescue ArgumentError
      @vol = nil
    end

    @song = song_or_file(@mpd.currentsong)
    i = 0
    @playlist = @mpd.playlistinfo.map do |song|
      [ i+=1, song_or_file(song), @mpd.currentsong == song ]
    end

    erb :index
  end

  get '/vol/' do
    begin
      new_vol = Integer(params[:vol])
      control_mpd(:setvol, new_vol)
    rescue ArgumentError
      nil
    ensure
      redirect '/'
    end
  end

  get '/vol/:vol' do
    begin
      vol = Integer(@mpd.status['volume'])
      new_vol = vol
      case params[:vol]
      when 'plus'
        new_vol += 10 unless vol >= 100
      when 'minus'
        new_vol -= 10 unless vol <= 0
        puts "vol = #{vol.inspect}\nnew_vol = #{new_vol.inspect}"
      end
      control_mpd(:setvol, new_vol)
    rescue ArgumentError
      nil
    ensure
      redirect '/'
    end
  end

  get '/play/:id' do
    id = params[:id].to_i
    unless id == 0
      id -= 1
      control_mpd(:play, id)
    end
    redirect '/#current'
  end

  get '/search' do
    @result = nil
    @q = nil
    if params[:q]
      q = params[:q]
      @q = CGI.escapeHTML(q)
      @result = @mpd.listallinfo.select{ |item|
        [:file, :artist, :album, :title].any? { |meth|
          item.send(meth) =~ /#{Regexp.escape(q)}/i
        }
      }
    end

    erb :search
  end

  get '/add/:file' do
    searched_file = CGI.unescape(params[:file]).gsub('||', '&').gsub('|', '/')
    if searched_file
      file_add = @mpd.listall.select { |file|
        file == searched_file
      }
      control_mpd(:add, file_add)
    end
    redirect '/'
  end

  %w[play pause stop prev next].each do |action|
    get "/#{action}" do
      control_mpd(action)
      redirect '/'
    end
  end
end

__END__
@@layout
<!DOCTYPE html>
<html>
  <head>
    <meta content='text/html; charset=UTF-8' http-equiv='Content-Type' />
    <title>
      <%= @title %>
    </title>
  </head>
  <body>
    <div id="main">
      <%= yield %>
    </div>

    <p><a href="#main">top</a></p>
  </body>
</html>

@@index
<p>
  <a href="/">reload</a> |
  <a href="/#current">current</a> |
  <a href="/search">search</a>
</p>
<p>np: <%= @song %></p>
<p>State: <%= @state %> (<%=@playlist.size%> files in playlist)</p>
<form action="/vol/" style="display:inline;">
  <p>
    Volume:
    <select name="vol">
    <% [100, 90, 80, 70, 60, 50, 40, 30, 20, 10, 0].each do |vol| %>
      <% if @vol == vol %>
        <option value="<%=vol%>" selected="selected">! <%=vol%>%</option>
      <%else%>
        <option value="<%=vol%>"><%=vol%>%</option>
      <%end%>
    <%end%>
    </select>
    <input type="submit" value="Ok"/>
    <a href="/vol/plus">+</a>
    |
    <a href="/vol/minus">-</a>
  </p>
</form>

<p>
  <a href="/prev">«</a>
  <% if not @is_playing %>
    <a href="/play">Play</a>
  <%end%>

  <% if @is_playing %>
    <a href="/stop">Stop</a>
  <%end%>
  <a href="/pause">Pause</a>
  <a href="/next">»</a>
</p>

<ul>
  <% @playlist.each do |(id,entry,current)| %>
  <li>
    <% if current %>
      <a href="play/<%= id %>" style="color:red;" id="current">
        <%= entry %>
      </a>
    <%else%>
      <a href="play/<%= id %>"><%= entry %></a>
    <%end%>
  </li>
  <%end%>
</ul>


@@search
<p><a href="/">return to main</a></p>
<form action="/search">
  <p>
    <input type="text" name="q" value="<%=@q %>">
    <input type="submit" value="Search"/>
  </p>
</form>

<% if @result && !@result.empty? %>
<p>click a file to add (<%=@result.size%> results)</p>
<ul>
  <% @result.each do |entry| %>
  <li>
    <a href="/add/<%=add_link entry.file %>">
      <%= song_or_file entry %>
    </a>
  </li>
  <%end%>
</ul>
<%elsif (@result.nil? || @result.empty?) && @q %>
  <p style="color:red;">nothing found</p>
<%else%>
  searching for something? just type it!
<%end%>

@@error
<h1>an error occured</h1>
<p>
  maybe it's misconfigured.
</p>
<p>
  MPD to connect to at: <strong><%= @options.mpd_host %>:<%= @options.mpd_port %></strong>
</p>

<p>
  <a href="/">reload</a>
</p>
