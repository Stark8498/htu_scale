module TRINH_VAN_PHUC::HTU_ScalePlus
  class << self
    attr_accessor(:active)
    attr_reader(:cmd_reset, :cmd_xyz, :cmd_x, :cmd_y, :cmd_z, :cmd_dim, :cmds)
  end
  BEHAVIOR_SECTION = "htu_behavior".freeze
  BEHAVIOR_ALL = 0

  # Which scale handles SketchUp shows, remembered machine-wide. The six toolbar
  # buttons set it; #apply_behavior puts it on whatever gets selected next, which
  # is what makes the choice outlive the component, the file and the session.
  def self.behavior_state
    Sketchup.read_default(BEHAVIOR_SECTION, "state", BEHAVIOR_ALL).to_i
  rescue StandardError
    BEHAVIOR_ALL
  end

  # Sets the mode, and puts it on whatever happens to be selected right now.
  #
  # It no longer reads the selection to decide anything. It used to compare the
  # selected component's own mask, which meant the button needed exactly one
  # component selected to work at all -- fine when the mask belonged to that
  # component, wrong now that the mode is a preference. Picking a mode with
  # nothing selected is a perfectly reasonable thing to do.
  def self.set_behavior(state)
    # Pressing the button that is already on means "off", back to all handles.
    if behavior_state == state && state != BEHAVIOR_ALL
      state = BEHAVIOR_ALL
    end
    Sketchup.write_default(BEHAVIOR_SECTION, "state", state)
    apply_behavior
    repick_scale_tool
    state
  end

  # Forces SketchUp's Scale tool to read the mask again.
  #
  # It does not re-read no_scale_mask while it stays the active tool, and
  # send_action("selectScaleTool:") on the tool that is ALREADY running is a no-op.
  # So the mask #apply_behavior had just written was never picked up: the first press
  # of a behaviour button did nothing visible, and pressing a second button and
  # coming back looked like the fix -- that press happened to land while a different
  # tool held the stack, which turned the re-pick into a real tool change.
  #
  # Out through Select and straight back is a real change every time. The two places
  # that could never afford to get this wrong -- ScalePPTool#apply_dim_value and
  # dims.rb -- have always done exactly this. set_behavior was the odd one out.
  def self.repick_scale_tool
    model = Sketchup.active_model
    # The trip through Select is a tool change as far as the observer can tell, and
    # unwrapping there would explode the wrapper the user is still scaling and cost
    # two undo steps for one button press. Only this deliberate round trip is
    # excused; a real departure still unwraps.
    GroupLock.suspend { model.select_tool(nil) }
    Sketchup.send_action("selectScaleTool:")
    true
  rescue StandardError => e
    p(e)
    false
  end

  # Applies the remembered mode to a component as it is selected, so a new file
  # or a fresh SketchUp starts out in the mode last chosen instead of back on
  # all handles.
  #
  # Writing only when the mask actually differs matters more than it looks: this
  # runs on every selection change, and an unconditional write would dirty the
  # model and push an undo step each time the user clicked something.
  def self.apply_behavior(selection = Sketchup.active_model.selection)
    state = behavior_state
    objects = selection.to_a.select { |e| e.respond_to?(:definition) }
    changed = objects.reject do |object|
      object.definition.behavior.no_scale_mask? == state
    end
    if changed.empty?
      return 0
    end
    model = Sketchup.active_model
    model.start_operation("Scale Handles", true)
    changed.each { |object| object.definition.behavior.no_scale_mask = state }
    model.commit_operation
    changed.size
  rescue StandardError => e
    p(e)
    0
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
    # Checked against the remembered mode, not against the selected component's
    # own mask, and never grayed. These used to be dead unless exactly one
    # component was selected -- which read as "broken" far more often than it
    # read as "not applicable", and is simply the wrong question now that the
    # mode is a preference the user can set at any time.
    cmds.each do |cmd, val|
      cmd.set_validation_proc do
        behavior_state == val ? MF_CHECKED : MF_ENABLED
      end
    end
    cmds[@cmd_dim] = 0
    @cmds = cmds
  end

  # Which of them get a toolbar button.
  #
  # All six stay in the menu -- that is the only place Preferences > Shortcuts
  # looks, and a key is the whole point of the per-axis ones. On the toolbar they
  # were six near-identical cubes to read at a glance, and only two get pressed
  # by hand: the lock, and the way back off it.
  def self.toolbar_cmds
    [@cmd_reset, @cmd_xyz, @cmd_dim].compact
  end
  def self.toggle
    PLUGIN.active_overlay.enabled = !PLUGIN.active_overlay.enabled?
  end
  def self.active?
    @active
  end
  # scale_factor= and verify_ui_scale lived here to size the radial pet toolbar.
  # Every consumer of SCALE_FACTOR was inside radial_menu/, so both went with the
  # toolbar. Dimension text sizes itself from view.pixels_to_model instead.
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
        # numpts is an Integer (text_geometry passes 6), so `1 / numpts` was
        # integer division -> 0. Every sample landed on t = 0, collapsing each
        # quadratic segment onto its start point: glyphs lost every curve and
        # the dimension text rendered as broken strokes.
        dt = 1.0 / numpts
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
