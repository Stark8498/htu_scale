module TRINH_VAN_PHUC::HTU_ScalePlus
  class PetToolbar
    attr_reader(:menu)
    def initialize(scale)
      @scale = scale
      @model = Sketchup.active_model
      @view = @model.active_view
      @selection = Sketchup.active_model.selection
      @visible = true
      @menu = TRINH_VAN_PHUC::HTU_ScalePlus::RadialMenu::Menu.new
      reset
      @menu.show
    end
    def size=(s)
    end
    def scale_factor=(factor)
      TRINH_VAN_PHUC::HTU_ScalePlus::RadialMenu.scale_factor = factor
      update
    end
    def reset
      if @rect
        @menu.delete_layout(@rect)
      end
      @rect = TRINH_VAN_PHUC::HTU_ScalePlus::RadialMenu::RectangleLayout.new
      load_commands
      @menu.add_layout(@rect)
      @rect.redraw(true)
    end
    def command_on_hover(&block)
      @command_on_hover = block
    end
    def command_on_blur(&block)
      @command_on_blur = block
    end
    def load_commands
      cmds = PLUGIN.cmds.keys
      cmds.each do |command|
        cmd = TRINH_VAN_PHUC::HTU_ScalePlus::RadialMenu::Command.new(command)
        cmd.block = command.proc
        cmd.validation_proc = command.get_validation_proc
        cmd.tooltip = command.tooltip
        cmd.on_click do
          Sketchup.active_model.select_tool(nil)
          run_command(cmd)
        end
        cmd.on_hover do
          if @command_on_hover
            @command_on_hover.call(cmd)
          end
        end
        cmd.on_blur do
          if @command_on_blur
            @command_on_blur.call(cmd)
          end
        end
        @rect.add_item(cmd)
      end
    end
    def visible=(value)
      @visible = value
      @menu.visible = visible?
    end
    def visible?
      @visible
    end
    def on_hover?
      @menu.on_hover?
    end
    def center_screen(view = Sketchup.active_model.active_view)
      [view.vpwidth / 2, view.vpheight / 2]
    end
    def update
      @menu.show(center_screen)
    end
    def redraw_drawui
      @menu.redraw(true)
      @menu.items.each do |item|
        item.auto_layout_items
      end
    end
    def bounds
      bb = Geom::BoundingBox.new
      @menu.items.each do |i|
        bb.add(i.bounds)
      end
      bb
    end
    def command_data(command)
      data = TRINH_VAN_PHUC::PieMenu.command_data(command)
      hash = {:proc => data[:proc], :validation_proc => data[:validation_proc]}
      hash
    end
    def onMouseMove(flag, x, y, view)
      @mouse_xy = [x, y]
      if @menu.visible?
        @menu.onMouseMove(flag, x, y, view)
      end
      view.invalidate
    end
    def onLButtonDown(flag, x, y, view)
      if @menu.visible?
        @menu.onLButtonDown(flag, x, y, view)
      end
    end
    def onLButtonUp(flag, x, y, view)
      if @menu.visible?
        @menu.onLButtonUp(flag, x, y, view)
      end
    end
    def run_command(command = nil)
      command ||= @menu.selected_item
      unless command && command.is_a?(TRINH_VAN_PHUC::HTU_ScalePlus::RadialMenu::Command)
        return
      end
      if command.validation == MF_DISABLED || command.validation == MF_GRAYED
        return UI.beep
      end
      @id_click = UI.start_timer(0.0099999999983992893, false) do
  UI.stop_timer(@id_click)
  command.call
end
    end
    def draw(view)
      unless visible?
        return
      end
      @menu.draw(view)
    end
    def resume(view)
      view.invalidate
    end
  end
end
