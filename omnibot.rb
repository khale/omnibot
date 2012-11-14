#!/usr/bin/env ruby

require 'rubygems'
require 'twitter'
require 'isaac'
require 'isaac-formatting'
require 'httparty'
require 'time'
require 'open-uri'
require 'json'
require 'yaml'

# custom stuff
# for fixed-length history stack (probly a better way)
require 'leakybucket'
# URL shortening
require 'bitly'

HISTORY_MAX = 20

# hack to get PMs to work (channel var not scoped in PM events)
HOME = '#systems'

# list of channels we should join upon connecting
CHANNELS = [{ :channel => HOME }]

OPTION_STR = <<-eos
====================================================================
OMNIBOT - Command listing:
        !?                - display this message 
        !hipster          - generate a random hipster quote
        !meme             - generate a random meme
        !tweet: <msg>     - tweet <msg> to the NUCSystems feed
        !tweet <name>[n]  - tweet something <name> said
                            n is an index into an array containing the last n 
                            things <name> said. [0] is the most recent. omnibot
                            only has a limited memory of 10 comments (for now)
                            If <name> is not provided, it will use your nick.
        !log  <name>[n]   - Works like the above, but simply displays the result

        url shortening: omnibot will automatically shorten URLs posted in the channel
====================================================================
eos

# more stuff for preparing Isaac
%w{/vendor /vendor/utils}.collect{|dir| $:.unshift File.dirname(__FILE__)+dir}
%w{twitter_search flickraw}.collect{ |lib| require(lib).to_s }
        
# configure IRC client opts
configure do |c|
  c.nick     = 'omnibot'
  c.server   = 'fourinhand.cs.northwestern.edu'
  c.realname = 'General purpose awesome bot'
  c.port     = 6667
  c.verbose  = true
end

$twitter ||= TwitterSearch::Client.new
$logs      = { 'omnibot' => LeakyBucket.new(HISTORY_MAX) }
$bitly   ||= Bitly.new

$yml       = YAML::load(File.open('twitter.yaml'))
$client  ||= Twitter::Client.new(
        :consumer_key       => $yml['consumer_key'],
        :consumer_secret    => $yml['consumer_secret'],
        :oauth_token        => $yml['oauth_token'],
        :oauth_token_secret => $yml['oauth_token_secret']
)


helpers do
  def shorten(target, url)
      response = $bitly.shorten "longUrl" => url
  end

  def print_success(m, chan)
        msg chan, "#{color(:green)} *** #{m} #{stop_color}"
  end

  def print_error(m, nick) 
        msg nick, "#{color(:red)} *** ERROR: #{m} #{stop_color}"
  end

  def tweet(nick, m, poster, chan)
        begin
                $client.update("#{nick}: \"#{m}\"")
                print_success("#{poster} tweeted #{nick}'s message,  \"#{m}\" to @NUCSystems", chan)
        rescue
                print_error("Failed to update Twitter: #{$!}", nick)
        end
  end
end

# after connecting to the irc server, join our channels (w/keys if specified)
on :connect do
  CHANNELS.each do |channel|
    join channel[:channel] + " #{channel[:key]}"
  end
end

# look for urls in public channels, grab only the first one per line
on :channel, /(http[s]*:\/\/\S+)/ do |url|
  resp = shorten channel, url
  msg channel, "#{color(:purple)} url: #{resp} #{stop_color}"
  $logs[nick] = LeakyBucket.new(HISTORY_MAX) if $logs[nick].nil?
  $logs[nick].push(message)
end

on :channel, /omnibot:/ do |resp|
    msg channel, "PM me wit !? for command listings"
end

on :channel do
        # ignore command strings and shortened urls
        return if message =~ /^\!/ or message =~ /url:/

        $logs[nick] = LeakyBucket.new(HISTORY_MAX) if $logs[nick].nil?
        $logs[nick].push(message)
end

# get urls from private messages, grab only the first one per line
on :private, /(http[s]*:\/\/\S+)/ do |url|
  resp = shorten channel, url
  msg nick, "#{color(:purple)} #{resp} #{stop_color}"
end

on :private, /^\!\?/ do
        OPTION_STR.split("\n").each { |s| msg nick, s }
end

on :private, /^\!hipster$/i do
        meme = open("http://meme.boxofjunk.ws/moar.txt?lines=1&vocab=hipster").read.chomp rescue print_error('could not reach Automeme', 1, nick)
        msg HOME, "#{nick}->#{meme}"
        $logs['omnibot'].push(meme)
end

on :private, /^\!meme$/i do
        meme = open("http://meme.boxofjunk.ws/moar.txt?lines=1").read.chomp rescue  print_error('could not reach AutoMeme', 1, nick)
        msg HOME, "#{nick}->#{meme}"
        $logs['omnibot'].push(meme)
end

on :private, /^\!tweet\s*:\s*(.*)/i do |t|
        tweet nick, t, nick, HOME
end

on :private, /^\!tweet\s*(\w*)\[(-?\d*)\]/i do |name, count|
        count = 0 if count.nil? or count == ""

        # if no name was provided, use the poster's nick
        if name.nil? or name == ""
                if $logs[nick].nil?
                        print_error("no saved posts!", 1, nick)
                else
                        line = $logs[nick].at(count)
                        if line.nil?
                                print_error("no saved posts!", nick)
                        else
                                tweet nick, line, nick, HOME
                        end
                end
        else
        # we've been provided a nick to look for
                if $logs[name].nil?
                        print_error("no saved posts!", nick)
                else
                        line = $logs[name].at(count)
                        if line.nil?
                                print_error("no saved posts!", nick)
                        else
                                tweet name, line, nick, HOME
                        end
                end
        end
end

# the same as above
on :private, /^\!log\s*(\w*)\[(-?\d*)\]/ do |name, count|
        count = 0 if count.nil? or count == ""
        if name.nil? or name == ""
                if $logs[nick].nil?
                        print_error("no saved posts!", nick)
                else
                        line = $logs[nick].at(count)
                        if line.nil?
                                print_error("no saved posts!", nick)
                        else
                                msg nick, line
                        end
                end
        else
                if $logs[name].nil?
                        print_error("no saved posts!", nick)
                else
                        line = $logs[name].at(count)
                        if line.nil?
                                print_error("no saved posts!", nick)
                        else
                                msg nick, line
                        end
                                
                end
        end
end

