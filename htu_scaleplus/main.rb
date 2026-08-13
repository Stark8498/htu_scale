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
    # $VERBOSE nil around this one call, restored immediately, even if it raises.
    #
    # SketchUp 2026 prints
    #
    #   main.rb:55: warning: Sketchup.send_action is deprecated and not being maintained.
    #
    # every time. That was tolerable while only a button press reached here. The mask
    # repair reaches it on every drag that loses the mask -- which is every drag with a
    # lock on -- so the user's Ruby Console filled up with the same line, three times in
    # one probe run.
    #
    # There is no replacement to move to: Model#select_tool takes Ruby tools only, and
    # nothing else in the API activates SketchUp's OWN Scale tool. The deprecation has
    # been read and is written down in docs/HANDOFF.md; silencing a line that repeats per
    # drag is not the same as not knowing about it.
    #
    # UNVERIFIED, and safe either way: this works only if SketchUp emits the notice
    # through rb_warn, which honours $VERBOSE. If it writes to the console directly the
    # line simply stays and nothing else changes.
    verbose = $VERBOSE
    begin
      $VERBOSE = nil
      Sketchup.send_action("selectScaleTool:")
    ensure
      $VERBOSE = verbose
    end
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
    changed = behavior_drift(selection)
    if changed.empty?
      return 0
    end
    model = Sketchup.active_model
    model.start_operation("Scale Handles", true)
    write_behavior(changed)
    model.commit_operation
    changed.size
  rescue StandardError => e
    p(e)
    0
  end
  # Which selected objects are not already in the remembered mode. Split out so a
  # caller that must NOT open an operation can still ask the question -- see
  # #reassert_behavior, where opening one crashed SketchUp.
  def self.behavior_drift(selection = Sketchup.active_model.selection)
    state = behavior_state
    selection.to_a.select { |e| e.respond_to?(:definition) }.reject do |object|
      object.definition.behavior.no_scale_mask? == state
    end
  end
  def self.write_behavior(objects, state = behavior_state)
    objects.each { |object| object.definition.behavior.no_scale_mask = state }
    objects.size
  end
  # Puts the chosen mode back after a scale drag, if the drag lost it.
  #
  # #apply_behavior only ever ran on a selection CHANGE, and letting go of a grip is
  # not one: the same object stays selected, so nothing looked at the mask again. That
  # was fine as long as scaling left the mask alone, and it does not.
  #
  # Measured in SketchUp 2026 with dev/htu_mask_probe.rb rather than reasoned, because
  # reasoning about it was wrong once. On a single ComponentInstance the mask goes 120
  # -> 0 across the release while the definition's object_id stays the SAME. So
  # SketchUp clears no_scale_mask on the very definition it was set on, when the scale
  # commits. This comment used to say make_unique handed the object a fresh definition
  # carrying default behavior; that would have shown a different id, and it did not.
  #
  # Still written so it does not matter which way the mask was lost: #apply_behavior
  # reads `object.definition` fresh on every call, so a cleared mask and a definition
  # swapped out from under the object are repaired alike. Keeping that costs nothing,
  # and one reading on one SketchUp version on one kind of object is not enough to
  # narrow it.
  #
  # Costs nothing when nothing drifted, which is every drag once this is right:
  # nothing to write means no tool re-pick, and a re-pick on every grip release would
  # be felt.
  #
  # ---- WHY THIS DOES NOT RUN WHEN THE GRIP IS RELEASED ----
  #
  # The first version did, on a UI.start_timer(0) from onToolStateChanged, and it
  # CRASHED SketchUp on every drag. SketchUp's own log said why, in plain English:
  #
  #   Start(Scale)Commit(9)
  #   Start(Macro)New operation ("Scale Handles") started while an existing
  #   operation ("Scale") was still open
  #
  # "Scale Handles" is #apply_behavior's operation. So the native Scale tool's own
  # operation is STILL OPEN when state 0 arrives and still open one timer tick later,
  # and starting an operation inside another one is what took SketchUp down.
  #
  # Two things follow, and both are load-bearing:
  #
  #   1. The release only ARMS this (ScalePP2_ToolsOb#scale_finished sets the flag and
  #      does nothing else). The repair is triggered by the overlay's #onMouseMove,
  #      which SketchUp does not deliver in the middle of committing a drag. In
  #      practice that is the same instant -- the hand that let go of the grip is
  #      still moving.
  #
  #      But NOT run there. An overlay callback may not touch the model at all, which
  #      is SketchUp's own rule and it says so:
  #
  #        RuntimeError: no model changes should be made during overlay callbacks
  #
  #      That was the second failed attempt: the repair ran, the write raised, the
  #      rescue below swallowed it, and the only symptom was grips that stayed wrong.
  #      So #reassert_behavior_if_pending hands the work to a timer -- a timer callback
  #      is not an overlay callback, and by then the drag is long committed, so neither
  #      of the two rules is broken.
  #   2. On the single-object path it writes the mask WITHOUT opening an operation,
  #      through #write_behavior rather than #apply_behavior. Belt and braces: if the
  #      safe moment is ever wrong again, a bare write cannot nest, so the worst case
  #      is an untidy undo entry instead of a crash.
  #
  # The multi-object path does NOT get that second protection and cannot: GroupLock has
  # to group entities, and #build_wrapper opens an operation to do it. So that branch
  # rests entirely on the mouse move being a safe moment. Worth knowing if a crash ever
  # comes back with two or more objects selected.
  def self.reassert_behavior
    model = Sketchup.active_model
    unless model && model.valid?
      return false
    end

    # A selection of several objects has no definition of its own to carry a mask, so
    # for it the repair is the wrapper, not the write -- writing the mask onto each
    # object again would leave the union cage ungoverned, which is the whole reason
    # GroupLock exists. Nothing happens here unless a wrapper is genuinely missing:
    # #wrappable? refuses while one is live, below two objects, and in all-handles
    # mode. #wrap re-picks the tool itself.
    if GroupLock.wrap(model)
      return true
    end

    changed = behavior_drift(model.selection)
    if changed.empty?
      return false
    end
    write_behavior(changed)

    # The mask was just rewritten under a Scale tool that has already read the old
    # one, and it does not look again while it stays the active tool. Same reason
    # #set_behavior cannot get away with a bare send_action.
    repick_scale_tool
    true
  rescue StandardError => e
    p(e)
    false
  end
  # Set by the grip release, read and cleared by the next mouse move. A plain flag
  # rather than a timer, because a timer is what fired inside the Scale tool's open
  # operation and crashed SketchUp.
  def self.behavior_repair_pending!
    @behavior_repair_pending = true
  end
  # Called from the overlay's #onMouseMove, so it must not touch the model itself --
  # SketchUp raises "no model changes should be made during overlay callbacks" on
  # anything that tries. All it does is hand the job to a timer, whose callback is
  # under no such rule.
  #
  # The delay is 0 and that is not a race: the mouse move it comes from has already
  # proved SketchUp is dispatching input, which it does not do while committing a drag.
  # A timer straight from the RELEASE was a different story and crashed SketchUp -- see
  # #reassert_behavior.
  def self.reassert_behavior_if_pending
    unless @behavior_repair_pending
      return false
    end

    # Cleared BEFORE the repair is scheduled, not after it runs: #reassert_behavior
    # re-picks the tool, and anything that raised with the flag still set would be
    # retried on every single mouse move from then on.
    @behavior_repair_pending = false
    id = UI.start_timer(0, false) do
      UI.stop_timer(id)
      reassert_behavior
    end
    true
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
