require("sketchup")
module TRINH_VAN_PHUC
  module ViewUI
    class Slider < Item
      attr_accessor(:position, :direction, :width, :height, :thumb_radius, :min, :max, :step)
      attr_accessor(:draw_min_text, :draw_max_text, :draw_value_text, :text_size)
      attr_accessor(:value)
      def initialize(*args)
        super(args)
        @direction = X_AXIS
        @width = 200
        @height = 8
        @thumb_radius = @height * 2
        @slider_rounded = @height / 2
        @min = 0
        @max = 100
        @step = 1
        @value = 100
        @range = false
        @draw_min_text = false
        @draw_max_text = false
        @draw_value_text = false
        @text_size = 14
        @sides = 24
        @position = Geom::Point3d.new(500, 500, 0)
        compute_shape
        redraw
      end
      def start
        @position.offset(yaxis, @height / 2)
      end
      def end
        start.offset(@direction, @width)
      end
      def xaxis
        @direction
      end
      def yaxis
        Z_AXIS.cross(@direction)
      end
      def bounds
        @slider_shape_draw
      end
      def compute_shape
        if @value < @min
          @value = @min
        end
        if @value > @max
          @value = @max
        end
        @thumb_radius = @height * 2
        @slider_rounded = @height / 3
        point = ORIGIN
        y_axis = Z_AXIS.cross(@direction)
        rect_slider = [point]
        rect_slider << rect_slider.last.offset(@direction, @width)
        rect_slider << rect_slider.last.offset(y_axis, @height)
        rect_slider << rect_slider.last.offset(@direction.reverse, @width)
        @slider_shape = TRINH_VAN_PHUC::PieMenu::ShapeGeom.rounded_shape(rect_slider, @slider_rounded)
        thumb_position = point.offset(y_axis, @height / 2)
        @thumb_shape = TRINH_VAN_PHUC::PieMenu::ShapeGeom.circle_points(thumb_position, @thumb_radius / 2, @sides)
      end
      def slider_value_shape
        length = @point.distance(@position)
        if length.zero?
          return
        end
        point = ORIGIN
        y_axis = Z_AXIS.cross(@direction)
        rect_slider = [point]
        rect_slider << rect_slider.last.offset(@direction, length)
        rect_slider << rect_slider.last.offset(y_axis, @height)
        rect_slider << rect_slider.last.offset(@direction.reverse, length)
        shape = TRINH_VAN_PHUC::PieMenu::ShapeGeom.rounded_shape(rect_slider, @slider_rounded)
        vector = ORIGIN.vector_to(@position)
        shape.map do |pt|
          pt + vector
        end
      end
      def redraw(reshape = false)
        if reshape
          compute_shape
        end
        vector = ORIGIN.vector_to(@position)
        @slider_shape_draw = @slider_shape.map do |point|
  point + vector
end
        @thumb_shape_draw = @thumb_shape.map do |point|
  point + vector
end
        vector_value = @direction.clone
        total = @max - @min
        length_unit = @width.to_f / total
        value_units = @value - @min
        vector_value.length = length_unit * value_units
        @point = @position.offset(vector_value)
        @thumb_shape_draw.map! do |point|
          point + vector_value
        end
      end
      def value=(value)
        @value = value
        if @value.is_a?(Numeric)
          if @min.is_a?(Integer) && @max.is_a?(Integer)
            @value = @value.to_i
          end
        end
        redraw
      end
      def on_change(&block)
        @on_change = block
      end
      def bound_polygons
        @thumb_shape_draw
      end
      def onMouseMove(_flag, x, y, view)
        if active?
          self.value = value_at_mouse(x, y)
          if @on_change
            @on_change.call(@value)
          end
          view.invalidate
        else
          h = @hover
          self.hover = check_hover(x, y)
          if @hover != h
            view.invalidate
          end
        end
      end
      def value_at_mouse(x, y)
        line = [@position, @position.offset(@direction, @width)]
        mouse = Geom::Point3d.new(x, y, 0)
        point = mouse.project_to_line([@position, @direction])
        @point = point
        v_min = point.vector_to(line.first)
        v_max = point.vector_to(line.last)
        if point_between?(line[0], line[1], point)
          d = point.distance(@position)
          total = @max - @min
          length_unit = @width.to_f / total
          value = d.to_f / length_unit + @min
        else
          value = v_min.samedirection?(v_max) && v_min.length < v_max.length ? @min : @max
        end
        @line = line
        value - value % @step
      end
      def onLButtonDown(_flag, x, y, _view)
        self.hover = check_hover(x, y)
        self.active = on_hover?
      end
      def onLButtonUp(_flag, _x, _y, _view)
        self.active = false
      end
      def max_text(&block)
        @max_text = block
      end
      def draw(view)
        draw_slider(view)
        draw_slider_value(view)
        draw_thumb(view)
        if @draw_min_text
          draw_min(view)
        end
        if @draw_max_text
          draw_max(view)
        end
        if @draw_value_text
          draw_value(view)
        end
      end
      def draw_slider(view)
        draw_shadow(view, @slider_shape_draw, X_AXIS.reverse + Y_AXIS, 4)
        view.line_width = 1
        view.drawing_color = "white"
        view.drawing_color = "silver"
        view.draw2d(GL_POLYGON, @slider_shape_draw)
      end
      def draw_thumb(view)
        view.line_width = 4
        view.drawing_color = "limegreen"
        b = Geom::BoundingBox.new
        b.add(@thumb_shape_draw)
        scale = on_hover? ? 1.3999999999068677 : 1.1999999997206032
        tr = Geom::Transformation.scaling(b.center, scale)
        border = @thumb_shape_draw.map do |pt|
  pt.transform(tr)
end
        view.draw2d(GL_POLYGON, border)
        view.drawing_color = on_hover? ? "whitesmoke" : "white"
        view.draw2d(GL_POLYGON, @thumb_shape_draw)
      end
      def draw_min(view)
        text = @min.to_s
        options = {:font => "Arial", :size => @text_size, :bold => true, :align => TextAlignLeft, :color => "gray", :vertical_align => TextVerticalAlignCenter}
        point = start
        bounds = view.text_bounds(point, text, options)
        point.offset!(yaxis, @height / 2 + bounds.height / 2)
        view.draw_text(point, text, options)
      end
      def draw_max(view)
        text = @max_text ? @max_text.call : @max.to_s
        options = {:font => TRINH_VAN_PHUC::PieMenu::TEXT_FONT, :size => @text_size, :bold => false, :align => TextAlignRight, :color => Sketchup::Color.new(50, 50, 50), :vertical_align => TextVerticalAlignCapHeight}
        point = self.end
        bounds = view.text_bounds(point, text, options)
        x1, y1 = bounds.upper_left.to_a
        x2, y2 = bounds.lower_right.to_a
        x1 = x1 - @height
        y1 = y1 - @height / 4
        x2 = x2 + @height
        y2 = y2 + @height / 4
        points = [Geom::Point3d.new(x1, y1), Geom::Point3d.new(x1, y2), Geom::Point3d.new(x2, y2), Geom::Point3d.new(x2, y1)]
        view.drawing_color = TRINH_VAN_PHUC::PieMenu::BACKGOUND_COLOR
        offset = @height + bounds.height / 2
        points.map! do |pt|
          pt.offset!(yaxis, offset)
        end
        bg = rounded_shape(points, @height)
        view.draw2d(GL_POLYGON, bg)
        point.offset!(yaxis, offset)
        view.draw_text(point, text, options)
      end
      def draw_slider_value(view)
        shape = slider_value_shape
        unless shape
          return
        end
        view.drawing_color = "lime"
        view.draw2d(GL_POLYGON, shape)
      end
      def draw_value(view)
        text = @value.to_s
        options = {:font => "Arial", :size => @text_size, :bold => true, :align => TextAlignCenter, :color => "gray", :vertical_align => TextVerticalAlignBaseline}
        point = @point
        bounds = view.text_bounds(point, text, options)
        position = point.offset(yaxis.reverse, @height / 2 + bounds.height / 2)
        view.draw_text(position, text, options)
      end
    end
  end
end
