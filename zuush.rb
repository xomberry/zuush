require 'sinatra/base'
require 'sqlite3'
require 'fileutils'
require_relative 'rack_cp_fix'
require_relative 'meow'

class Zuush < Sinatra::Application
  Dir.chdir __dir__
  FileUtils.mkpath 'files'
  FileUtils.mkpath 'db'
  FileUtils.mkpath 'public'

  DB = SQLite3::Database.new 'db/quu.db', results_as_hash: true
  DB.execute <<-SQL
    create table if not exists ShortLinks (
      short  text primary key not null,
      long   text not null,
      key    text not null,
      ts     text not null,
      id_num int not null,
      url    text not null,
      hits   int not null default 0
    );
  SQL
    
  set bind: '0.0.0.0', port: 80, static: false, threaded: false
  
  post '/api/up' do
    upload
  end
  
  post '/api/hist' do
    k = request.POST['k']
    return 400 if k.nil?
    
    response = ['0']
    DB.execute "select id_num, ts, url, long, hits from ShortLinks where Key = ? order by TS desc limit 10", k do |row|
      response += row.values.join ','
    end
    response.join "\n"
  end
  
  get '/f/:key/*' do |key, shortlink|
    uploaded_file(shortlink[/[A-Za-zА-Яа-я_]*/], key)
  end

  get '/f/*' do |shortlink|
    uploaded_file(shortlink[/[A-Za-zА-Яа-я_]*/])
  end
  
  get '/twp' do
    erb :twp, locals: {port: '6688'}
  end

  get '/twp/test' do
    erb :twp, locals: {port: '4525'}
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
    row = DB.execute('select key, long from ShortLinks where short = ? limit 1', shortlink)[0]
    return not_found if row.nil?

    file_key = row['key']
    return 403 if file_key && key != file_key

    long = row['long']
    path = "files/#{long}"
    DB.execute 'update shortlinks set hits = hits + 1 where short = ?', shortlink
    
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
    
    num = DB.execute('select count(*) as num from ShortLinks')[0]['num']
    shortlink = num2word(num)
    ext = File.extname(filename)
    key = num2word(rand(1_000..9999)).gsub(/./) {|ch| [ch.tr('aehilost', '43411057'), ch.upcase, ch].sample}
    client_ip = request.ip
    host = 'zuush.tk'
    
    url = "http://#{host}/f/#{key}/#{shortlink+ext}"

    DB.execute 'insert into ShortLinks (short, long, key, k, ts, id_num, url) values (?, ?, ?, ?, ?, ?, ?)', [shortlink, filename, key, k, Time.now.to_s, num, url]
    
    "0,#{url},0,0"
  end
end

Zuush.run!
