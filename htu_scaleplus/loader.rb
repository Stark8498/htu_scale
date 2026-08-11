# =============================================================================
#  HTU ScalePlus 1.1.2 — loader.rb (plaintext)
# =============================================================================
#  Recovered from the captured RubyEncoder AST (call #1, buffer
#  The plugin runs entirely from plain Ruby source.
#
#  Constants supplied by the parent file htu_scaleplus.rb:
#    PLUGIN, PLUGIN_NAME, PLUGIN_ID, PLUGIN_VERSION, PATH, PATH_ROOT,
#    FILENAMESPACE, PLUGIN_EX
# =============================================================================

require "sketchup.rb"
require "uri"

module TRINH_VAN_PHUC
  class << self
    attr_accessor :tools_command, :plugins_command
  end

  # Shared "HTU" submenus — created once, reused by every HTU plugin.
  @tools_command   ||= UI.menu("Tools").add_submenu("HTU")
  @plugins_command ||= UI.menu("Plugins").add_submenu("HTU")

  module HTU_ScalePlus
    PATH_R       = File.join(File.dirname(__FILE__), "Resources")
    IS_WIN       = Sketchup.platform == :platform_win
    IS_OSX       = Sketchup.platform == :platform_osx
    SCALE_FACTOR = UI.scale_factor
    TEMP_DIMS    = File.join(PATH_R, "dims.csv")

    Sketchup.require "#{PATH}/utils"
    Sketchup.require "#{PATH}/main"
    Sketchup.require "#{PATH}/pet_toolbar"
    Sketchup.require "#{PATH}/radial_menu"
    Sketchup.require "#{PATH}/tool"
    Sketchup.require "#{PATH}/scale_tool"
    Sketchup.require "#{PATH}/dims"
    Sketchup.require "#{PATH}/observer"
    Sketchup.require "#{PATH}/overlay"

    class << self
      attr_reader :observer
      attr_accessor :settings, :response, :request
    end

    @settings = Settings.new(PLUGIN_NAME)
    @settings.set_default(:dim_offset, 20)

    DIM_SMALL  = 0
    DIM_MEDIUM = 1
    DIM_LARGE  = 2

    @settings[:dim_text_size] = DIM_SMALL

    def self.active_overlay(model = Sketchup.active_model)
      return unless model.is_a?(Sketchup::Model)

      model.overlays.find { |o| o.is_a?(TRINH_VAN_PHUC::HTU_ScalePlus::ScalePP2Overlay) }
    end

    def self.create_menu
      subplugins = TRINH_VAN_PHUC.plugins_command.add_submenu(PLUGIN_ID)
      subplugins.add_item("Check for Update") { PLUGIN::Update.check }

      UI.start_timer(10, false) { PLUGIN::Update.check(true) }

      ex = IS_WIN ? "svg" : "pdf"

      cmd = UI::Command.new(PLUGIN_ID) { TRINH_VAN_PHUC::HTU_ScalePlus.toggle }
      cmd.small_icon      = File.join(PATH_R, "icon.#{ex}")
      cmd.large_icon      = File.join(PATH_R, "icon.#{ex}")
      cmd.tooltip         = "Toggle ScalePlus"
      cmd.status_bar_text = "Toggle ScalePlus Overlay"
      cmd.set_validation_proc do
        if PLUGIN.active_overlay && PLUGIN.active_overlay.enabled?
          MF_CHECKED
        else
          MF_ENABLED
        end
      end

      PLUGIN.build_commands

      tb = UI::Toolbar.new(PLUGIN_NAME)
      tb.add_item(cmd)
      UI.start_timer(0.1, false) { tb.restore }

      TRINH_VAN_PHUC.tools_command.add_item(cmd)

      @observer = ScalePP2Observer.new

      # Interop hook for the separate "HTU Behavior" extension. The body of
      # this branch was empty in the captured AST — see README_BUILD.md.
      ex = Sketchup.extensions["HTU Behavior"]
      if ex && ex.load_on_start?
      end
    end

    TYPE_PACKAGE = false
    PATH_CONFIG  = File.join(PATH, "config")
    file = __FILE__
    unless file_loaded?(file)
      if Sketchup.version.to_i < 23
        UI.messagebox("#{PLUGIN_NAME} only support SketchUp 23+!")
        # AST said `PLUGIN.load_on_start?`, but nothing in the plugin defines
        # that method — it would raise NoMethodError. `load_on_start?` and
        # `uncheck` are a SketchupExtension pair, so PLUGIN_EX is the receiver
        # the original meant. Dead path on SketchUp 23+.
        PLUGIN_EX.uncheck if PLUGIN_EX.load_on_start?
      else
        create_menu
      end
      file_loaded(file)
    end
  end
end
