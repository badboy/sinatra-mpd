#!/usr/bin/env ruby
# encoding: utf-8

require 'sinatra/base'
require 'mustache/sinatra'
require 'mpd'

class SinatraMPD < Sinatra::Base
  register Mustache::Sinatra
  require 'views/layout'
  set :views, 'templates/'
  set :mustaches, 'views/'
  set :mpd_host, "localhost"
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
    mustache :error
  end

  get '/' do
    @title = 'Sinatra-MPD'
    @state = @mpd.status['state']
    mustache :index
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
