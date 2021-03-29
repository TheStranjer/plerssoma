require 'colorize'
require 'feedjira'
require 'open-uri'
require 'json'

class PleRSSoma
  attr_accessor :feeds, :fn, :pub_times

  def initialize(fn)
    @fn = fn
    @feeds = JSON.parse(File.open(fn, "r").read)
  end

  def start
    while true
      @pub_times = []
      feeds.length.times { |i| run_feed(i) }

      f = File.open(fn, "w")
      f.write(JSON.pretty_generate(feeds))
      f.close

      pub_times.sort!

      distances = pub_times.each_with_index.collect { |time,idx| pub_times[idx+1].nil? ? Float::INFINITY : pub_times[idx+1] - pub_times[idx] }
      distances.reject! { |d| d <= 0 }
      wait_time = pub_times.length > 1 ? distances.min : 3600
      puts "Waiting until #{Time.at(Time.now.to_i + wait_time).strftime("%I:%M %p").yellow} (#{wait_time.yellow}s)"
      sleep wait_time
    end
  end

  private

  def run_feed(i)
    begin
      puts "Attempting to read #{feeds[i]['url'].cyan}..."

      feed = Feedjira.parse(URI.open(feeds[i]['url']).read)
      puts "\tIdentified feed title as #{feed.title.cyan}"

      feeds[i]['last_time'].nil? ? new_feed(i, feed) : extant_feed(i, feed)

      @pub_times += feed.entries.collect { |entry| entry.published.to_i }
    rescue => e
      puts "Failed to acquire #{feeds[i]['url'].cyan} with error type #{e.class.red} because #{e.message.red}"
    end
  end

  def new_feed(i, feed)
    puts "\tThis feed has never been uploaded from. Establishing a baseline"

    entry = feed.entries.max { |a,b| a.published <=> b.published }

    puts "\tThe most recent entry is #{entry.title.cyan}, published at #{entry.published.yellow}."

    feeds[i]['last_time'] = entry.published.to_i
  end

  def extant_feed(i, feed)
    new_entries = feed.entries.select { |entry| entry.published.to_i > feeds[i]['last_time'] }

    if new_entries.length == 0
      puts "\tNo new content for #{feed.title.cyan}"
      return
    end

    new_entries.each do |entry|
      new_item(i, feed, entry)
    end

    feeds[i]['last_time'] = new_entries.max { |a,b| a.published <=> b.published }.published.to_i
  end

  def new_item(i, feed, entry)
    uri = URI.parse("https://#{feeds[i]['instance']}/api/v1/statuses")
    header = {
      'Authorization'=> "Bearer #{feeds[i]['bearer_token']}",
      'Content-Type' => 'application/json'
    }

    status = feeds[i]['status'].gsub("$TITLE", entry.title).gsub("$URL", entry.url).gsub("$published", entry.published.to_s).gsub("$DESC", entry.summary)

    req = Net::HTTP::Post.new(uri.request_uri, header)
    req.body = {
      'status'       => status,
      'source'       => 'plefeedoma',
      'visibility'   => feeds[i]['visibility'] || 'public',
      'content_type' => 'text/html'
    }.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    res = http.request(req)

    puts "\tPublished new article #{entry.title.green}"
  end
end

fn = ARGV.find { |x| /\.json$/i.match(x) } || "feeds.json"
puts "Opening #{fn.cyan} as feeds file"

PleRSSoma.new(fn).start
sleep 3600