class Bitly
        include HTTParty
        include YAML
        attr_accessor :api_key, :login

        def initialize
                yml = YAML::load(File.open('bitly.yaml'))
                @login = yml['login']
                @api_key = yml['api_key']
        end

        def shorten options = {}
                params = {"apiKey" => @api_key, "login" => @login, "format" => "txt"}.merge options
                HTTParty::get("http://api.bitly.com/v3/shorten", :query =>params).chomp
        end
end
