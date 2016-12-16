require 'rest-client'
require 'uri'

class UpyunAssetsError < StandardError

end

class RailsAssetsForUpyun

  @bucket = @bucket_path = @user_name = @password = @upyun_ap = ""

  class << self
    attr_accessor :bucket, :bucket_path, :user_name, :password, :upyun_ap
  end

  # 配置
  # Hash {
  #   bucket: "",         # bucket 名称
  #   user_name: "",      # 操作员
  #   password: "",       # 密码
  #   bucket_path: "/",   # 路径
  #   upyun_ap: ""http://v0.api.upyun.com # API地址
  # }
  def self.config(options)
    default = {
      bucket: "",
      user_name: "",
      password: "",
      bucket_path: "/",
      upyun_ap: "http://v0.api.upyun.com"
    }

    args = options.reverse_merge(default)

    default.keys.each do |k|
      raise UpyunAssetsError, "argument #{k.to_s} is blank" if args[k].blank?
    end

    self.bucket = args[:bucket]
    self.user_name = args[:user_name]
    self.password = args[:password]
    self.bucket_path = args[:bucket_path]
    self.upyun_ap = args[:upyun_ap]
  end

  # publis assets to upyun
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

  # 增量发布，比较backup_path和release_path的内容
  # 只发布修改的部分
  # params:
  #  Hash: {
  #    backup_path: ''    # 备份assets的路径
  #    release_path: ''   # 当前发布的assets的地址
  #  }
  def self.increment_publish(options)
    default = {
      backup_path: "",
      release_path: "",
    }
    args = options.reverse_merge(default)

    # 比较backup_path 和 release_path的文件，只发布修改了和release中新增的文件
    # 发布文件

    # 如果没有backup_path 则直接发布release_path中的文件
    files_pathes = Dir[File.join(args[:release_path], "**{,/*/**}/*")].select{|f| File.file?(f)}
    if args[:backup_path].blank?
      puts "全部上传"
      files_pathes.each do |file_path|
        upload_file(file_path, args[:release_path])
      end
    else
      puts "增量上传"
      files_pathes.each do |file_path|
        sub_path = file_path[args[:release_path].size .. -1]
        backup_file_path = File.join(args[:backup_path], sub_path)
        if File.exist?(backup_file_path)
          if FileUtils.compare_file(file_path, backup_file_path)
            # do nothing
          else
            # 上传
            upload_file(file_path, args[:release_path])
          end
        else
          # 上传
          upload_file(file_path, args[:release_path])
        end
      end
    end
  end

  # 检查云上是否已存在并上传
  # params:
  #   @file_path: 文件
  #   @dir: 文件目录, 这里是release_path，非完整路径
  def self.upload_file(file_path, dir)
    url = URI.encode "/#{self.bucket}#{self.bucket_path}#{file_path[dir.to_s.size + 1 .. -1]}"
    date = Time.now.httpdate

    if last_request && (Time.now.to_f - last_request) < duration
     sleep(duration)
    end
    last_request = Time.now.to_f
    size = RestClient.head("#{self.upyun_ap}#{url}", {
        Authorization: "UpYun #{self.user_name}:#{signature('HEAD', url, date, 0, self.password)}",
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
    if size == (file_size = File.size(file_path))
      # do nothing
    else
      file_content = File.read(file_path)

      RestClient.put("#{self.upyun_ap}#{url}",  file_content,{
        Authorization: "UpYun #{self.user_name}:#{signature('PUT', url, date, file_size, self.password)}",
        Date: date,
        mkdir: 'true',
        Content_MD5: Digest::MD5.hexdigest(file_content),
        })
    end
  end

  def self.signature(method, uri, date, content_length, password)
    Digest::MD5.hexdigest("#{method}&#{uri}&#{date}&#{content_length}&#{Digest::MD5.hexdigest password}")
  end
end
