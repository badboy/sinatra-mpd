#!/usr/bin/env ruby
# encoding: utf-8

require 'haml'
require 'mpd'

class SinatraMPD < Sinatra::Base
  set :root, File.dirname(__FILE__)

  set :mpd_host, 'localhost'
  set :mpd_port, 6600

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
  end

  get '/error' do
    @title = 'Sinatra-MPD | error'
    @options = options
    haml :error
  end

  get '/' do
    @title = 'Sinatra-MPD'
    @state = @mpd.status['state']
    @is_playing = @state == 'play'
    @song = song_or_file(@mpd.currentsong)
    i = 0
    @playlist = @mpd.playlistinfo.map do |song|
          [ i+=1, song_or_file(song), @mpd.currentsong == song ]
    end

    haml :index
  end

  get '/play/:id' do
    id = params[:id].to_i
    unless id == 0
      id -= 1
      control_mpd(:play, id)
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
