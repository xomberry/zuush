require 'sinatra/base'
require 'data_mapper'
require 'fileutils'
require_relative 'rack_cp_fix'
require_relative 'meow'

class Zuush < Sinatra::Application
  HOST = "zuush.tk"

  Dir.chdir __dir__
  FileUtils.mkpath 'files'
  FileUtils.mkpath 'db'
  FileUtils.mkpath 'public'

  DataMapper.setup(:default, "sqlite://#{__dir__}/db/zuu.db")

  class UploadedFile
    include DataMapper::Resource

    property :id,             Serial
    property :file_name,      String, unique: true
    property :short_link,     String, unique: true
    property :short_link_key, String
    property :user_key,       String
    property :timestamp,      Time
    property :url,            String, format: :url
    property :hits,           Integer, required: true, default: 0

    Lock = Mutex.new
  end

  DataMapper.finalize
  DataMapper.auto_upgrade!    


  set bind: '0.0.0.0', port: 80, static: false, threaded: false
  
  post '/api/up' do
    upload
  end
  
  post '/api/hist' do
    k = request.POST['k']
    return 400 if k.nil?
    
    response = ["0"]
    last_10_uploads = UploadedFile.all(user_key: k, limit: 10, order: [:timestamp.desc])
    last_10_uploads.each do |file|
      response << "#{file.id},#{file.timestamp},#{file.url},#{file.file_name},#{file.hits}"
    end
    response.join "\n"
  end
  
  get '/f/:key/*' do |key, shortlink|
    uploaded_file(shortlink[/[A-Za-zА-Яа-я_]*/], key)
  end

  get '/f/*' do |shortlink|
    uploaded_file(shortlink[/[A-Za-zА-Яа-я_]*/])
  end
  
  get '/meow/get' do
    Meow.phrase
  end
  
  get '/' do
    logger.info request.ip
    file_response 'public/index.html'
  end

  get '/*' do |path|
    file_response "public/#{path}"
  end

  error 400 do
    '<h1>Bad request</h1>'
  end

  error 403 do
    '<h1>Forbidden</h1>'
  end

  not_found do
    '<h1>Not Found</h1>'
  end

  def file_response(path)
    return 404 unless File.exists?(path)
    last_modified File.mtime(path)
    send_file path, filename: File.basename(path), disposition: :inline
  end
  
  def uploaded_file(shortlink, key = nil)
    logger.info shortlink

    file = UploadedFile.first(short_link: shortlink)
    return not_found if file.nil?

    return 403 if file.short_link_key && key != file.short_link_key

    path = "files/#{file.file_name}"
    file.hits += 1
    file.save
    
    file_response(path)
  end
  
  def num2word(number)
    beginning = %w[al in con ex de com per pro ac dis ad ar or ma na si un at pre]
    core = %w[di ti be to ar ma na si mon col ten fac]
    ending = %w[ing er ly es on y an ty ry ment ble ture tive ness]
    
    number, mod = number.divmod(ending.count)
    word_ending = ending[mod]
    
    number, mod = number.divmod(beginning.count)
    word_beginning = beginning[mod]
    
    word_core = ""
    until number == 0
      number, mod = number.divmod(core.count)
      word_core << core[mod]
    end
    
    word_beginning + word_core + word_ending
  end

  def upload
    return 400 unless request.post? and request.form_data?

    f = request.POST['f']
    k = request.POST['k']
    return 400 if f.nil? || k.nil?

    filename = f[:filename]
    logger.info k
    tempfile = f[:tempfile]
    return 400 if filename.nil? or tempfile.nil?
    
    FileUtils.copy tempfile.path, "files/#{filename}"
    tempfile.delete

    file = UploadedFile.new
    UploadedFile::Lock.synchronize do
      file.short_link = num2word(UploadedFile.count)
      file.file_name = filename
      file.short_link_key = num2word(rand(1_000..9_999)).gsub(/./) {|ch| [ch.tr('aehilost', '43411057'), ch.upcase, ch].sample}
      file.user_key = k
      file.timestamp = Time.now
      ext = File.extname(filename)
      file.url = "http://#{HOST}/f/#{file.short_link_key}/#{file.short_link+ext}"
      file.save
    end

    "0,#{file.url},0,0"
  end
end

Zuush.run!
