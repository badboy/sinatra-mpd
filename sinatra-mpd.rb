#!/usr/bin/env ruby18
# encoding: utf-8

require 'sinatra/base'
require 'mpd'

class SinatraMPD < Sinatra::Base
  use_in_file_templates!

  set :mpd_host, "localhost"
  set :mpd_port, 6600

  before do
    if request.env['PATH_INFO'] != '/error'
      begin
        @mpd = MPD.new(options.mpd_host, options.mpd_port)
        @mpd.ping
        headers({ 'Cache-Control' => 'no-cache' })
      rescue Errno::ECONNREFUSED
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
  end

  get '/error' do
    @title = 'Sinatra-MPD | error'
    @options = options
    erb :error
  end

  get '/' do
    @title = "Sinatra-MPD @ #{options.mpd_host}"
    @state = @mpd.status['state']
    @is_playing = @state == 'play'
    @song = song_or_file(@mpd.currentsong)
    i = 0
    @playlist = @mpd.playlistinfo.map do |song|
          [ i+=1, song_or_file(song), @mpd.currentsong == song ]
    end

    erb :index
  end

  get '/play/:id' do
    id = params[:id].to_i
    unless id == 0
      id -= 1
      @mpd.play id
    end
    redirect '/'
  end

  %w[play pause stop prev next].each do |action|
    get "/#{action}" do
      @mpd.send(action)
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
  </body>
</html>

@@index
<p>np: <%= @song %></p>
<p>State: <%= @state %></p>
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
      (current)
    <%end%>
    <a href="play/<%= id %>"><%= entry %></a>
  </li>
  <%end%>
</ul>


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
