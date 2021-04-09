require 'colorize'
require 'feedjira'
require 'open-uri'
require 'json'
require 'syndesmos'
require 'time'

class PleRSSoma
  attr_accessor :feeds, :fn, :pub_times, :multiplier

  def initialize(fn)
    @fn = fn
    @feeds = JSON.parse(File.open(fn, "r").read)
    @multiplier = 1.0
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
      wait_time *= multiplier
      puts "Waiting until #{Time.at(Time.now.to_i + wait_time).strftime("%I:%M %p").yellow} (#{wait_time.yellow}s)"
      sleep wait_time

      @multiplier += 0.25
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
    syn = Syndesmos.new(bearer_token: feeds[i]['bearer_token'], instance: feeds[i]['instance'])

    status = feeds[i]['status'].gsub("$TITLE", entry.title.to_s).gsub("$URL", entry.url.to_s).gsub("$PUBLISHED", entry.published.to_s).gsub("$DESC", entry.summary.to_s)

    syn.statuses({
      'status'       => status,
      'source'       => 'plefeedoma',
      'visibility'   => feeds[i]['visibility'] || 'public',
      'content_type' => 'text/html'
    })

    puts "\tPublished new article #{entry.title.green}"

    @multiplier = 1
  end
end

module Feedjira
  module Parser
    module GitHub
      class RepositoryEventEntry
        include FeedEntryUtilities

        attr_reader :json, :entry_id, :url, :external_url, :title, :content, :summary,
                    :published, :updated, :image, :banner_image, :author, :categories,
                    :title

        def initialize(event, title)
          @json = json
          @title = "Repository: #{title}"
          @published = Time.parse(event[:created_at])

          send("initialize_#{event_type(event)}".to_sym, event)
        end

        private

        def initialize_push_event(event)
          @entry_id = "PUSH:#{event[:payload][:push_id]}"
          content = event[:payload][:commits].collect { |c| { 
            :url     => "https://github.com/#{title}/commit/#{c[:sha]}",
            :author  => c[:author][:name],
            :message => c[:message]
          } }

          @summary = "<div>The following commits were pushed:</div><ul>#{content.collect { |c| "<li><a href=\"#{c[:url]}\">#{c[:message]}</a> by #{c[:author]}</li>" }.join('')}</ul>"
        end

        def initialize_create_event(event)
          @entry_id = "CREATE:#{event['']}"
          @summary = "Created <a href=\"https://github.com/#{title}/\">#{title}</a>"
        end

        def event_type(event)
          event[:type]
            .gsub(/^([A-Z])/) { |l| l.downcase }
            .gsub(/([^A-Z])([A-Z])/) { |c| "#{c[0]}_#{c[1].downcase}" }
        end
      end

      class RepositoryEventPublisher
        include SAXMachine
        include FeedUtilities

        element :title
        element :link, :as => :url
        element :description

        elements :item, :as => :entries, :class => GitHub::RepositoryEventEntry

        attr_accessor :feed_url

        attr_reader :json, :version, :title, :url, :feed_url, :description, :entries

        def initialize(json)
          @json = json
          @version = "1.0"
          @title = json.first[:repo][:name]
          @url = "https://github.com/#{title}"
          @feed_url = json.first[:repo][:url]
          @description = json.select { |el| el[:type] == "CreateEvent" }.sort { |el| Time.parse(el[:created_at]).to_i }.first[:description]

          @entries = json.collect { |ev| GitHub::RepositoryEventEntry.new(ev, title) }
        end

        def self.parse(json)
          new(JSON.parse(json, symbolize_names: true))
        end

        def self.able_to_parse?(json)
          /api\.github\.com/.match(json) ? true : false
        end
      end
    end
  end
end

Feedjira.configure do |config|
  config.parsers += [
    Feedjira::Parser::GitHub::RepositoryEventPublisher
  ]
end

fn = ARGV.find { |x| /\.json$/i.match(x) } || "feeds.json"
puts "Opening #{fn.cyan} as feeds file"

PleRSSoma.new(fn).start