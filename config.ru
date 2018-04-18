# frozen_string_literal: true

require "rubygems"
require "bundler"

Bundler.require :default, :test

Combustion.initialize! :all
run Combustion::Application
