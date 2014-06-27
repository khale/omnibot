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
require 'asciiart'
require 'bing_translator'
require 'hpricot'
require 'uri'
require 'htmlentities'
require 'net/http'

# custom stuff
# for fixed-length history stack (probly a better way)
require_relative 'leakybucket'
# URL shortening
require_relative 'bitly'

# more stuff for preparing Isaac
require_relative 'vendor/utils/twitter_search'
require_relative 'vendor/utils/flickraw'

HISTORY_MAX = 10000

# hack to get PMs to work (channel var not scoped in PM events)
HOME = '#systems'

# list of channels we should join upon connecting
CHANNELS = [{ :channel => HOME }]
MEME_URL = "http://api.automeme.net/txt?lines=1"
CMD_URL  = "http://www.commandlinefu.com/commands/random/plaintext"
OPTION_STR = <<-eos
====================================================================
OMNIBOT - Command listing: PM them to omnibot, it will respond in the message
        !?                - display this message 
        !cmd              - show a random command from commandlinefu
        !meme             - generate a random meme
        !tweet: <msg>     - tweet <msg> to the NUCSystems feed
        !tweet <name>[n]  - tweet something <name> said
                            n is an index into an array containing the last n 
                            things <name> said. [0] is the most recent. omnibot
                            only has a limited memory of 10 comments (for now)
                            If <name> is not provided, it will use your nick.
        !tsearch @type @handle <msg> - search twitter for messages. type can either be
                            'from' or 'to'. msg is optional
        !log  <name>[n]   - Works like the above, but simply displays the result
        !ascii <url>      - generate ascii art from image pointed to by url
        !translate from:<lan> to:<lan> <txt> - translate text. Supported codes:
        !translate codes  - shows available language codes in PM
        !short <url>      - shorten the url
        !cowsay <text>    - cowsay some text
        !wiki <query>     - search for a wiki summary
        !stats            - print participation stats

        url shortening: omnibot will automatically shorten URLs posted in the channel
====================================================================
eos

        
# configure IRC client opts
configure do |c|
  c.nick     = 'omnibot'
  c.server   = 'fourinhand.cs.northwestern.edu'
  c.realname = 'General purpose awesome bot'
  c.port     = 6667
  c.verbose  = false
end

$logs      = { 'omnibot' => LeakyBucket.new(HISTORY_MAX) }

# bitly setup
$bitly   ||= Bitly.new

# bing translate setup 
$bing = YAML::load(File.open('bing.yaml'))
$translator ||= BingTranslator.new($bing['client_id'], $bing['client_secret'])

# twitter setup
$twitter ||= TwitterSearch::Client.new
$yml       = YAML::load(File.open('twitter.yaml'))
$client    = Twitter::REST::Client.new do |config|
        config.consumer_key        = $yml['consumer_key']
        config.consumer_secret     = $yml['consumer_secret']
        config.access_token        = $yml['oauth_token']
        config.access_token_secret = $yml['oauth_token_secret']
end


helpers do

    def get_title(url)
        doc = Hpricot(open(url))
        return (doc/'title').text.strip.split.join(" ")
    end

    def content_type_from_head(raw_uri)
        uri = URI.parse(raw_uri)
        http = Net::HTTP.new(uri.host, uri.port)
        response, data = http.head((uri.path == "" ? "/" : uri.path), nil)
        return response.content_type
    end

    def is_html?(url)
      content_type_from_head(url) =~ /text\/html/
    end

  def shorten(target, url)
      response = $bitly.shorten "longUrl" => url
  end

  def print_success(m, chan)
        msg chan, "#{color(:green)} *** #{m} #{stop_color}"
  end

  def print_error(m, nick) 
        msg nick, "#{color(:red)} *** ERROR: #{m} #{stop_color}"
  end

  def print_error_chan(m, nick, chan)
        msg chan, "#{color(:red)} *** ERROR: #{m} #{stop_color}"
  end




  def tsearch(nick, handle, m, chan, type)
      if type == "to" 
          $client.search("to:#{handle} #{m}", :result_type => "recent").take(1).collect do |tw|
              msg chan, "Most recent tweet to @#{handle} - #{tw.user.screen_name}:\"#{tw.text}\""
          end
      elsif type == "from" 
          $client.search("from:#{handle} #{m}", :result_type => "recent").take(1).collect do |tw|
              msg chan, "#{color(:green)} Most recent tweet from @#{handle} - \"#{tw.text}\" #{stop_color}"
          end
      end
  end

  def tweet(nick, m, poster, chan)
        begin
                $client.update("#{nick}: \"#{m}\"")
                print_success("#{poster} tweeted #{nick}'s message,  \"#{m}\" to @NUCSystems", chan)
        rescue
                print_error("Failed to update Twitter: #{$!}", nick)
        end
  end

  def ascii(nick, chan, url)
      begin 
          a = AsciiArt.new(url)
          s = a.to_ascii_art(width: 80)
          s.split("\n").each {|l| msg chan, l}
      rescue
          print_error_chan("#{nick} is a stupid bitch and tried to use an invalid link", nick, chan)
      end
  end

  def translate(nick, chan, from, to, txt)
    begin
        trans = $translator.translate txt , :from => from, :to => to
        msg chan, "#{nick} says in '#{to}': #{trans}"
    rescue
        print_error("could not translate", nick)
    end 
  end 


  def trans_get_codes(nick, chan)
      begin 
          codes = $translator.supported_language_codes
          msg nick, codes
      rescue
          print_error("could not get translation codes", nick)
      end
  end

  def stats(nick, chan)
      begin 
          cont = {}
          sum = 0

          $logs.keys.each do |k| 
              cont[k] = $logs[k].count
              sum += cont[k]
          end

          if sum <= 0
              return 
          end

        
          colors = [:red, :blue, :green, :yellow, :purple, :orange]
          bar_length = 50
          i = 0
          cont.keys.sort.each do |k| 
              frac = Float(cont[k])/Float(sum)
              percent = frac * 100.0
              num_dots = (frac * bar_length).to_int
              spaces = bar_length - num_dots
              line = "*"*num_dots + " "*spaces + " #{cont[k]} #{percent}% -> #{k}"
              msg chan, "#{color(colors[i])} #{line} #{stop_color}"
              i = (i+1) % 6
          end

      rescue
          print_error("error getting stats #{$!}", nick)
      end
  end

  def cowsay(nick, chan, txt)
        meme = open(MEME_URL).read.chomp rescue  print_error('could not reach AutoMeme', nick)
        url = "http://cowsay.morecode.org/say?format=text&message=#{URI.encode(txt)}"
        cow = open(url).read rescue print_error("could not reach cowsay", nick)
        cow.split("\n").each{|l| msg chan, l}
  end

end

# after connecting to the irc server, join our channels (w/keys if specified)
on :connect do
  CHANNELS.each do |channel|
    join channel[:channel] + " #{channel[:key]}"
  end
end

# look for urls in public channels, grab only the first one per line
on :channel, /^(http[s]*:\/\/\S+)/ do |url|
        $logs[nick] = LeakyBucket.new(HISTORY_MAX) if $logs[nick].nil?
        $logs[nick].push(message)
        title = ""
        begin 
            URI.extract(url, %w(http https)).each do |u|
                title = HTMLEntities.new.decode(get_title(u)) if is_html?(u)
            end
        rescue
            title = "[no title]"
        end
        u = shorten channel, url
        msg channel, "#{color(:orange)}(#{u}) #{title}"
end

on :channel, /omnibot:/ do
    msg channel, "PM me with !? for command listings"
end


on :channel do
        # ignore command strings and shortened urls
        return if message =~ /^\!/ or message =~ /url:/

        $logs[nick] = LeakyBucket.new(HISTORY_MAX) if $logs[nick].nil?
        $logs[nick].push(message)
end

# get urls from private messages, grab only the first one per line
on :private, /^\!short (http[s]*:\/\/\S+)/ do |url|
  resp = shorten channel, url
  msg nick, "#{color(:purple)} #{resp} #{stop_color}"
end

on :private, /^\!\?/ do
        OPTION_STR.split("\n").each { |s| msg nick, s }
end


on :private, /^\!meme$/i do
        meme = open(MEME_URL).read.chomp rescue  print_error('could not reach AutoMeme', nick)
        msg HOME, "#{nick}->#{meme}"
        $logs['omnibot'].push(meme)
end


on :private, /^\!wiki\s*(.*)/i do |query|
    q = query.gsub(" ", "_")
    cmd = "dig +short txt #{q}.wp.dg.cx"
    res = %x[ #{cmd} ]
    msg HOME, "#{color(:blue)}#{nick}: wiki article for #{query}:"
    msg HOME, "#{color(:blue)} #{res} #{stop_color}"
end


on :private, /^\!tsearch\s+@(\w+)\s+@(\w+)\s*(.*)/i do |type, handle, msg|
    if msg.nil?
        msg = " "
    end
    tsearch nick, handle, msg, HOME, type
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

on :private, /^\!ascii\s*(.*)/ do |url|
    ascii nick, HOME, url
end
    

# the same as above
on :private, /^\!publog\s*(\w*)\[(-?\d*)\]/ do |name, count|
        count = 0 if count.nil? or count == ""
        if name.nil? or name == ""
                if $logs[nick].nil?
                        print_error("no saved posts!", nick)
                else
                        line = $logs[nick].at(count)
                        if line.nil?
                                print_error("no saved posts!", nick)
                        else
                               msg HOME, line
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
                                msg HOME, line
                        end
                                
                end
        end
end

on :private, /^\!translate\s*from:(\w*)\s*to:(\w*)\s*(.*)/i do |fr, to,txt|
    translate nick, HOME, fr, to, txt
end

on :private, /^\!translate\s*codes/i do 
    trans_get_codes nick, HOME
end

on :private, /^!cowsay\s*(.*)/i do |txt|
    cowsay nick, HOME, txt
end

on :private, /^\!say (.*)/i do |txt|
        msg HOME, txt
end

on :private, /^\!stats$/i do 
    stats nick, HOME
end

on :private, /^\!cmd$/i do 
        cmd = open(CMD_URL).read
        cmd.split("\n").last(2).each {|l| msg HOME, l}
        $logs['omnibot'].push(cmd)
end
