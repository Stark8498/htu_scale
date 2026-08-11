module TRINH_VAN_PHUC::HTU_ScalePlus
  class << self
    attr_accessor(:active)
    attr_reader(:cmd_reset, :cmd_xyz, :cmd_x, :cmd_y, :cmd_z, :cmd_dim, :cmds)
  end
  def self.set_behavior(state)
    sel = Sketchup.active_model.selection
    definition = sel[0].definition
    behavior = definition.behavior
    old_state = Sketchup.read_default("htu_behavior", "state")
    if old_state && (old_state == state && (old_state != 0 && old_state == behavior.no_scale_mask?))
      state = 0
    end
    Sketchup.write_default("htu_behavior", "state", state)
    behavior.no_scale_mask = state
    Sketchup.send_action("selectScaleTool:")
  end
  def self.toggle_dimensions
    Sketchup.write_default(PLUGIN_NAME, "show_dim", !show_dim?)
  end
  def self.show_dim?
    Sketchup.read_default(PLUGIN_NAME, "show_dim", true)
  end
  def self.build_commands
    all = 0
    xyz = 120
    x = 126
    y = 125
    z = 123
    @cmd_reset = UI::Command.new("Behavior Scale All") do
  set_behavior(all)
end
    @cmd_reset.small_icon = File.join(PATH_R, "reset.png")
    @cmd_reset.large_icon = File.join(PATH_R, "reset.png")
    @cmd_reset.tooltip = "Scale all handles appear"
    @cmd_xyz = UI::Command.new("Behavior Scale XYZ") do
  set_behavior(xyz)
end
    @cmd_xyz.small_icon = File.join(PATH_R, "icon_xyz.png")
    @cmd_xyz.large_icon = File.join(PATH_R, "icon_xyz.png")
    @cmd_xyz.tooltip = "Scale along XYZ"
    @cmd_x = UI::Command.new("Behavior Scale X") do
  set_behavior(x)
end
    @cmd_x.small_icon = File.join(PATH_R, "icon_x.png")
    @cmd_x.large_icon = File.join(PATH_R, "icon_x.png")
    @cmd_x.tooltip = "Scale along red (X)"
    @cmd_y = UI::Command.new("Behavior Scale Y") do
  set_behavior(y)
end
    @cmd_y.small_icon = File.join(PATH_R, "icon_y.png")
    @cmd_y.large_icon = File.join(PATH_R, "icon_y.png")
    @cmd_y.tooltip = "Scale along green (Y)"
    @cmd_z = UI::Command.new("Behavior Scale Z") do
  set_behavior(z)
end
    @cmd_z.small_icon = File.join(PATH_R, "icon_z.png")
    @cmd_z.large_icon = File.join(PATH_R, "icon_z.png")
    @cmd_z.tooltip = "Scale along blue (Z)"
    @cmd_dim = UI::Command.new("Toggle show dimensions") do
  toggle_dimensions
  Sketchup.send_action("selectScaleTool:")
end
    @cmd_dim.small_icon = File.join(PATH_R, "show_dim.png")
    @cmd_dim.large_icon = File.join(PATH_R, "show_dim.png")
    @cmd_dim.tooltip = "Toggle show dimensions"
    @cmd_dim.set_validation_proc do
      if show_dim?
        MF_CHECKED
      else
        MF_ENABLED
      end
    end
    cmds = {}
    cmds[@cmd_reset] = all
    cmds[@cmd_xyz] = xyz
    cmds[@cmd_x] = x
    cmds[@cmd_y] = y
    cmds[@cmd_z] = z
    cmds.each do |cmd, val|
      cmd.set_validation_proc do
        sel = Sketchup.active_model.selection
        if sel.length == 1 && sel[0].respond_to?(:definition)
          definition = sel[0].definition
          behavior = definition.behavior
          no_scale_mask = behavior.no_scale_mask?
          if no_scale_mask == val
            MF_CHECKED
          else
            MF_ENABLED
          end
        else
          MF_GRAYED
        end
      end
    end
    cmds[@cmd_dim] = 0
    @cmds = cmds
  end
  def self.toggle
    PLUGIN.active_overlay.enabled = !PLUGIN.active_overlay.enabled?
  end
  def self.active?
    @active
  end
  def self.scale_factor=(factor)
    begin
      begin
        original_verbose = $VERBOSE
        $VERBOSE = nil
        PLUGIN.const_set(:SCALE_FACTOR, factor)
        begin
          PLUGIN::RadialMenu.scale_factor = factor
          PLUGIN.active_overlay.dim_scale.pet_toolbar.redraw_drawui
        rescue => exception
          p(exception)
        end
        Sketchup.active_model.active_view.invalidate
      rescue StandardError => e
        p(e)
      end
    ensure
      $VERBOSE = original_verbose
    end
  end
  def self.verify_ui_scale
    dialog = UI::HtmlDialog.new({:dialog_title => "", :resizable => true, :width => 300, :min_width => 300, :max_width => 300, :height => 300, :min_height => 300, :max_height => 300, :left => -300, :top => -300})
    html = "      <!DOCTYPE html>\n      <html><script> window.onload = function() { sketchup.ready(window.outerWidth, window.devicePixelRatio) }; </script></html>\n"
    dialog.add_action_callback("ready") do |_a, _width, pixel_ratio|
      PLUGIN.scale_factor = pixel_ratio
      dialog.close
      if Sketchup.respond_to?(:focus)
        Sketchup.focus
      end
    end
    dialog.set_html(html)
    dialog.center
    dialog.show
  end
  module Typeface
    class TextTypeface
      def self.eval(pts, t)
        degree = pts.length - 1
        if degree < 1
          return nil
        end
        t1 = 1 - t
        fact = 1
        n_choose_i = 1
        x = pts[0].x * t1
        y = pts[0].y * t1
        z = pts[0].z * t1
        (1...degree).each do |i|
          fact = fact * t
          n_choose_i = n_choose_i * (degree - i + 1) / i
          fn = fact * n_choose_i
          x = (x + fn * pts[i].x) * t1
          y = (y + fn * pts[i].y) * t1
          z = (z + fn * pts[i].z) * t1
        end
        x = x + fact * t * pts[degree].x
        y = y + fact * t * pts[degree].y
        z = z + fact * t * pts[degree].z
        Geom::Point3d.new(x, y, z)
      end
      def self.points(pts, numpts)
        curvepts = []
        dt = 1 / numpts
        (0..numpts).each do |i|
          t = i * dt
          curvepts[i] = TextTypeface.eval(pts, t)
        end
        curvepts
      end
      attr_accessor(:size, :typeface)
      def initialize
        @typeface = load_typeface
        @geometrys = typeface_to_geometry(@typeface)
        @line_heigth = @typeface[:ascender] - @typeface[:descender]
        @size = 256.mm
        @scale = @size / @line_heigth
        @tr_size = Geom::Transformation.scaling(@scale)
      end
      def activate
        char_loops = convert("HTU 01\n100 mm")
        triangles = []
        char_loops.each do |_char, loops|
          unless loops
            next
          end
          triangles << Geom.tesselate(loops.first, *loops[1..-1])
        end
        @triangles = triangles.flatten
      end
      def typeface_to_geometry(typeface)
        geometrys = {}
        typeface[:glyphs].each do |char, data|
          outline = data[:o].split(" ")
          loops = text_geometry(outline)
          geometrys[char] = loops
        end
        geometrys
      end
      def convert(text, options = {})
        default_options = {:size => 256.mm, :position => ORIGIN.clone, :direction => X_AXIS.clone, :normal => Z_AXIS.clone, :align => TextAlignLeft, :vertical_align => TextVerticalAlignBaseline}
        options = default_options.merge(options)
        size = options[:size]
        scale = size / @line_heigth
        tr_size = Geom::Transformation.scaling(scale)
        data = {}
        x = 0
        y = 0
        bb = Geom::BoundingBox.new
        text.downcase.each_char.each_with_index do |char, i|
          data[i] = nil
          if char == "\n"
            y = y - @line_heigth * scale
            x = 0
            next
          end
          typeface = @typeface[:glyphs][char.to_sym]
          unless typeface
            next
          end
          loops = @geometrys[char.to_sym]
          unless loops
            next
          end
          ha = typeface[:ha] * scale
          if loops.length > 0
            vector = Geom::Vector3d.new(x, y, 0)
            tr = Geom::Transformation.translation(vector)
            data[i] = loops.map do |l|
  l.map do |pt|
    pt.transform(tr * tr_size)
  end
end
            data[i].each do |loop|
              bb.add(loop)
            end
          end
          x = x + ha
        end
        point = ORIGIN.clone
        case options[:align]
        when TextAlignLeft
        when TextAlignCenter
          point.x -= bb.width / 2
        when TextAlignRight
          point.x -= bb.width
        end
        case options[:vertical_align]
        when TextVerticalAlignCenter
          point.y -= bb.height / 2
        when TextVerticalAlignBoundsTop
          point.y -= bb.height
        end
        vec = bb.min.vector_to(point)
        vec2 = ORIGIN.vector_to(options[:position])
        tr = Geom::Transformation.translation(vec)
        tr2 = Geom::Transformation.translation(vec2)
        origin = ORIGIN
        xaxis = options[:direction].reverse
        zaxis = options[:normal]
        yaxis = zaxis.cross(xaxis)
        tr_align = Geom::Transformation.axes(origin, xaxis, yaxis, zaxis)
        data.each do |_i, loops|
          unless loops
            next
          end
          loops.each do |l|
            l.each do |pt|
              pt.transform!(tr2 * tr_align * tr)
            end
          end
        end
        data
      end
      def load_typeface(path = File.join(__dir__, "SF Pro Rounded_Bold.json"))
        begin
          file = File.read(path)
          data = JSON.parse(file, {:symbolize_names => true})
          data
        rescue StandardError => e
          p(e)
          {:import => [], :export => []}
        end
      end
      def text_geometry(outline)
        data = {}
        data[:loops] = []
        data[:points] = []
        data[:lines] = []
        data[:quads] = []
        data[:curves] = []
        data[:control_point] = []
        0.upto(outline.length - 1) do |i|
          action = outline[i]
          case action
          when "m"
            data[:loops] << []
            point = Geom::Point3d.new([outline[i + 1].to_i, outline[i + 2].to_i, 0])
            data[:points] << point
            data[:loops].last << point
          when "l"
            point = Geom::Point3d.new([outline[i + 1].to_i, outline[i + 2].to_i, 0])
            line = [data[:points].last, point]
            data[:lines] << line
            data[:points] << point
            data[:loops].last << point
          when "q"
            end_point = Geom::Point3d.new([outline[i + 1].to_i, outline[i + 2].to_i, 0])
            control_point = Geom::Point3d.new([outline[i + 3].to_i, outline[i + 4].to_i, 0])
            pts = [data[:points].last, control_point, end_point]
            curve = TextTypeface.points(pts, 6)
            data[:points] += curve
            data[:curves] << curve
            data[:quads] << end_point
            data[:control_point] << control_point
            curve.each do |pt|
              data[:loops].last << pt
            end
          when "b"
          else
            next
          end
        end
        data[:loops]
      end
      def onMouseMove(_flags, x, y, view)
        @ip0 ||= nil
        @ip ||= Sketchup::InputPoint.new
        @ip.pick(view, x, y, @ip0)
        view.invalidate
      end
      def onLButtonDown(_flags, _x, _y, view)
        if !@point0
          @ip0 = Sketchup::InputPoint.new
          @ip0.copy!(@ip)
          @point0 = @ip0.position
        else
          @point0 = nil
        end
        view.invalidate
      end
      def resume(view)
        view.invalidate
      end
      def getExtents(*_args)
        bb = Geom::BoundingBox.new
        if @ip
          bb.add(@ip.position)
        end
        if @ip0
          bb.add(@ip0.position)
        end
        bb
      end
      def draw(view)
        view.drawing_color = "blue"
        view.line_stipple = ""
        view.line_width = 1
        if @ip && !@point0
          @ip.draw(view)
        end
        unless @point0
          return
        end
        line = [@ip.position, @ip0.position]
        view.set_color_from_line(@ip, @ip0)
        view.draw_lines(line)
        vector = line.first.vector_to(line.last)
        unless vector.valid?
          return
        end
        point = Geom.linear_combination(0.5, line.first, 0.5, line.last)
        normal = vector.parallel?(Z_AXIS) ? begin
v = view.camera.direction.cross(Z_AXIS)
v.cross(Z_AXIS)
end : Z_AXIS
        options = {:size => view.pixels_to_model(20, point), :align => TextAlignCenter, :vertical_align => TextVerticalAlignBaseline, :direction => vector, :normal => normal}
        draw_text(view, point, vector.length.to_s, options)
        view.draw_points(line, 10, 1, "red")
      end
      def draw_text(view, point, text)
        options[:position] = point
        char_loops = convert(text, options)
        triangles = []
        char_loops.each do |_i, loops|
          unless loops
            next
          end
          triangles << Geom.tesselate(loops.first, *loops[1..-1])
        end
        view.draw(GL_TRIANGLES, triangles.flatten)
      end
      def draw2d_text(view, point, text)
        options[:position] = point
        char_loops = convert(text, options)
        triangles = []
        char_loops.each do |_i, loops|
          unless loops
            next
          end
          triangles << Geom.tesselate(loops.first, *loops[1..-1])
        end
        view.draw2d(GL_TRIANGLES, triangles.flatten.map do |pt|
  view.screen_coords(pt)
end)
        view.draw(GL_TRIANGLES, triangles.flatten)
        char_loops
      end
      def inspect
        name = self.class.name.split("::").last
        module_name = self.class.name.split("::")[-2]
        hex_id = format("0x%x", object_id << 1)
        "#<#{module_name}::#{name}:#{hex_id}-[#{@typeface[:familyName]}]>"
      end
    end
  end
end
