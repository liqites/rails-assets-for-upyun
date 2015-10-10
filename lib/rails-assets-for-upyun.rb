require 'rest-client'
require 'uri'
class RailsAssetsForUpyun
  def self.publish(bucket, username, password, bucket_path="/", localpath='public', upyun_ap="http://v0.api.upyun.com")
    # http://stackoverflow.com/questions/357754/can-i-traverse-symlinked-directories-in-ruby-with-a-glob

    puts "version 0.2 -- Start time...#{Time.now}"
    last_request = nil
    duration = 1.0/20.0
    request_count = 0
    request_duration = 10
    request_maxtime = 0.0
    Dir[File.join localpath, "**{,/*/**}/*"].select{|f| File.file? f}.each do |file|
      url = URI.encode "/#{bucket}#{bucket_path}#{file[localpath.to_s.size + 1 .. -1]}"
      date = Time.now.httpdate

      # add to avoid too many request error for upyun
      #puts "-------------#{(Time.now.to_f - last_request)} is need sleep ? :#{(Time.now.to_f - last_request) < duration}" if last_request
      if last_request && (Time.now.to_f - last_request) < duration
       puts "----------sleep(#{duration})----------"
       sleep(duration)
      end
      # if request_count > request_duration
      #   puts "--------#{request_maxtime/request_count}----------"
      #   request_count = 0
      #   request_maxtime = 0.0
      # end
      # request_maxtime = request_maxtime + (Time.now.to_f - last_request) if last_request
      # request_count = request_count + 1
      last_request = Time.now.to_f
      size = RestClient.head("#{upyun_ap}#{url}", {\
          Authorization: "UpYun #{username}:#{signature 'HEAD', url, date, 0, password}",
          Date: date}) do |response, request, result, &block|
        case response.code
        when 200
          response.headers[:x_upyun_file_size].to_i
        when 404
          "non-exists"
        else
          # puts "--------end #{request_maxtime/request_count}----------"
          puts "End time...#{Time.now}"
          response.return!(request, result, &block)
        end
      end
      if size == (file_size = File.size file)
        puts "skipping #{file}.."
      else
        file_content = File.read(file)
        puts "uploading #{size} => #{file_size} #{file}.."

        RestClient.put("#{upyun_ap}#{url}",  file_content,{\
          Authorization: "UpYun #{username}:#{signature 'PUT', url, date, file_size, password}",
          Date: date,
          mkdir: 'true',
          Content_MD5: Digest::MD5.hexdigest(file_content),
          })
      end
    end
  end
  def self.signature(method, uri, date, content_length, password)
    Digest::MD5.hexdigest "#{method}&#{uri}&#{date}&#{content_length}&#{Digest::MD5.hexdigest password}"
  end
end
