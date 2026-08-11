module TRINH_VAN_PHUC
  module ViewUI
    FILENAMESPACE = File.basename(__FILE__, ".*")
    PATH_ROOT = File.dirname(__FILE__).freeze
    PATH = File.join(PATH_ROOT, FILENAMESPACE).freeze
    Sketchup.require("#{PATH_ROOT}/item")
    Sketchup.require("#{PATH_ROOT}/button")
    Sketchup.require("#{PATH_ROOT}/checkbox")
    Sketchup.require("#{PATH_ROOT}/toggle")
    Sketchup.require("#{PATH_ROOT}/slider")
  end
end
