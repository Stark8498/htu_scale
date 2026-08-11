module TRINH_VAN_PHUC::HTU_ScalePlus::RadialMenu
  module ShapeGeom
    extend(self)
    def bounds2d_points(bounds)
      x1, y1 = bounds.upper_left.to_a
      x2, y2 = bounds.lower_right.to_a
      [Geom::Point3d.new(x1, y1), Geom::Point3d.new(x1, y2), Geom::Point3d.new(x2, y2), Geom::Point3d.new(x2, y1)]
    end
    # DECOMPILER FIX: the captured AST lost the `width`/`height` optional
    # params. The body references both as bare identifiers, and the sole caller
    # `square_points(origin, size)` invokes it as
    # `rectangle_points(origin, size, size)` — so the arity is 3.
    def rectangle_points(origin = ORIGIN, width = 1, height = 1)
      rect = [Geom::Point3d.new(origin.x - width / 2, origin.y - height / 2, 0), Geom::Point3d.new(origin.x + width / 2, origin.y - height / 2, 0), Geom::Point3d.new(origin.x + width / 2, origin.y + height / 2, 0), Geom::Point3d.new(origin.x - width / 2, origin.y + height / 2, 0)]
      rect
    end
    def circle_line_width(center, radius, sides, size = 2)
      outer = circle_points(center, radius + size / 2, sides)
      inner = circle_points(center, radius - size / 2, sides)
      Geom.tesselate(outer, inner.reverse)
    end
    def line_width(line, size = 2, sides = 6)
      if size < 2
        raise("Size must be > 1")
      end
      pts = []
      p_start, p_end = line
      vec_edge = p_start.vector_to(p_end)
      vec_cr = Z_AXIS.cross(vec_edge)
      vec_cr.length = size / 2
      pts << p_start.offset(vec_cr)
      angle = 360 / (sides * 2)
      trans = Geom::Transformation.rotation(p_start, Z_AXIS, angle.degrees)
      1.upto(sides) do
        pts << pts.last.transform(trans)
      end
      pts << pts.last.offset(vec_edge)
      trans = Geom::Transformation.rotation(p_end, Z_AXIS, angle.degrees)
      1.upto(sides) do
        pts << pts.last.transform(trans)
      end
      pts
    end
    def square_points(origin, size)
      rectangle_points(origin, size, size)
    end
    def square_uvs
      [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1, 0, 0), Geom::Point3d.new(1, 1, 0), Geom::Point3d.new(0, 1, 0)].reverse
    end
    def circle_points(center = ORIGIN, radius = 1, sides = 24)
      vecx = X_AXIS.clone
      vecx.length = radius
      circle = [center.offset(vecx)]
      tr = Geom::Transformation.rotation(center, Z_AXIS, (360 / sides).degrees)
      0.upto(sides - 1) do
        circle.push(circle.last.transform(tr))
      end
      circle
    end
    def circle_uvs(sides = 24)
      circle = [ORIGIN.offset(X_AXIS)]
      tr = Geom::Transformation.rotation(ORIGIN, Z_AXIS, (360 / sides).degrees)
      0.upto(sides - 1) do
        circle.push(circle.last.transform(tr))
      end
      uvs = circle.map do |pt|
  pt.offset(X_AXIS + Y_AXIS).to_a.map do |i|
    i / 2
  end
end
      uvs.reverse
    end
    def rounded_shape(shape, round)
      begin
        points = []
        lines = []
        0.upto(shape.length - 1) do |a|
          lines << [shape[a], shape[a - (shape.length - 1)]]
        end
        pairs = lines.each_cons(2).map.to_a
        pairs << [lines.last, lines.first]
        pairs.each do |pair|
          line0, line1 = pair
          vector0 = line0[0].vector_to(line0[1])
          vector1 = line1[0].vector_to(line1[1])
          points << line0.first.offset(vector0, round)
          points << line0.last.offset(vector0.reverse, round)
          normal = vector0.cross(vector1)
          center = points.last.offset(vector1, round)
          sides = 6
          total_angle = 90
          angle = total_angle / sides
          tr = Geom::Transformation.rotation(center, normal, angle.degrees)
          0.upto(sides - 1) do
            points << points.last.transform(tr)
          end
        end
        points
      rescue => exception
        shape
      end
    end
    def midpoint(segment, point = nil)
      if point
        segment = [segment, point]
      end
      line = segment.map do |pt|
  pt.to_a[0..1]
end
      Geom.linear_combination(0.5, line.first, 0.5, line.last)
    end
    def point_between?(a, b, c)
      v1 = c.vector_to(a)
      v2 = c.vector_to(b)
      if !v1.valid? || !v2.valid?
        return true
      end
      !v1.samedirection?(v2)
    end
    def point_inside_segment?(point, segment)
      point_between?(segment[0], segment[1], point)
    end
    def draw_circle_point(view, point, size = 5, color = MAIN_COLOR)
      points = circle_points(point, (size + 2) * PLUGIN::RadialMenu.scale_factor, 12)
      view.drawing_color = "white"
      view.draw2d(GL_POLYGON, points)
      points = circle_points(point, size * PLUGIN::RadialMenu.scale_factor, 12)
      view.drawing_color = color
      view.draw2d(GL_POLYGON, points)
    end
    def draw_shadow(view, shape, vector = X_AXIS.reverse + Y_AXIS, size = 4)
      unless PLUGIN::RadialMenu.settings[:draw_shadow]
        return
      end
      shadow_l = shape.map do |pt|
  pt.offset(vector, size * PLUGIN::RadialMenu.scale_factor)
end
      shadow = shape.map do |pt|
  pt.offset(vector, size / 2 * PLUGIN::RadialMenu.scale_factor)
end
      view.drawing_color = SHADOW_COLOR_L
      gl = shape.length % 3 == 0 ? GL_TRIANGLES : GL_POLYGON
      view.draw2d(gl, shadow_l)
      view.drawing_color = SHADOW_COLOR
      view.draw2d(gl, shadow)
    end
    def screen_rectangle(view = Sketchup.active_model.active_view)
      width = view.vpwidth
      height = view.vpheight
      [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(width, 0, 0), Geom::Point3d.new(width, height, 0), Geom::Point3d.new(0, height, 0)]
    end
  end
end
