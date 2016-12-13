require 'rest-client'
require 'uri'
class RailsAssetsForUpyun
  def self.publish(bucket, username, password, rejectpath = '', bucket_path="/", localpath='public', upyun_ap="http://v0.api.upyun.com")
    # http://stackoverflow.com/questions/357754/can-i-traverse-symlinked-directories-in-ruby-with-a-glob

    puts "version 0.2 -- Start time...#{Time.now}, reject: #{rejectpath}"
    
    last_request = nil
    duration = 1.0/20.0
    request_count = 0
    request_duration = 10
    request_maxtime = 0.0
    
    file_array = []
    
    if !rejectpath.is_a?(Regexp) && rejectpath.blank?
      file_array = Dir[File.join localpath, "**{,/*/**}/*"]
    else
      file_array = Dir[File.join localpath, "**{,/*/**}/*"].reject{|f| f[rejectpath]}
    end
    
    puts "开始上传#{file_array.count}个文件"
    progress = ProgressBar.create(:title => "上传", :starting_at => 20, :total => file_array.count)
    
    file_array.select{|f| File.file? f}.each do |file|
      url = URI.encode "/#{bucket}#{bucket_path}#{file[localpath.to_s.size + 1 .. -1]}"
      date = Time.now.httpdate

      if last_request && (Time.now.to_f - last_request) < duration
       sleep(duration)
      end
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
          response.return!(request, result, &block)
        end
      end
      if size == (file_size = File.size file)
        
      else
        file_content = File.read(file)
        

        RestClient.put("#{upyun_ap}#{url}",  file_content,{\
          Authorization: "UpYun #{username}:#{signature 'PUT', url, date, file_size, password}",
          Date: date,
          mkdir: 'true',
          Content_MD5: Digest::MD5.hexdigest(file_content),
          })
      end
      progress.increment
    end
  end
  def self.signature(method, uri, date, content_length, password)
    Digest::MD5.hexdigest "#{method}&#{uri}&#{date}&#{content_length}&#{Digest::MD5.hexdigest password}"
  end
end
