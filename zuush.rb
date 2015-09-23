require 'sinatra'

get '/' do
  "<h1>Мявкалка трясется!</h1>"
end

not_found do
  "<h1>404</h1>"
end
