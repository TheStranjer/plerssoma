require 'colorize'
require 'rss'
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

      rss = RSS::Parser.parse(URI.open(feeds[i]['url']).read)
      puts "\tIdentified feed title as #{rss.channel.title.cyan}"

      feeds[i]['last_time'].nil? ? new_feed(i, rss) : extant_feed(i, rss)

      @pub_times += rss.items.collect { |item| item.pubDate.to_i }
    rescue => e
      puts "Failed to acquire #{feeds[i]['url'].cyan} because #{e.message.red}"
    end
  end

  def new_feed(i, rss)
    puts "\tThis feed has never been uploaded from. Establishing a baseline"

    item = rss.items.max { |a,b| a.pubDate <=> b.pubDate }

    puts "\tThe most recent item is #{item.title.cyan}, published at #{item.pubDate.yellow}."

    feeds[i]['last_time'] = item.pubDate.to_i
  end

  def extant_feed(i, rss)
    new_items = rss.items.select { |item| item.pubDate.to_i > feeds[i]['last_time'] }

    if new_items.length == 0
      puts "\tNo new content for #{rss.channel.title.cyan}"
      return
    end

    new_items.each do |item|
      new_item(i, rss, item)
    end

    feeds[i]['last_time'] = new_items.max { |a,b| a.pubDate <=> b.pubDate }.pubDate.to_i
  end

  def new_item(i, rss, item)
    uri = URI.parse("https://#{feeds[i]['instance']}/api/v1/statuses")
    header = {
      'Authorization'=> "Bearer #{feeds[i]['bearer_token']}",
      'Content-Type' => 'application/json'
    }

    status = feeds[i]['status'].gsub("$TITLE", item.title).gsub("$URL", item.link).gsub("$PUBDATE", item.pubDate.to_s)

    req = Net::HTTP::Post.new(uri.request_uri, header)
    req.body = {
      'status'       => status,
      'source'       => 'plerssoma',
      'visibility'   => feeds[i]['visibility'] || 'public',
      'content_type' => 'text/html'
    }.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    res = http.request(req)

    puts "\tPublished new article #{item.title.green}"
  end
end

fn = ARGV.find { |x| /\.json$/i.match(x) } || "feeds.json"
puts "Opening #{fn.cyan} as feeds file"

PleRSSoma.new(fn).start
sleep 3600