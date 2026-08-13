module TRINH_VAN_PHUC::HTU_ScalePlus
  # Navigating the camera is not leaving the Scale tool. Middle-mouse orbit,
  # shift+middle pan, the Zoom and Zoom Window tools, Walk, Look Around: each of
  # them interrupts Scale and hands it straight back, and none of them means the
  # user is done scaling.
  #
  # Only orbit used to be recognised, so a pan or a zoom read as a real tool
  # change and cost three things at once: the dimensions stopped being drawn, a
  # dimension being typed into lost its axis lock and everything typed so far
  # (ScalePPTool#deactivate calls unlock_axis), and the multi-object wrapper was
  # exploded out from under a scale in progress.
  #
  # Matched on a keyword rather than a whole name because #fix_mac_tool_name
  # exists for a reason: SketchUp on macOS reports names with the front chopped
  # off, and a list of exact strings would miss every mangled one.
  #
  # Known limit, not an oversight: the mac truncations recorded in
  # #fix_mac_tool_name go as far as "ool" for MoveTool, and nothing can recover a
  # keyword from that. Orbit, pan and zoom are the three that happen constantly,
  # by middle mouse, and they survive any truncation that leaves the word itself.
  # The robust fix is tool_id, which is numeric and identical on both platforms --
  # but the ids would have to be captured from a running mac first, and a guessed
  # id is worse than a keyword that mostly works.
  NAVIGATION_TOOLS = /Orbit|Pan|Zoom|Walk|Around|Camera/.freeze

  def self.navigation?(tool_name)
    !NAVIGATION_TOOLS.match(tool_name.to_s).nil?
  end

  # Whether SketchUp is mid-navigation right now, asked of the live tool stack
  # rather than of a name handed to a callback. The overlay needs it that way:
  # onMouseMove arrives with no tool name at all.
  def self.navigating?(model = Sketchup.active_model)
    navigation?(model.tools.active_tool_name)
  rescue StandardError
    false
  end

  # There was a GRIPLESS_TOOLS = /Orbit/ here, on the theory that an orbit hides
  # the Scale tool's grips while a pan keeps them. It does not: SketchUp draws
  # neither the grips nor the yellow bounding-box highlight during ANY gesture it
  # reports as a tool change, orbit and pan alike. Confirmed frame by frame from a
  # screen capture -- during a pan the only thing left where a grip should be is
  # the gray outline this plugin draws, with nothing green inside it.
  #
  # What led to the wrong theory: "pan keeps its grips" was reported while the fill
  # covered every navigation, so the grips being seen during a pan were the ones
  # this plugin was painting. Narrowing the fill to orbit took them away again.
  #
  # A scroll-wheel zoom needs no entry anywhere: it is not a tool change at all, so
  # navigation? is false, nothing is painted, and the real grips stay visible
  # underneath -- which is what keeps a fill from ever burying a real grip.
  class ScalePP2Observer
    attr_accessor(:last_tool_name)
    def initialize
      Sketchup.add_observer(AppOb.new(self))
    end
    def selection_changed(selection)
      apply_behavior(selection)
      dialog = TRINH_VAN_PHUC::HTU_ScalePlus::DimsUI.dialog
      unless dialog && dialog.visible?
        return
      end
      TRINH_VAN_PHUC::HTU_ScalePlus::DimsUI.selection_changed
    end
    # Deferred by a tick rather than run inline: this changes the model, and
    # SketchUp does not promise that a model edit made from inside an observer
    # callback is safe -- it can land in the middle of whatever operation caused
    # the selection to change.
    def apply_behavior(selection)
      id = UI.start_timer(0, false) do
        UI.stop_timer(id)
        PLUGIN.apply_behavior(selection)
      end
    rescue StandardError => e
      p(e)
    end
    class AppOb < Sketchup::AppObserver
      def initialize(observer = nil)
        @observer = observer
        begin
          attach_observers(Sketchup.active_model)
        rescue StandardError
        end
      end
      def onNewModel(model)
        attach_observers(model)
      end
      def onOpenModel(model)
        attach_observers(model)
      end
      def onActivateModel(model)
        overlay = model.overlays.to_a.find do |o|
  o.is_a?(TRINH_VAN_PHUC::HTU_ScalePlus::ScalePP2Overlay) && o.valid?
end
        if overlay
          return
        end
        add_overlay(model)
      end
      private
      def attach_observers(model)
        model.tools.add_observer(ScalePP2_ToolsOb.new(@observer))
        model.selection.add_observer(ScalePPSelectionObserver.new(@observer))
        model.add_observer(ScalePPModelOb.new)
        if model.overlays.to_a.find do |o|
  o.is_a?(TRINH_VAN_PHUC::HTU_ScalePlus::ScalePP2Overlay) && o.valid?
end
          return
        end
        add_overlay(model)
      end
      def add_overlay(model)
        overlay = TRINH_VAN_PHUC::HTU_ScalePlus::ScalePP2Overlay.new
        model.overlays.add(overlay)
        # SketchUp registers new overlays disabled, and every entry point in the
        # plugin is gated on Overlay#enabled? -- including the ScaleTool
        # piggyback in #tool_changed, so pressing S did nothing until the user
        # toggled the overlay by hand. Enable on registration instead. This runs
        # once per model (the caller skips it when an overlay already exists), so
        # a later manual toggle in the Overlays panel is left alone.
        begin
          overlay.enabled = true
        rescue StandardError => e
          p(e)
        end
      end
    end
    # The one cleanup point that is not a tool change, and the one that protects
    # the user's file: a wrapper group is scratch, it must never be written into
    # a .skp. Run inline, not deferred a tick like the others -- the save happens
    # immediately after this returns, so a timer would fire too late to matter.
    class ScalePPModelOb < Sketchup::ModelObserver
      def onPreSaveModel(model)
        GroupLock.unwrap(model)
      rescue StandardError => e
        p(e)
      end
    end
    class ScalePPSelectionObserver < Sketchup::SelectionObserver
      def initialize(observer)
        @observer = observer
      end
      def onSelectionBulkChange(selection)
        selection_changed(selection)
      end
      def onSelectionAdded(selection, _entity)
        selection_changed(selection)
      end
      def onSelectionCleared(selection)
        selection_changed(selection)
      end
      def selection_changed(selection)
        @observer.selection_changed(selection)
      end
    end
    class ScalePP2_ToolsOb < Sketchup::ToolsObserver
      def initialize(observer)
        @observer = observer
      end
      def navigation?(tool_name)
        PLUGIN.navigation?(tool_name)
      end
      # Whether the tool SketchUp just switched to is one of this plugin's own.
      #
      # It pushes its ScalePPTool onto the stack to catch a click, and SketchUp
      # announces that as a tool change named "RubyTool". The user has not gone
      # anywhere -- they are still scaling, with the cursor outside the grip box or
      # over a dimension -- but the relay below read it as a departure and ran
      #   tool.active = ("ScaleTool" == "RubyTool")  # false
      # which set @active false and called deactivate on every single push.
      #
      # Nothing looked wrong, because Tool#active? is `@active || the tool is on
      # the stack` and the second half was still true. It only surfaced when a
      # camera tool took the top of the stack: the second half collapsed, active?
      # went false, and Overlay#draw stopped drawing the tool at all -- which is
      # why an orbit lost the grips AND the dimensions while a pan did not.
      #
      # Identity, not the name: every other extension's tool is called "RubyTool"
      # too, and switching to one of those IS a real departure.
      def own_tool?
        overlay = PLUGIN.active_overlay
        tools = overlay && overlay.tools
        return false unless tools

        active = Sketchup.active_model.tools.active_tool
        return false unless active

        tools.any? { |tool| tool.equal?(active) }
      rescue StandardError
        false
      end
      def onActiveToolChanged(_model, tool_name, tool_id)
        tool_name = fix_mac_tool_name(tool_name)
        tool_changed(tool_name, tool_id)
        # Navigation is not a tool the user chose, so it must not become the tool
        # the overlay restores to. Overlay#start replays last_tool_name, and
        # replaying "CameraOrbitTool" leaves the Scale tool switched off.
        if navigation?(tool_name)
          return
        end
        @observer.last_tool_name = tool_name
      end
      def tool_changed(tool_name, tool_id)
        if navigation?(tool_name)
          @navigating = true
          return
        end
        # This plugin taking the stack for itself. Not a navigation -- @navigating
        # must stay exactly as it was, so an orbit that pushed the tool still
        # counts as one orbit and still gets its one replay.
        if own_tool?
          return
        end
        # Coming back from an orbit, pan or zoom: SketchUp announces that by
        # reporting the Scale tool as a tool change. It is the one moment the
        # push/pop state can be brought up to date with the camera the user just
        # moved, without waiting for them to jiggle the mouse first.
        resumed = @navigating
        @navigating = false
        # Above the overlay check on purpose. The multi-object wrapper is a
        # scratch group living in the user's model, and leaving one behind is
        # worse than never making one -- so the unwrap has to run even when the
        # overlay has gone away. The navigation guard above is what keeps a
        # middle-mouse orbit in the middle of a scale from unwrapping.
        GroupLock.tool_changed(tool_name)
        unless PLUGIN.active_overlay
          return
        end
        PLUGIN.active_overlay.tool_changed(tool_name)
        if resumed
          PLUGIN.active_overlay.navigation_finished
        end
      end
      def onToolStateChanged(_tools, tool_name, _tool_id, tool_state)
        tool_name = fix_mac_tool_name(tool_name)
        # Above the overlay check, for the same reason the GroupLock call in
        # #tool_changed is: the mask governs SketchUp's OWN handles, and none of the
        # rest of the mask machinery is overlay-gated either -- the six toolbar
        # buttons write it whether the overlay is on or off.
        scale_finished(tool_name, tool_state)
        unless PLUGIN.active_overlay
          return
        end
        PLUGIN.active_overlay.onToolStateChanged(tool_name, tool_state)
      end
      # A grip has just been let go of. This ARMS the mask repair and does nothing
      # else -- no model edit, no operation, no tool change, not even a timer.
      #
      # The first version ran the repair from a UI.start_timer(0) right here, and it
      # crashed SketchUp on every drag. Its own log said why:
      #
      #   Start(Scale)Commit(9)
      #   Start(Macro)New operation ("Scale Handles") started while an existing
      #   operation ("Scale") was still open
      #
      # So the native Scale tool's operation is still open when state 0 arrives, and
      # still open a timer tick later. A tick is the deferral every other observer
      # callback in this plugin uses and it is NOT enough here. The repair now waits
      # for the overlay's #onMouseMove, which SketchUp does not deliver mid-commit.
      #
      # Keyed off the 1 -> 0 transition, not off state 0 on its own: SketchUp also
      # reports 0 when the Scale tool merely becomes active, and the repair re-picks
      # the tool, which brings us straight back here with another 0. Requiring a 1
      # first makes that second pass a no-op instead of a loop.
      def scale_finished(tool_name, tool_state)
        unless tool_name == "ScaleTool"
          return false
        end
        if tool_state == 1
          @dragging = true
          return false
        end
        unless @dragging
          return false
        end
        @dragging = false
        PLUGIN.behavior_repair_pending!
        true
      rescue StandardError => e
        p(e)
        false
      end
      def fix_mac_tool_name(tool_name)
        if tool_name == "eTool"
          tool_name = "ScaleTool"
        elsif tool_name == "ool"
          tool_name = "MoveTool"
        elsif tool_name == "onentCSTool"
          tool_name = "ComponentCSTool"
        elsif tool_name == "PullTool"
          tool_name = "PushPullTool"
        end
        tool_name
      end
    end
  end
end
