require 'bundler/setup'
require './textease.rb'

configure do
  set :environment, :test
end

run Rack::URLMap.new "/" => TextEase.new