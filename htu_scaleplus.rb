require 'sketchup.rb'
require 'extensions.rb'

module TRINH_VAN_PHUC
  module HTU_ScalePlus
    PLUGIN = self
    PLUGIN_NAMESPACE = 'HTU'.freeze
    PLUGIN_ID = 'ScalePlus'.freeze
    PLUGIN_NAME = 'HTU ScalePlus'.freeze
    AUTHOR = 'Trinh Van Phuc'.freeze
    PLUGIN_VERSION = '1.2.2'.freeze
    PATH_ROOT = File.dirname(__FILE__).freeze
    PATH = File.join(PATH_ROOT, 'htu_scaleplus').freeze
    unless file_loaded?(__FILE__)
      ex = SketchupExtension.new(PLUGIN_NAME, File.join(PATH, 'loader'))
      ex.version = PLUGIN_VERSION
      ex.creator = AUTHOR
      ex.description = PLUGIN_NAME
      Sketchup.register_extension(ex, true)
      PLUGIN_EX = ex
    end
  end
end
file_loaded(__FILE__)
