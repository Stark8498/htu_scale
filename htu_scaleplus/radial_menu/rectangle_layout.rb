module TRINH_VAN_PHUC::HTU_ScalePlus::RadialMenu
  class RectangleLayout < Layout
    attr_accessor(:column, :row)
    attr_reader(:width, :height, :hover_vertex)
    def initialize(table = [1, 1])
      @column, @row = table
      super()
      @type = :rectangle
    end
    def reset
      super
    end
    def resize(table)
      column, row = table
      if !column.is_a?(Integer) || !row.is_a?(Integer)
        raise("Column and row must be Integer")
      end
      if column < 1
        raise("Column must be > 0")
      end
      if row < 1
        raise("Row must be > 0")
      end
      if column * row < @items.length
        raise("Size must be >= number of items")
      end
      @column = column.to_i
      @row = row.to_i
      auto_layout_items
    end
    def can_move?
      true
    end
    def min_x
      if @items.empty?
        return 0
      end
      min_x = @items.min_by do |i|
  i.position.x
end.position.x
      min_x / (self.size + self.padding)
    end
    def min_y
      if @items.empty?
        return 0
      end
      min_y = @items.min_by do |i|
  i.position.y
end.position.y
      min_y / (self.size + self.padding)
    end
    def max_x
      if @items.empty?
        return 0
      end
      max_x = @items.max_by do |i|
  i.position.x
end.position.x
      max_x / (self.size + self.padding)
    end
    def max_y
      if @items.empty?
        return 0
      end
      max_y = @items.max_by do |i|
  i.position.y
end.position.y
      max_y / (self.size + self.padding)
    end
    def columns
      max_x - min_x + 1
    end
    def rows
      max_y - min_y + 1
    end
    def can_resize?
      @items.length > 1
    end
    def add_item_at_cell(well, col, row)
      well.position = position_at_cell(col, row)
      unless @items.include?(well)
        @items << well
      end
      compute_shape
    end
    def position_at_cell(col, row)
      vector = Geom::Vector3d.new((self.size + self.padding) * col, (self.size + self.padding) * row, 0)
      ORIGIN + vector
    end
    def get_item_index(item)
      x = item.position.x / (self.size + self.padding)
      y = item.position.y / (self.size + self.padding)
      [x, y]
    end
    def invailedate_bounds
      bb3d = Geom::BoundingBox.new
      if @items.empty?
        origin = absolute_position
        bb3d.add([origin.x - self.size / 2, origin.y - self.size / 2])
        bb3d.add([origin.x + self.size / 2, origin.y + self.size / 2])
      else
        points = []
        @items.each do |item|
          points << item.bounds2d.upper_left.to_a
          points << item.bounds2d.lower_right.to_a
        end
        bb3d.add(points)
      end
      upper_left = Geom::Point2d.new(bb3d.corner(0).to_a[0..1])
      lower_right = Geom::Point2d.new(bb3d.corner(3).to_a[0..1])
      upper_left.x -= self.padding
      upper_left.y -= self.padding
      lower_right.x += self.padding
      lower_right.y += self.padding
      Geom::Bounds2d.new(upper_left, lower_right)
    end
    def auto_layout_items
      if @items.length > @column * @row
        until @column * @row >= items.length
          if @row == 1
            @column = @column + 1
          else
            @row = @row + 1
          end
        end
      end
      i = 0
      0.upto(@row - 1) do |row|
        0.upto(@column - 1) do |col|
          well = @items[i]
          if well
            well.position = position_at_cell(col, row)
          end
          i = i + 1
        end
      end
      redraw(true)
    end
    attr_reader(:outer_draw)
    def bounds
      @outer_draw
    end
    def compute_shape
      bounds = invailedate_bounds
      @outer_draw = ShapeGeom.bounds2d_points(bounds)
      @outer_draw_rounded = ShapeGeom.rounded_shape(@outer_draw, self.padding * 2)
      @outer_polygon = @outer_draw.map do |pt|
  pt.offset(absolute_position.vector_to(ORIGIN))
end
      bounds.height
    end
    def redraw(reshape = false)
      @items.each do |i|
        i.redraw(reshape)
      end
      if reshape
        compute_shape
      end
      vector = ORIGIN.vector_to(absolute_position)
      @outer_draw = @outer_polygon.map do |point|
  point + vector
end
      @outer_draw_rounded = ShapeGeom.rounded_shape(@outer_draw, self.padding * 2)
      super
    end
    def check_hover(_flag, x, y, _view)
      mouse_in_outer = Geom.point_in_polygon_2D([x, y], @outer_draw, true)
      self.hover = mouse_in_outer || !@hover_vertex.nil?
    end
    def draw_shape(view)
      unless @show
        return
      end
      shape = menu.on_edit? ? @outer_draw : @outer_draw_rounded
      # `shadow = 4` was here and nothing read it -- whatever drew a shadow with it is
      # not in the captured source. Dropped so `ruby -w` stays quiet.
      view.drawing_color = BACKGOUND_COLOR
      view.draw2d(GL_POLYGON, shape)
      cam = view.camera
      rays = @outer_draw.map do |pt|
  view.pickray(pt.x, pt.y)
end
      plane = [cam.eye, cam.direction]
      if cam.perspective?
        distance = 10.mm
        plane = [cam.eye.offset(cam.direction, distance), cam.direction]
      elsif PLUGIN.active_overlay
        point = PLUGIN.active_overlay.max_point || cam.eye
        plane = [point, cam.direction]
      end
      rect = rays.map do |ray|
  Geom.intersect_line_plane(ray, plane)
end
      view.draw(GL_QUADS, rect)
      view.line_width = drawing_line_width
      color = BORDER_COLOR
      if menu.on_edit?
        if active?
          color = ACTIVE_BORDER_COLOR
        elsif on_edit?
          color = ACTIVE_BORDER_COLOR
        elsif @hover
          color = HOVER_BORDER_COLOR
        end
      end
      view.drawing_color = color
      if menu.on_edit?
        if drawing_line_width == 1
          view.draw2d(GL_LINE_LOOP, shape)
        else
          0.upto(shape.length - 1).each do |i|
            line = [shape[i], shape[i - (shape.length - 1)]]
            view.draw2d(GL_POLYGON, ShapeGeom.line_width(line, drawing_line_width, 4))
          end
        end
      elsif PLUGIN::RadialMenu.settings[:draw_shadow]
      else
        view.line_width = 1
        view.draw2d(GL_LINE_LOOP, shape)
      end
      if PLUGIN::RadialMenu.debug && menu.on_edit?
        view.drawing_color = "lime"
        view.draw2d(GL_POLYGON, circle_points(absolute_position, 3))
        if on_edit?
          point = absolute_position
          point.x += 30
          point.y += 20
          view.draw_text(point, "x: #{@position.x}\ny: #{@position.y}", {:size => 12})
        end
      end
    end
    def inspect
      name = self.class.name.split("::").last
      module_name = self.class.name.split("::")[-2]
      hex_id = format("0x%x", object_id << 1)
      "#<#{module_name}::#{name}:#{hex_id}>"
    end
  end
end
