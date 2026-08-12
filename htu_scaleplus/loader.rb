# =============================================================================
#  HTU ScalePlus — loader.rb (plaintext)
#  (no version number here on purpose: it lives only in htu_scaleplus.rb, and a
#  copy in a banner is a copy that goes stale)
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
require "json"

module TRINH_VAN_PHUC
  class << self
    attr_accessor :tools_command, :plugins_command
  end

  # One submenu named after the extension, not a shared "HTU" bucket. The other
  # HTU extensions each sit at the top level under their own name, and a lone
  # "HTU" entry next to them said nothing about what was inside it.
  MENU_NAME = "HTU_ScalePlus".freeze
  @tools_command   ||= UI.menu("Tools").add_submenu(MENU_NAME)
  @plugins_command ||= UI.menu("Plugins").add_submenu(MENU_NAME)

  module HTU_ScalePlus
    PATH_R       = File.join(File.dirname(__FILE__), "Resources")
    IS_WIN       = Sketchup.platform == :platform_win
    IS_OSX       = Sketchup.platform == :platform_osx
    SCALE_FACTOR = UI.scale_factor
    TEMP_DIMS    = File.join(PATH_R, "dims.csv")

    # pet_toolbar and radial_menu are gone: the six commands the pet toolbar
    # hosted now sit on the real toolbar below, and radial_menu/ existed only to
    # draw it. The files stay in the tree, unloaded, like listbox.rb.
    Sketchup.require "#{PATH}/utils"
    Sketchup.require "#{PATH}/main"
    # Part of the same axis-lock mechanism main.rb owns -- it is the branch that
    # handles a selection of more than one object -- so it sits next to it.
    Sketchup.require "#{PATH}/group_lock"
    Sketchup.require "#{PATH}/tool"
    Sketchup.require "#{PATH}/dim_favorites"
    Sketchup.require "#{PATH}/dim_menu"
    Sketchup.require "#{PATH}/dim_add_dialog"
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

    # set_default, not assignment: `@settings[:dim_text_size] = DIM_SMALL` wrote
    # on every startup, so the Text size chosen from the dimension menu was
    # overwritten each time SketchUp launched and never survived a session.
    @settings.set_default(:dim_text_size, DIM_SMALL)

    def self.active_overlay(model = Sketchup.active_model)
      return unless model.is_a?(Sketchup::Model)

      model.overlays.find { |o| o.is_a?(TRINH_VAN_PHUC::HTU_ScalePlus::ScalePP2Overlay) }
    end

    def self.create_menu
      # The commands go straight into the extension's own submenu now. There
      # used to be a "ScalePlus" submenu nested inside it, which read as
      # "HTU_ScalePlus > ScalePlus > ..." once the outer one was named properly.
      #
      # Check for Update, and the silent check on a ten-second timer that went
      # with it, are gone: both called home to the original vendor's server
      # about a version of this plugin that no longer exists there.
      subplugins = TRINH_VAN_PHUC.plugins_command

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
      # The behaviour commands and the dimension toggle used to live only on the
      # pet toolbar. They already carry icons, tooltips and validation procs, so
      # they work unchanged as native toolbar buttons.
      #
      # #toolbar_cmds, not #cmds: all six are still built and still in the menu
      # below, but the per-axis three do not get a button. See main.rb for why.
      tb.add_separator
      PLUGIN.toolbar_cmds.each { |behaviour_cmd| tb.add_item(behaviour_cmd) }
      UI.start_timer(0.1, false) { tb.restore }

      TRINH_VAN_PHUC.tools_command.add_item(cmd)

      # The same commands again, in a menu this time. SketchUp's Preferences >
      # Shortcuts only lists what it can find in a menu, so a command that lives
      # only on a toolbar can never be bound to a key -- and the axis lock is
      # exactly the kind of thing that wants one.
      subplugins.add_item(cmd)
      PLUGIN.cmds.each_key { |behaviour_cmd| subplugins.add_item(behaviour_cmd) }

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
