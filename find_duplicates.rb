require 'faraday'
require 'json'

require_relative 'config'


connection_config = defined?(FARADAY_CONFIG) ? FARADAY_CONFIG : {}
connection = Faraday.new 'https://www.strava.com', connection_config

res = connection.post('/oauth/token', client_id: CLIENT_ID, client_secret: CLIENT_SECRET, code: AUTHORIZATION_CODE, grant_type: 'authorization_code')

data = JSON.parse(res.body)
puts JSON.pretty_generate(data)
access_token = data.fetch('access_token')

AUTHORIZATION = "Bearer #{access_token}"


ACTIVITY_DIR = 'activities'
Dir.mkdir(ACTIVITY_DIR) unless Dir.exist?(ACTIVITY_DIR)
ACTIVITY_INDEX = File.join(ACTIVITY_DIR, 'index')

def list_activities(connection)
  return enum_for(:list_activities, connection) unless block_given?

  known_ids = []
  page = 0
  loop do
    page += 1
    res = connection.get('/api/v3/athlete/activities', { page: page, per_page: 200 }, { authorization: AUTHORIZATION } )
    if res.status != 200
      raise "code: #{res.status}, #{res.body}"
    end
    data = JSON.parse(res.body)
    break if data.empty?
    
    data.map { |d| d.fetch('id') }.each do |id|
      known_ids.push id
      yield id
    end
  end
  File.write(ACTIVITY_INDEX, JSON.pretty_generate(known_ids))
end

def get_activity_detail(connection, activity_id)
  activity_file = File.join(ACTIVITY_DIR, activity_id.to_s)
  if File.exist?(activity_file)
    return JSON.parse(File.read(activity_file))
  end
  res = connection.get("/api/v3/activities/#{activity_id}",  {}, { authorization: AUTHORIZATION })
  if res.status != 200
    raise "code: #{res.status}, #{res.body}"
  end
  activity_detail = JSON.parse(res.body)
  File.write(
    activity_file,
    JSON.pretty_generate(activity_detail)
  )
  activity_detail
end
  
def show_device_name(activity_detail)
  activity_id = activity_detail.fetch('id')
  puts "activity_id: #{activity_id}, device_name: #{activity_detail['device_name']}"
end

  
#list_activities(connection) do |activity_id|
#  activity_detail = get_activity_detail(connection, activity_id)
#  begin
#    show_device_name(activity_detail)
#  rescue => e
#    puts "#{e.class}: #{e.message}"
#    puts "skipping #{activity_id}"
#  end
#end

require 'time'

def start_time(activity)
 Time.iso8601(activity.fetch('start_date'))
end

all_activities = list_activities(connection).map{ |id| get_activity_detail(connection, id) }.sort_by { |a| start_time(a) }
possible_duplicates = all_activities.each_cons(2).select do |a1, a2|
  s1 = start_time(a1)
  s2 = start_time(a2)
  (s1 - s2).abs < 5 * 60
end

def activity_url(id, open_browser = true)
  url = "https://www.strava.com/activities/#{id}"
  system "cmd /C start #{url}" if open_browser
  url
end

puts "#{possible_duplicates.size} possible duplicates found:"
possible_duplicates.each do |a1, a2|
  if (a1['distance'].to_f - a2['distance'].to_f).abs < 1_000
    g = [a1, a2].select{ |a| a['device_name'].include?('800') }
    if g.any?
      puts "delete #{activity_url(g.first.fetch('id'), true)}"
      next
    end
  end
  puts "possible duplicate #{activity_url(a1.fetch('id'))} - #{activity_url(a2.fetch('id'))}"
end
