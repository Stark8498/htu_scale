module TRINH_VAN_PHUC::HTU_ScalePlus::RadialMenu
  class Command < Item
    attr_accessor(:block, :validation_proc)
    attr_reader(:data, :icon, :icon_texture, :tooltip)
    # DECOMPILER FIX: the AST lost the `data` parameter. The body does
    # `@data.merge!(data)` on the line after assigning @data, so with the
    # parameter gone `data` resolved to the attr_reader and self-merged @data —
    # a harmless no-op, but only by accident. `data = {}` restores the intended
    # arity with byte-identical behaviour for the one call site in this plugin
    # (pet_toolbar.rb passes a single argument).
    def initialize(command = nil, data = {}, &block)
      super()
      if command.is_a?(String)
        @name = command
      elsif command.is_a?(UI::Command)
        self.ui_command = command
      end
      @data = {:name => nil, :ui_command => nil, :icon => nil, :tooltip => nil}
      @data.merge!(data)
      if @data[:name]
        self.name = @data[:name]
      end
      if @data[:ui_command]
        self.ui_command = @data[:ui_command]
      end
      if @data[:icon]
        self.icon = @data[:icon]
      end
      if @data[:tooltip]
        self.tooltip = @data[:tooltip]
      end
      @block = block
      @type = :circle
      @sides = 24
      @texture_draw = []
      @bound_draw = []
      redraw(true)
      reset
    end
    attr_reader(:ui_command)
    def ui_command=(cmd)
      @ui_command = cmd
      unless @ui_command
        return
      end
      parse_ui_command_icon_texture
      self.tooltip = cmd.tooltip == "" ? cmd.menu_text : cmd.tooltip
    end
    def name
      if @ui_command
        @ui_command.menu_text
      else
        @name
      end
    end
    attr_writer(:name)
    def icon=(file)
      begin
        if @icon_texture
          Sketchup.active_model.active_view.release_texture(@icon_texture)
        end
        @icon = file
        if file && File.exist?(file)
          image_rep = Sketchup::ImageRep.new(file)
          @icon_texture = Sketchup.active_model.active_view.load_texture(image_rep)
        else
          @icon_texture = nil
        end
      rescue StandardError => e
        @icon_texture = nil
      end
    end
    def parse_ui_command_icon_texture
      texture = nil
      if @ui_command
        begin
          image = command_icon_file(@ui_command)
          image ||= PLUGIN::RadialMenu::ERROR_ICON
          image_rep = Sketchup::ImageRep.new(image)
          texture = Sketchup.active_model.active_view.load_texture(image_rep)
        rescue StandardError => e
          p(["Error load_texture texture", e.message, @ui_command.menu_text])
          image = PLUGIN::RadialMenu::ERROR_ICON
          image_rep = Sketchup::ImageRep.new(image)
          texture = Sketchup.active_model.active_view.load_texture(image_rep)
        end
      end
      @icon = image
      @icon_texture = texture
      texture
    end
    def release_icon
      unless @icon_texture
        return
      end
      view = Sketchup.active_model.active_view
      view.release_texture(@icon_texture)
      @icon_texture = nil
    end
    attr_accessor(:tooltip_color)
    def tooltip=(text)
      @tooltip_color ||= "blue"
      options = {:size => 10 * PLUGIN::RadialMenu.scale_factor, :rounded => false, :color => @tooltip_color, :border_color => @tooltip_color}
      @tooltip = Tooltip.new(text, {nil => options})
      redraw_tooltip
    end
    def tree
      {:item => self, :position => @position, :menu_text => @ui_command.menu_text, :icon => command_icon_file(@ui_command), :tooltip => @tooltip ? @tooltip.text : ""}
    end
    def size
      PLUGIN::RadialMenu.pie_size
    end
    def padding
      size / 6
    end
    def bounds2d
      bb3d = Geom::BoundingBox.new
      bb3d.add(bounds)
      upper_left = Geom::Point2d.new(bb3d.corner(0).to_a[0..1])
      lower_right = Geom::Point2d.new(bb3d.corner(3).to_a[0..1])
      Geom::Bounds2d.new(upper_left, lower_right)
    end
    def bounds
      @bound_draw
    end
    def compute_shape
      if @type == :circle
        rect_radius = Math.sqrt(2 * size * size) / 2
        @texture_polygon = square_points(ORIGIN, rect_radius)
        @bound_polygon = circle_points(ORIGIN, size / 2 + 1, @sides)
      elsif @type == :square
        @bound_polygon = square_points(ORIGIN, size)
      end
      @uvs = square_uvs
      @bg_square = square_points(ORIGIN, size + padding)
      @bg_square = rounded_shape(@bg_square, padding * 1.5)
    end
    def erase!
      if @icon_texture
        Sketchup.active_model.active_view.release_texture(@icon_texture)
      end
    end
    def redraw(reshape = false)
      if reshape
        compute_shape
      end
      ab_pos = absolute_position
      vector = ORIGIN.vector_to(ab_pos)
      @texture_draw = @texture_polygon.map do |point|
  point + vector
end
      @bound_draw = @bound_polygon.map do |point|
  point + vector
end
      redraw_tooltip
      super
    end
    def redraw_tooltip(reverse = false)
      begin
        unless @tooltip
          return
        end
        # UPSTREAM BUG FIX: center_screen returns a bare [x, y] Array, so
        # `center_screen.x` raised NoMethodError — swallowed by the rescue below,
        # but it fired for every pet-toolbar command, which is built before it is
        # added to a menu (so `menu` is nil here). Menu#show normalises the same
        # Array with `Geom::Point3d.new(point)`; this follows that idiom.
        x = menu ? menu.position.x : center_screen[0]
        @tooltip.options[:align] = absolute_position.x < x ? TextAlignRight : TextAlignLeft
        @tooltip.redraw
        if self.parent.is_a?(PLUGIN::RadialMenu::RectangleLayout)
          vec = Y_AXIS.clone
          vec.length = size + padding * 2
          if reverse
            vec.reverse!
          end
        else
          # Same normalisation as above — center_screen is an [x, y] Array and
          # the next line calls Point3d#vector_to on it.
          center = menu ? menu.position : Geom::Point3d.new(center_screen)
          vec = center.vector_to(absolute_position)
          vec.length = size + padding
        end
        point = absolute_position.offset(vec)
        @tooltip.position = point
      rescue => exception
        p(self)
        p(exception)
      end
    end
    def zone
      @bound_draw
    end
    def onMouseMove(_flag, x, y, view)
      focus = hover?
      self.hover = Geom.point_in_polygon_2D([x, y], zone, true)
      if @tooltip
        @tooltip.visible = hover?
      end
      if @on_hover && (hover? && !focus)
        @on_hover.call(hover?, view)
      end
      if @on_blur && (focus && !hover?)
        @on_blur.call
      end
    end
    def onLButtonDown(_flag, x, y, _view)
      if @validation && (@validation == MF_DISABLED || @validation == MF_GRAYED)
        self.active = false
      else
        self.hover = Geom.point_in_polygon_2D([x, y], zone, true)
        self.active = hover?
      end
    end
    def onLButtonUp(_flag, _x, _y, _view)
      unless active?
        return
      end
      if @on_click
        @on_click.call
      elsif @block
        @block.call
      end
    end
    def call
      begin
        unless @block
          return
        end
        reset
        @block.call
      rescue StandardError => e
        p(e)
      end
    end
    def validation
      if @validation_proc
        @validation_proc.call
      else
        MF_ENABLED
      end
    end
    def draw(view)
      begin
        view.line_stipple = ""
        @validation = validation
        shadow = hover? || active? ? 6 : 4
        draw_shadow(view, @bound_draw, X_AXIS.reverse + Y_AXIS, shadow)
        draw_background(view)
        line_width = draw_line_width
        view.line_width = line_width
        view.drawing_color = border_color
        view.draw2d(GL_LINE_STRIP, @bound_draw)
        @icon_texture ||= parse_ui_command_icon_texture
        draw_icon(view)
        if @validation == MF_DISABLED || @validation == MF_GRAYED
          draw_disable(view)
        end
      rescue StandardError => e
        p(e.message)
        p(e.backtrace.inspect)
      end
    end
    def draw_icon(view)
      unless @icon_texture
        return
      end
      begin
        view.draw2d(GL_POLYGON, @texture_draw, {:texture => @icon_texture, :uvs => @uvs})
      rescue ArgumentError => e
        if e.message == "invalid texture ID"
          @icon_texture = parse_ui_command_icon_texture
          draw(view)
        end
      end
    end
    def draw_line_width
      if active?
        return @active_line_width
      elsif hover?
        return @hover_line_width
      end
      1
    end
    def draw_background(view)
      view.drawing_color = background_color
      view.draw2d(GL_POLYGON, @bound_draw)
    end
    def draw_disable(view)
      c = background_color.clone
      if c.is_a?(Sketchup::Color)
      else
        c = Sketchup::Color.new(c)
      end
      c.alpha = 150
      view.drawing_color = c
      view.draw2d(GL_POLYGON, @bound_draw)
    end
    def background_color
      if @validation
        case @validation
        when MF_GRAYED, MF_DISABLED
          return DISABLED_BACKGOUND_COLOR
        when MF_CHECKED
          return ACTIVE_BACKGOUND_COLOR
        end
      end
      BACKGOUND_COLOR
    end
    def border_color
      if @validation
        case @validation
        when MF_GRAYED, MF_DISABLED
          return DISABLED_COLOR
        when MF_CHECKED
          return ACTIVE_BORDER_COLOR
        end
      end
      if active?
        ACTIVE_BORDER_COLOR
      elsif @hover
        HOVER_BORDER_COLOR
      else
        BORDER_COLOR
      end
    end
    def command_icon_file(command)
      unless command && command.is_a?(UI::Command)
        return
      end
      if command.large_icon != "" && File.exist?(command.large_icon)
        command.large_icon
      elsif command.small_icon != "" && File.exist?(command.small_icon)
        command.small_icon
      end
    end
    def inspect
      name = self.class.name.split("::").last
      module_name = self.class.name.split("::")[-2]
      hex_id = format("0x%x", object_id << 1)
      "#<#{module_name}::#{name}:#{hex_id}> #{@ui_command ? @ui_command.menu_text : ""} "
    end
  end
end
