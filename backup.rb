require 'twitter'
require 'json'
require 'yaml'
require 'pg'
require 'logger'

class Timeline
  def initialize
    # Load configuration for user specified as the first command line parameter.
    # Default to user "default" if no parameters were given.
    conf = YAML.load_file("users.yml")[ARGV[0] || "default"]
    auth = conf["auth"]

    # Init twitter client
    @client = Twitter::REST::Client.new do |config|
      config.consumer_key        = auth["consumer_key"]
      config.consumer_secret     = auth["consumer_secret"]
      config.access_token        = auth["access_token"]
      config.access_token_secret = auth["access_token_secret"]
    end

    @db = PG.connect(conf["db"])

    @user = @client.user

    @log = Logger.new(STDOUT)
    @log.level = Logger::INFO
    @log.info "Getting tweets for #{@user.name}"
  end

  def get
    # Get the id of the most recent tweet stored
    since_id = @db.exec("SELECT MAX(id) FROM tweets")[0]["max"].to_i

    if since_id.zero?
      @log.info "Getting tweets since the beginning of time."
      @since = {}
    else
      @log.info "Getting tweets since ID #{since_id}"
      @since = { since_id: since_id }
    end

    # Get all tweets
    @tweets = (get_user_timeline + get_mentions_timeline + get_favorites).uniq { |t| t.id }
    @tweets = @tweets + get_tweets_replied_to

    @log.info "Got #{@tweets.size} unique tweets."
  end

  def dump
    # Dump all tweets in db
    @db.prepare('put_tweet', 'INSERT INTO tweets(id, u_id, data) VALUES ($1, $2, $3)')

    @log.info "Dumping #{@tweets.size} tweets to db."

    @tweets.each do |t|
      begin
        @db.exec_prepared('put_tweet', [t.id, t.user.id, t.attrs.to_json])
      rescue PG::UniqueViolation
        @log.error "Tweet #{t.id} already exists in database. Skipping."
      end
    end
  end

  def get_tweets_replied_to
    # Get tweets that I have replied to that are not already in my mentions or
    # favorites. Only works for the last 50 tweets that were replies to other
    # tweets because of rate limits.
    tweets = []

    # Only include those tweets that are my replies & haven't already been
    # fetched in the mentions / favorites timeline.
    replies = @tweets.select do |t|
      t.in_reply_to_status_id &&
        t.user.id == @user.id &&
        !@tweets.index { |x| x.id == t.in_reply_to_status_id }
    end

    # Get the replied to tweets one by one, wait if nessecary.
    replies.each do |t|
      begin
        tweets.push(@client.status(t.in_reply_to_status_id))
      rescue Twitter::Error::TooManyRequests => error
        @log.error "Hit rate limit, trying again in #{error.rate_limit.reset_in}s."
        sleep error.rate_limit.reset_in
        retry
      rescue => e
        @log.error "Couldn't get tweet #{t.in_reply_to_status_id} from User ##{t.in_reply_to_user_id} due to #{e}."
      end
    end

    tweets.uniq! { |t| t.id }

    @log.info "Got #{tweets.size} unique tweets that were replied to."

    tweets
  end

  def self.def_getter(method)
    define_method("get_#{method}") do
      # Traverse a timeline (mentions, user or favorites).
      # Gets entire timeline unless @since is defined.
      page, max_id = [], 0
      default_params = { :count => 200, :include_rts => 1 }.merge(@since)

      begin
        tweets = @client.send(method, default_params) # Get initial list of tweets

        while (page.size != 1 && !tweets.empty?)
          max_id = tweets.last.id # Sentinel
          params = default_params.merge({ :max_id => max_id })

          page = @client.send(method, params)

          tweets += page
        end
      rescue Twitter::Error::TooManyRequests => error
        @log.error "Hit rate limit, trying again in #{error.rate_limit.reset_in}."
        sleep error.rate_limit.reset_in
        retry
      end

      @log.info "Got #{tweets.size} tweets from #{method}"
      tweets
    end
  end

  %w{ mentions_timeline user_timeline favorites }.each do |m|
    # Define methods get_user_timeline, get_mentions_timeline & get_favorites
    def_getter(m)
  end
end

t = Timeline.new
t.get
t.dump
