class LeakyBucket
        attr_accessor :maxlen, :a
        
        def count
                @a.count
        end

        def push(elm)
                if @a.count < @maxlen
                        @a.unshift(elm)
                else
                        @a.pop
                        @a.unshift(elm)
                end
        end

        def at(i)
                c = i.to_i
                if c <= 0
                        @a.first
                elsif c >= @maxlen
                        @a.last
                else
                        if @a[c].nil?
                                @a.last
                        else
                                @a[c]
                        end
                end
        end

        def initialize(len)
                @maxlen = len
                @a = []
        end
end
