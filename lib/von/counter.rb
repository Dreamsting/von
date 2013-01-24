module Von
  class Counter
    CHILD_REGEX  = /:[^:]+\z/
    PARENT_REGEX = /:?[^:]+\z/

    def initialize(field)
      @field = field.to_sym
    end

    def options
      @options ||= Von.config.counter_options(@field)
    end

    def periods
      @periods ||= options.select { |k|
        Period::AVAILABLE_PERIODS.include?(k)
      }.inject({}) { |h, (p, l)| h[p] = Period.new(@field, p, l); h }
    end

    def hash
      @hash ||= "#{Von.config.namespace}:#{@field}"
    end

    def increment(field = 'total')
      if field.is_a?(Period)
        increment_period(field)
      else
        Von.connection.hincrby(hash, field, 1)
        increment_parents
      end
    end

    def increment_period(period)
      Von.connection.hincrby(period.hash, period.field, 1)
      unless Von.connection.lrange(period.list, 0, -1).include?(period.field)
        Von.connection.rpush(period.list, period.field)
      end

      if Von.connection.llen(period.list) > period.length
        expired_counter = Von.connection.lpop(period.list)
        Von.connection.hdel(period.hash, expired_counter)
      end
    end

    def increment_parents
      field = @field.to_s
      return if field !~ CHILD_REGEX

      parents = field.sub(CHILD_REGEX, '')

      until parents.empty? do
        Von.connection.hincrby("#{Von.config.namespace}:#{parents}", 'total', 1)
        parents.sub!(PARENT_REGEX, '')
      end
    end

    def count(period)
      if period.nil?
        Von.connection.hget(hash, 'total')
      else
        _count   = []
        _period  = periods[period]
        now      = DateTime.now.beginning_of_hour

        _period.length.times do
          this_period = now.strftime(_period.format)
          _count.unshift(this_period)
          now = _period.hours? ? now.ago(3600) : now.send(:"prev_#{_period.time_unit}")
        end

        keys = Von.connection.hgetall("#{hash}:#{period}")
        _count.map { |date| { date => keys.fetch(date, 0) }}
      end
    end

  end
end