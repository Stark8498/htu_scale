module TRINH_VAN_PHUC::HTU_ScalePlus::RadialMenu
  class Menu
    include(ShapeGeom)
    attr_reader(:items, :position)
    attr_accessor(:visible)
    def initialize
      @items = []
      @position = ORIGIN.clone
      @view = Sketchup.active_model.active_view
      @visible = false
      reset
    end
    def position=(point)
      @position = point
      if visible?
        show(point)
      end
    end
    def show(point = center_screen)
      @visible = true
      if point.is_a?(Array)
        point = Geom::Point3d.new(point)
      end
      @position = point
      redraw
    end
    def close
      @visible = false
      reset
    end
    def visible?
      @visible
    end
    def on_hover?
      @items.any? do |i|
        i.hover?
      end
    end
    def on_edit?
      false
    end
    def reset
      @mouse_down = nil
      @key_press = nil
      @items.each(&:reset)
    end
    def tree
      @items.map(&:tree)
    end
    def commands
      []
    end
    def add_layout(layout)
      @items << layout
      layout.parent = self
      if layout.is_a?(PLUGIN::RadialMenu::CircleLayout) && layout.radius != layout.compute_fixed_radius
        layout.auto_layout_items
      end
    end
    def delete_layout(layout)
      unless layout
        return
      end
      @items.delete(layout)
      layout.items.each do |e|
        e.erase!
      end
    end
    def auto_resize_layouts
      cls = items.grep(PLUGIN::RadialMenu::CircleLayout)
      cls.sort_by! do |l|
        l.items.length
      end
      cls.each_with_index do |c, i|
        if i.zero?
          c.auto_layout_items(true)
        else
          previous_layout = cls[i - 1]
          fixed_radius = c.compute_fixed_radius
          if overlapping_with?(previous_layout, fixed_radius) || previous_layout.radius >= fixed_radius
            fixed_radius = previous_layout.radius + PLUGIN::RadialMenu.pie_size * 1.5
          end
          c.radius = fixed_radius
          c.auto_layout_items(false)
        end
      end
    end
    def center_screen
      view = Sketchup.active_model.active_view
      [view.vpwidth / 2, view.vpheight / 2]
    end
    def redraw(reshape = false)
      items.each do |i|
        i.redraw(reshape)
      end
    end
    def onMouseMove(flag, x, y, view)
      unless visible?
        return
      end
      @mouse = [x, y]
      draw = false
      @items.each do |c|
        c.onMouseMove(flag, x, y, view)
      end
      hover_cmd = commands.find do |c|
  c.hover?
end
      view.tooltip = hover_cmd && (hover_cmd.ui_command && !hover_cmd.tooltip) ? hover_cmd.ui_command.menu_text : nil
      if hover_cmd
        draw = true
      end
      if draw
        onSetCursor
      end
      if draw
        view.invalidate
      end
    end
    def onLButtonDown(flag, x, y, view)
      unless visible?
        return
      end
      @mouse_down = [x, y]
      @items.each do |l|
        l.onLButtonDown(flag, x, y, view)
      end
    end
    def onLButtonUp(flag, x, y, view)
      unless visible?
        return
      end
      @items.each do |c|
        c.onLButtonUp(flag, x, y, view)
      end
      @mouse_down = nil
      view.invalidate
    end
    def getMenu(*_args)
      true
    end
    def min_circle_radius
      PLUGIN::RadialMenu.pie_size
    end
    def draw(view)
      unless visible?
        return
      end
      @items.each do |i|
        i.draw(view)
      end
    end
    def inspect
      name = self.class.name.split("::").last
      module_name = self.class.name.split("::")[-2]
      hex_id = format("0x%x", object_id << 1)
      "#<#{module_name}::#{name}:#{hex_id}>"
    end
    def missing_method(method, *_args)
      if PLUGIN::RadialMenu.debug
        p("#{self.class}.missing_method: #{method}")
      end
    end

    # UPSTREAM BUG FIX (author's typo, faithfully decompiled — the debug string
    # inside the method also reads "missing_method", so the AST is not at fault):
    # `missing_method` is not a Ruby hook, so the bare `onSetCursor` call in
    # onMouseMove raised NoMethodError on every hover and aborted the rest of the
    # callback, including `view.invalidate`. Aliasing the author's logger onto the
    # real hook makes the call the logged no-op it was written to be.
    # Revert by deleting this one line if you need byte-faithful behaviour.
    alias_method :method_missing, :missing_method
  end
end
