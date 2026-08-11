module TRINH_VAN_PHUC::HTU_ScalePlus::RadialMenu
  class LabelText
    include(ShapeGeom)
    LEADER_SINGLE_SEGMENT = 0
    LEADER_TWO_SEGMENT = 1
    LEADER_BEZIER = 2
    attr_accessor(:options, :text)
    attr_reader(:bounds)
    def initialize(text, leader_type = nil, target_point = nil)
      @text = text
      @position = [0, 0]
      @options = {:font => "Arial", :size => 10, :bold => false, :rounded => true, :align => TextAlignLeft, :vertical_align => TextVerticalAlignCenter, :color => "blue", :background_color => "white", :border_width => 1, :border_color => "blue", :padding => 12}
      if leader_type.is_a?(Hash)
        options = leader_type
        @leader_type = nil
        @target_point = nil
      else
        @leader_type = leader_type
        @target_point = target_point
      end
      @options.merge!(options)
      @view = Sketchup.active_model.active_view
      redraw
    end
    def text_size
      @options[:size] * PLUGIN::RadialMenu.scale_factor
    end
    def text_padding
      text_size / 2
    end
    def position=(point)
      @position = point
      redraw
    end
    def redraw
      options = @options.clone
      options[:size] = text_size
      @bounds = @view.text_bounds(@position, @text, options)
      x1, y1 = @bounds.upper_left.to_a
      x1 = x1 - text_padding
      y1 = y1 - text_padding / 4
      x2, y2 = @bounds.lower_right.to_a
      x2 = x2 + text_padding
      y2 = y2 + text_padding
      @rect = [Geom::Point3d.new(x1, y1 - text_padding / 4), Geom::Point3d.new(x1, y2 - text_padding / 4), Geom::Point3d.new(x2, y2 - text_padding / 4), Geom::Point3d.new(x2, y1 - text_padding / 4)]
      @shape = @options[:rounded] ? rounded_shape(@rect, text_size / 2) : @rect
      @leader_lines = compute_leader_lines(@bounds, @target_point)
    end
    def rectangle
      @rect
    end
    def compute_leader_lines(bounds, target_point)
      until target_point && @leader_type
        return
      end
      center = ShapeGeom.bounds2d_center(bounds)
      bb_lines = ShapeGeom.bounds2d_lines(bounds)
      bb_midpoints = bb_lines.each_with_object({}) do |l, h|
  h[ShapeGeom.midpoint(l)] = l
end
      @anchor_point = bb_midpoints.keys.min_by do |pt|
  pt.distance(target_point)
end
      line = bb_midpoints[@anchor_point]
      @anchor_vec = center.vector_to(center.project_to_line(line))
      @target_vec = target_point.vector_to(target_point.project_to_line([@anchor_point, Y_AXIS]))
      unless @target_vec.valid?
        @target_vec = target_point.vector_to(target_point.project_to_line([@anchor_point, X_AXIS]))
      end
      d = @anchor_point.distance(target_point) / 2
      case @leader_type
      when LEADER_SINGLE_SEGMENT
        lines = [@anchor_point, target_point]
      when LEADER_TWO_SEGMENT
        anchor_point2 = @anchor_point.offset(@anchor_vec, d)
        lines = [@anchor_point, anchor_point2, target_point]
      when LEADER_BEZIER
        anchor_point2 = @anchor_point.offset(@anchor_vec, d)
        target_point2 = target_point.offset(@target_vec, d)
        pts = [@anchor_point, anchor_point2, target_point2, target_point]
        pts.map! do |pt|
          [pt.x, pt.y, 0]
        end
        lines = compute_bspline(pts, 24, 4)
      end
      lines
    end
    def bezier_points(pts, segments = 24)
      polyline = []
      degree = pts.length - 1
      degree = 2
      unless pts[0].is_a?(Array)
        pts = pts.map(&:to_a)
      end
      knots = [0, 0, 0, 1, 2, 2, 2]
      (0..segments).each do |t|
        pt = interpolate_bezier(t.to_f / segments.to_f, degree, pts, knots)
        point = Geom::Point3d.new(pt)
        polyline.push(point)
      end
      polyline
    end
    def interpolate_bezier(t, degree, points, knots = nil, weights = [], result = [])
      n = points.length
      d = points[0].length
      if degree < 1
        raise("degree must be at least 1 (linear)")
      end
      if degree > n - 1
        raise("degree must be at least 1 (linear)")
      end
      (0..n - 1).each do |i|
        weights[i] = 1
      end
      unless knots
        knots = []
        (0..n + degree).each do |i|
          knots[i] = i
        end
      end
      if knots.length != n + degree + 1
        raise("bad knot vector length")
      end
      domain = [degree, knots.length - 1 - degree]
      low = knots[domain[0]]
      high = knots[domain[1]]
      t = t * (high - low) + low
      if t < low || t > high
        raise("out of bounds")
      end
      s = (domain[0]..domain[1] - 1).find do |i|
  t >= knots[i] && t <= knots[i + 1]
end
      v = []
      (0..n - 1).each do |i|
        v[i] = []
        (0..d - 1).each do |j|
          v[i][j] = points[i][j] * weights[i]
        end
        v[i][d] = weights[i]
      end
      (1..degree).each do |l|
        i = s
        while i > s - degree - 1 + l
          x1 = t - knots[i]
          x2 = knots[i + degree + 1 - l] - knots[i]
          alpha = x1 / x2
          (0..d).each do |j|
            v[i][j] = (1 - alpha) * v[i - 1][j] + alpha * v[i][j]
          end
          i = i - 1
        end
      end
      result ||= []
      (0..d - 1).each do |i|
        result[i] = v[s][i] / v[s][d]
      end
      result
    end
    def compute_bspline(pts, numseg = 24, order = 3)
      curve = []
      nbpts = pts.length
      kmax = nbpts + order - 1
      knot = []
      knot[0] = 0
      (1..kmax).each do |i|
        knot[i] = i >= order && i < nbpts + 1 ? knot[i - 1] + 1 : knot[i - 1]
      end
      t = 0
      step = knot[kmax] / numseg
      (0..numseg).each do
        if knot[kmax] - t < 9.9999999975119991e-08
          t = knot[kmax]
        end
        basis = bspline_basis(order, t, nbpts, knot)
        pt = Geom::Point3d.new
        pt.x = pt.y = pt.z = 0
        (0..nbpts - 1).each do |i|
          pt.x += basis[i] * pts[i].x
          pt.y += basis[i] * pts[i].y
          pt.z += basis[i] * pts[i].z
        end
        curve << pt
        t = t + step
      end
      curve
    end
    def bspline_basis(order, t, nbpts, knot)
      basis = []
      kmax = nbpts + order - 1
      (0..kmax - 1).each do |i|
        basis[i] = t >= knot[i] && t < knot[i + 1] ? 1 : 0
      end
      (1..order - 1).each do |k|
        (0..kmax - k - 1).each do |i|
          d = basis[i] == 0 ? 0 : (t - knot[i]) * basis[i] / (knot[i + k] - knot[i])
          e = basis[i + 1] == 0 ? 0 : (knot[i + k + 1] - t) * basis[i + 1] / (knot[i + k + 1] - knot[i + 1])
          basis[i] = d + e
        end
      end
      if t == knot[kmax]
        basis[nbpts - 1] = 1
      end
      basis
    end
    def draw(view)
      options = @options.clone
      options[:size] = text_size
      if @leader_lines
        view.line_stipple = ""
        view.line_width = 3
        view.drawing_color = options[:background_color]
        view.draw2d(GL_LINE_STRIP, @leader_lines)
      end
      ShapeGeom.draw_shadow(view, @shape, X_AXIS.reverse + Y_AXIS, 6)
      view.line_width = options[:border_width]
      view.drawing_color = options[:background_color]
      view.draw2d(GL_POLYGON, @shape)
      view.drawing_color = options[:border_color]
      view.draw2d(GL_LINE_LOOP, @shape)
      view.draw_text(@position, @text, options)
      if @target_point
        draw_circle_point(view, @target_point, 5)
      end
    end
  end
end
