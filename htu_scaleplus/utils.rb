module TRINH_VAN_PHUC::HTU_ScalePlus
  module LengthUtils
    def self.number_to_current_length(numner)
      st = Sketchup.format_length(numner)
      if st.include?("mm")
        len = numner.mm
      elsif st.include?("cm")
        len = numner.cm
      elsif st.include?("m")
        len = numner.m
      else
        len
      end
      len
    end
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
  module Utils
    def object?(object)
      unless object.is_a?(Sketchup::Group) || object.is_a?(Sketchup::ComponentInstance)
        return false
      end
      true
    end
    def leaf_object?(object)
      best_object?(object)
    end
    def best_object?(object)
      unless object?(object)
        return
      end
      object.definition.entities.find_all do |e|
  object?(e)
end.empty?
    end
    def geometry?(entity)
      entity.is_a?(Sketchup::Drawingelement) && !object?(entity)
    end
    def definition_paths(d)
      unless d.is_a?(Sketchup::ComponentDefinition)
        d = d.definition
      end
      paths = []
      get_path(paths, d)
      paths
    end
    def get_path(paths, d, path_d = [])
      d.instances.each do |i|
        path = path_d.clone
        path << i
        parent = i.parent
        if parent.is_a?(Sketchup::Model)
          end_path = path
          paths << end_path.reverse
        else
          get_path(paths, parent, path)
        end
      end
    end
    def get_pickhelper_transformation(ph, entity)
      (0...ph.count).each do |i|
        path = ph.path_at(i)
        unless path.include?(entity)
          next
        end
        return ph.transformation_at(i)
      end
      Geom::Transformation.new
    end
    def object_bounds(object)
      if object.is_a?(Sketchup::Group)
        object.local_bounds
      elsif object.is_a?(Sketchup::ComponentInstance)
        object.definition.bounds
      end
    end
    def bound_points(bound)
      if bound.width == 0
        [0, 2, 6, 4].map do |i|
          bound.corner(i)
        end
      elsif bound.height == 0
        [0, 1, 5, 4].map do |i|
          bound.corner(i)
        end
      elsif bound.depth == 0
        [0, 1, 3, 2].map do |i|
          bound.corner(i)
        end
      else
      end
      (0..7).map do |i|
        bound.corner(i)
      end
    end
    def bottom_bound_points(bb, tr_bb = IDENTITY)
      pts = bound_points(bb).map do |pt|
  pt.transform(tr_bb)
end
      [pts[0], pts[1], pts[3], pts[2]]
    end
    def bounds_lines(bb, tr_bb = IDENTITY)
      pts = bound_points(bb).map do |pt|
  pt.transform(tr_bb)
end
      lines = pts.length == 8 ? [[pts[0], pts[1]], [pts[1], pts[3]], [pts[2], pts[3]], [pts[0], pts[2]], [pts[0], pts[4]], [pts[1], pts[5]], [pts[2], pts[6]], [pts[3], pts[7]], [pts[4], pts[5]], [pts[5], pts[7]], [pts[6], pts[7]], [pts[4], pts[6]]] : [[pts[0], pts[1]], [pts[1], pts[2]], [pts[2], pts[3]], [pts[0], pts[3]]]
      lines
    end
    def bounds_center_lines(bb, tr_bb = IDENTITY)
      pts = bound_points(bb).map do |pt|
  pt.transform(tr_bb)
end
      lines = [[midpoint([pts[0], pts[6]]), midpoint([pts[1], pts[7]])], [midpoint([pts[0], pts[5]]), midpoint([pts[2], pts[7]])], [midpoint([pts[0], pts[3]]), midpoint([pts[4], pts[7]])]]
      lines
    end
    def bounds_centers(bb, tr_bb = IDENTITY)
      pts = bound_points(bb).map do |pt|
  pt.transform(tr_bb)
end
      lines = pts.length == 8 ? [[pts[0], pts[3]], [pts[0], pts[5]], [pts[0], pts[6]], [pts[4], pts[7]], [pts[2], pts[7]], [pts[1], pts[7]]] : [[pts[0], pts[3]]]
      lines.map do |l|
        midpoint(l)
      end
    end
    def midpoint(segment)
      Geom.linear_combination(0.5, segment.first, 0.5, segment.last)
    end
    def point_between?(a, b, c)
      v1 = c.vector_to(a)
      v2 = c.vector_to(b)
      if !v1.valid? || !v2.valid?
        return true
      end
      !v1.samedirection?(v2)
    end
    def ipath_transfomation(ipath)
      path = ipath.to_a
      if path.last.respond_to?(:definition)
        tr = Geom::Transformation.new
        path.each do |o|
          tr = tr * o.transformation
        end
        tr
      else
        ipath.transformation
      end
    end
    def drawVec2D(line, view, size = 10)
      p1, p2 = line
      v = p2 - p1
      if v.length > 0
        view.draw2d(GL_LINE_STRIP, [p1, p2])
        tt = Geom::Transformation.rotation(p2, Geom::Vector3d.new(0, 0, 1), 145.degrees)
        tn = Geom::Transformation.rotation(p2, Geom::Vector3d.new(0, 0, 1), 120.degrees)
        v = p2 - p1
        v.length = size * 2
        p3 = (p2 + v).transform(tt)
        p4 = (p2 + v).transform(tt.inverse)
        p5 = (p2 + v).transform(tn)
        p6 = (p2 + v).transform(tn.inverse)
        view.line_stipple = ""
        view.draw2d(GL_LINE_LOOP, [p3, p2, p4, p6, p2, p5])
        view.draw2d(GL_TRIANGLES, [p2, p4, p6, p2, p5, p3])
      end
    end
    def draw_dim_text(view, dim, vector_offset, color = "black", dim_offset = 50.mm)
      text = dim[0].distance(dim[1])
      point = midpoint(dim)
      point.offset!(vector_offset, dim_offset / 4)
      vector = dim.first.vector_to(dim.last)
      normal = vector.cross(vector_offset).reverse
      options = {:size => dim_offset, :align => TextAlignCenter, :vertical_align => TextVerticalAlignBaseline, :direction => vector, :normal => normal, :color => color}
      up = view.camera.up
      direction = view.camera.direction
      camera_left = up.cross(direction)
      if vector.angle_between(camera_left).radians > 90
        vector.reverse!
        point.offset!(vector_offset.reverse, dim_offset / 2)
      end
      if normal.angle_between(direction).radians < 90
        normal.reverse!
        point.offset!(vector_offset.reverse, dim_offset / 2)
      end
      yaxis = vector
      xaxis = direction.cross(yaxis)
      zaxis = xaxis.cross(yaxis)
      vec = snap_text_normal_to_model_axes(zaxis)
      if vec.angle_between(zaxis).radians < 30
        zaxis = vec
      end
      options[:normal] = zaxis
      pj_point = point.project_to_line(dim)
      point = pj_point.offset(options[:direction].cross(options[:normal]), dim_offset / 4)
      view.drawing_color = color
      @text_typeface.draw2d_text(view, point, text.to_s, {nil => options})
    end
    def draw_dim(view, line, vector_offset, color = "gray", dim_offset = 50.mm)
      sp, ep = line
      dim = line.map do |pt|
  pt.offset(vector_offset, 2 * dim_offset)
end
      extensions = [[sp, dim.first], [ep, dim.last]]
      view.line_stipple = ""
      view.line_width = 2
      view.draw_points(dim, 15, 3, color)
      view.line_width = 1
      view.drawing_color = color
      lines = ([dim] + extensions).flatten
      view.draw(GL_LINES, lines)
      view.line_stipple = "_"
      view.draw2d(GL_LINES, lines.map do |pt|
  view.screen_coords(pt)
end)
      draw_dim_text(view, dim, vector_offset, color, dim_offset)
      view.line_width = 1
      view.line_stipple = ""
    end
    def snap_text_normal_to_model_axes(vector)
      @model ||= Sketchup.active_model
      xaxis = @model.axes.xaxis
      yaxis = @model.axes.yaxis
      zaxis = @model.axes.zaxis
      vecs = [xaxis, xaxis.reverse, yaxis, yaxis.reverse, zaxis, zaxis.reverse]
      vec = vecs.min_by do |v|
  v.angle_between(vector).radians
end
      vec
    end
    def hack_point_draw(view, points)
      vec = view.camera.direction.reverse
      d = view.pixels_to_model(2, points.first)
      points.map do |pt|
        pt.offset(vec, d)
      end
    end
    def point_inside_screen?(view, pt)
      rect = [[0, 0, 0], [view.vpwidth, 0, 0], [view.vpwidth, view.vpheight, 0], [0, view.vpheight, 0]]
      Geom.point_in_polygon_2D(view.screen_coords(pt), rect, false)
    end
    def store_camera(view)
      cam = view.camera
      {:eye => cam.eye.to_a.map do |i|
  i.round(3)
end, :up => cam.up.to_a.map do |i|
  i.round(3)
end, :target => cam.target.to_a.map do |i|
  i.round(3)
end}
    end
    def sort_lines_by_line(lines, line)
      bb = Geom::BoundingBox.new.add(lines.flatten)
      d = bb.diagonal
      vec = line[1].is_a?(Geom::Vector3d) ? line[1] : line[0].vector_to(line[1])
      unless vec.valid?
        return lines
      end
      point0 = line[0].offset(vec, d)
      lines.sort_by! do |l|
        midpoint(l).distance(point0)
      end
    end
    def square_from_center(x, y, d)
      half_d = d / 2
      vertex_a = [x - half_d, y - half_d]
      vertex_b = [x - half_d, y + half_d]
      vertex_c = [x + half_d, y + half_d]
      vertex_d = [x + half_d, y - half_d]
      [vertex_a, vertex_b, vertex_c, vertex_d]
    end
    def create_box(center, d)
      x, y, z = center
      half_d = d / 2
      vertices = [[x - half_d, y - half_d, z + half_d], [x - half_d, y - half_d, z - half_d], [x + half_d, y - half_d, z - half_d], [x + half_d, y - half_d, z + half_d], [x - half_d, y + half_d, z + half_d], [x - half_d, y + half_d, z - half_d], [x + half_d, y + half_d, z - half_d], [x + half_d, y + half_d, z + half_d]]
      faces = [[vertices[0], vertices[1], vertices[2], vertices[3]], [vertices[4], vertices[5], vertices[6], vertices[7]], [vertices[0], vertices[4], vertices[7], vertices[3]], [vertices[1], vertices[5], vertices[4], vertices[0]], [vertices[2], vertices[6], vertices[5], vertices[1]], [vertices[3], vertices[7], vertices[6], vertices[2]]]
      faces
    end
    def box_lines(faces)
      lines = []
      faces.each do |face|
        face.each_with_index do |vertex, index|
          next_vertex = face[(index + 1) % face.length]
          lines << [vertex, next_vertex]
        end
      end
      lines
    end
    def definition_paths(d)
      unless d.is_a?(Sketchup::ComponentDefinition)
        d = d.definition
      end
      paths = []
      get_path(paths, d)
      paths
    end
    def get_path(paths, d, path_d = [])
      d.instances.each do |i|
        path = path_d.clone
        path << i
        parent = i.parent
        if parent.is_a?(Sketchup::Model)
          end_path = path
          paths << end_path.reverse
        else
          get_path(paths, parent, path)
        end
      end
    end
  end
  # module Update lived here: a self-updater that fetched
  # https://curic.io/su_plugins/check_update.json, offered "Download and Install",
  # and pointed the user at www.curic.io for support.
  #
  # Its two callers went first -- the "Check for Update" menu item and the
  # ten-second startup timer -- because they ask the original vendor's server about
  # a version of this plugin that was never published there. That left ~270 lines
  # of dead code that still shipped, still loaded, and could still download and
  # install a file if anything ever called it. Removed for the customer release.
end
