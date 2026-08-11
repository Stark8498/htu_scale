module TRINH_VAN_PHUC::HTU_ScalePlus::RadialMenu
  class CircleLayout < Layout
    attr_accessor(:radius)
    def initialize(radius = PLUGIN::RadialMenu.pie_size * 1.5)
      @radius = radius
      super()
      @type = :circle
    end
    def reset
      super
    end
    def min_padding
      PLUGIN::RadialMenu.pie_size / 6
    end
    def first_circle?
      cs = menu.layouts.grep(CircleLayout)
      cs.min_by(&:radius) == self
    end
    def invailedate_bounds
      compute_shape
      redraw_shape
    end
    def auto_layout_items(fixed_radius = true)
      r = fixed_radius ? compute_fixed_radius : @radius
      start_position = @position.offset(X_AXIS, r)
      angle = (360 / @items.length).to_f
      tr = Geom::Transformation.rotation(@position, Z_AXIS, angle.degrees)
      positions = [start_position]
      0.upto(@items.length - 2) do
        positions << positions.last.transform(tr)
      end
      positions.each_with_index do |position, i|
        unless @items[i]
          next
        end
        @items[i].position = position
      end
      auto_resize = @radius != r
      @radius = r
      compute_shape
      redraw
      if menu && auto_resize
        menu.auto_resize_layouts
      end
    end
    def compute_fixed_radius
      angle = @items.empty? ? 90 : (360 / @items.length).to_f
      fixed_radius = (self.size / 2 + self.padding).to_f / Math.sin((angle / 2).degrees)
      if menu && menu.items.include?(self)
        min = menu.min_circle_radius
        min = min + self.size
        if fixed_radius < min
          fixed_radius = min
        end
      end
      if fixed_radius < self.size * 1.5
        fixed_radius = self.size * 1.5
      end
      fixed_radius
    end
    def check_hover(_flag, x, y, _view)
      mouse_in_outer = Geom.point_in_polygon_2D([x, y], @outer_draw, true)
      mouse_in_inner = Geom.point_in_polygon_2D([x, y], @inner_draw, true)
      self.hover = mouse_in_outer && !mouse_in_inner
    end
    attr_reader(:outer_draw)
    def bounds
      @outer_draw
    end
    def redraw(reshape = false)
      if reshape
        compute_shape
      end
      redraw_shape
      @items.each do |i|
        i.redraw(reshape)
      end
      super
    end
    def redraw_shape
      vector = ORIGIN.vector_to(absolute_position)
      @outer_draw = @outer_polygon.map do |point|
  point + vector
end
      @inner_draw = @inner_polygon.map do |point|
  point + vector
end
      @center_circle = @center_polygon.map do |point|
  point + vector
end
      @triangles_draw = Geom.tesselate(@outer_draw, @inner_draw.reverse)
    end
    attr_reader(:center_circle, :inner_polygon)
    def compute_shape
      sides = 64
      @center_polygon = circle_points(ORIGIN, @radius, sides)
      @outer_polygon = circle_points(ORIGIN, @radius + PLUGIN::RadialMenu.pie_size / 2 + self.padding, sides)
      @inner_polygon = circle_points(ORIGIN, @radius - PLUGIN::RadialMenu.pie_size / 2 - self.padding, sides)
    end
    def outer_radius
      @radius + PLUGIN::RadialMenu.pie_size / 2 + self.padding
    end
    def inner_radius
      @radius - PLUGIN::RadialMenu.pie_size / 2 - self.padding
    end
    def draw_shape(view)
      @on_edit = false
      if @on_edit
        view.drawing_color = BACKGOUND_COLOR
        view.draw2d(GL_TRIANGLES, @triangles_draw)
        view.line_width = drawing_line_width
        color = BORDER_COLOR
        view.drawing_color = color
        view.draw2d(GL_LINE_STRIP, @outer_draw)
        view.draw2d(GL_LINE_STRIP, @inner_draw)
      end
      view.drawing_color = BORDER_COLOR
      view.line_width = 3
      view.draw2d(GL_LINE_STRIP, @center_circle)
    end
    def draw_inner_circle(view)
      view.line_stipple = ""
      view.line_width = 1
      view.drawing_color = BORDER_COLOR
      view.draw2d(GL_LINE_STRIP, @inner_draw)
    end
    def inspect
      name = self.class.name.split("::").last
      module_name = self.class.name.split("::")[-2]
      hex_id = format("0x%x", object_id << 1)
      "#<#{module_name}::#{name}:#{hex_id}>"
    end
  end
end
