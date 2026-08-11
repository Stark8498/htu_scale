module TRINH_VAN_PHUC::HTU_ScalePlus
  class ScalePP2Observer
    attr_accessor(:last_tool_name)
    def initialize
      Sketchup.add_observer(AppOb.new(self))
    end
    def selection_changed(selection)
      dialog = TRINH_VAN_PHUC::HTU_ScalePlus::DimsUI.dialog
      unless dialog && dialog.visible?
        return
      end
      TRINH_VAN_PHUC::HTU_ScalePlus::DimsUI.selection_changed
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
      def onActiveToolChanged(_model, tool_name, tool_id)
        tool_name = fix_mac_tool_name(tool_name)
        tool_changed(tool_name, tool_id)
        @observer.last_tool_name = tool_name
      end
      def tool_changed(tool_name, tool_id)
        if tool_name == "CameraOrbitTool"
          return
        end
        unless PLUGIN.active_overlay
          return
        end
        PLUGIN.active_overlay.tool_changed(tool_name)
      end
      def onToolStateChanged(_tools, tool_name, _tool_id, tool_state)
        unless PLUGIN.active_overlay
          return
        end
        tool_name = fix_mac_tool_name(tool_name)
        PLUGIN.active_overlay.onToolStateChanged(tool_name, tool_state)
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
