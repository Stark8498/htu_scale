module TRINH_VAN_PHUC::HTU_ScalePlus
  module RadialMenu
    Sketchup.require("#{PATH}/radial_menu/constants")
    Sketchup.require("#{PATH}/radial_menu/shape_geom")
    Sketchup.require("#{PATH}/radial_menu/menu")
    Sketchup.require("#{PATH}/radial_menu/item")
    Sketchup.require("#{PATH}/radial_menu/layout")
    Sketchup.require("#{PATH}/radial_menu/circle_layout")
    Sketchup.require("#{PATH}/radial_menu/rectangle_layout")
    Sketchup.require("#{PATH}/radial_menu/command")
    Sketchup.require("#{PATH}/radial_menu/sub_menu")
    Sketchup.require("#{PATH}/radial_menu/label_text")
    Sketchup.require("#{PATH}/radial_menu/tooltip")
    PLUGIN = TRINH_VAN_PHUC::HTU_ScalePlus::PLUGIN
    PATH_R = File.join(File.dirname(__FILE__), "radial_menu/Resources")
    MISSING_ICON = File.join(PATH_R, "missing.png")
    TEXT_ICON = File.join(PATH_R, "text_command.png")
    ERROR_ICON = File.join(PATH_R, "tb_unknown.png")
    class << self
      attr_accessor(:settings, :debug)
    end
    class Settings
      def initialize(section)
        @section = section
        @cache = {}
      end
      def [](key, default = nil)
        if @cache.key?(key)
          x = @cache[key]
        else
          begin
            x = Sketchup.read_default(@section, key.to_s, default)
          rescue SyntaxError
            puts("#<Setting> Error reading setting! - Returning default value.")
            puts("> #{@section.inspect} - #{key.to_s.inspect} (#{default.inspect})")
            x = default
          end
          if default.is_a?(Length)
            x = x.to_l
          end
          if x.is_a?(String) && default.is_a?(Symbol)
            x = x.intern
          end
          @cache[key] = x
          x
        end
      end
      def []=(key, value)
        @cache[key] = value
        if value.is_a?(Length)
          value = value.to_f
        end
        if value.is_a?(Symbol)
          value = value.to_s
        end
        Sketchup.write_default(@section, key.to_s, value)
        value
      end
      def set_default(key, default = nil)
        self[key, default]
      end
      def sub_section(sub_section)
        new("#{@section}\\#{sub_section}")
      end
    end
    @settings = Settings.new("#{PLUGIN}.RadialMenu.Settings")
    @settings.set_default(:scale_factor, 1)
    @settings.set_default(:text_scale_factor, 1)
    @settings.set_default(:draw_shadow, true)
    class << self
      attr_accessor(:size, :scale_factor)
    end
    @size = PIE_SIZE
    @scale_factor = UI.scale_factor
    module_function
    def command_icon_file_path(command)
      unless command
        return
      end
      if command.large_icon != "" && File.exist?(command.large_icon)
        command.large_icon
      elsif command.small_icon != "" && File.exist?(command.small_icon)
        command.small_icon
      end
    end
    def pie_size
      @size * @scale_factor
    end
    def item_expand
      pie_size / 6
    end
  end
end
