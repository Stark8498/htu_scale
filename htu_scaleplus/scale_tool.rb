module TRINH_VAN_PHUC::HTU_ScalePlus
  def self.toggle_tool(status)
    tool = PLUGIN.active_overlay.tools.find do |t|
  t.tool_name == "ScaleTool"
end
    tool.active = status
    Sketchup.active_model.active_view.invalidate
  end
  # Kept as the public names other files already call (dims.rb, set_dim_value);
  # DimFavorites owns the storage rules now.
  def self.save_dim_to_object(len, value, object)
    DimFavorites.add(object, len, [value])
  end
  def self.object_dims(object, len)
    DimFavorites.list(object, len)
  end
  def self.clear_object_dims(object, len)
    DimFavorites.clear(object, len)
  end
  class ScalePPTool < Tool
    attr_reader(:data_dims)
    attr_accessor(:on_push_tool)
    attr_reader(:bb_data)
    # Axis ("lenx"/"leny"/"lenz") whose dimension is locked for VCB entry, or
    # nil. The axis is held rather than the dim itself because @data_dims is
    # rebuilt whenever the camera moves -- a held hash would carry stale
    # geometry, and orbiting mid-entry would then scale by the wrong amount.
    attr_reader(:locked_axis)
    # What has been typed into the locked dimension, and whether the keyboard
    # could be mirrored at all. nil buffer = nothing typed yet = drawn selected.
    attr_reader(:edit_buffer, :edit_echo)
    # Text-selection colours for the in-place editor. Deliberately not the
    # dimension's own red/green/blue: a filled badge in the axis colour is what
    # the heavy locked outline used to look like, and it read as decoration
    # rather than as selected text. A neutral highlight blue reads as selection
    # on all three axes.
    EDIT_FILL  = [51, 133, 224].freeze
    EDIT_TEXT  = [255, 255, 255].freeze
    EDIT_CARET = [40, 40, 40].freeze
    def initialize(overlay)
      super
      @overlay = overlay
      @tool_name = "ScaleTool"
      @tool_state = 0
      @on_push_tool = false
      @locked_axis = nil
      @edit_buffer = nil
      @edit_echo = true
      @model = Sketchup.active_model
      @selection = @model.selection
      @view = @model.active_view
    end
    # Compared against @active, not against #active?.
    #
    # #active? is `@active || this tool is on the stack`, so while the tool held
    # the stack `active = true` saw "already true" and returned without ever
    # setting the flag. The tool then drew only for as long as it stayed on top of
    # the stack, and a camera tool taking that spot made it vanish. Normalised to
    # true/false first because @active starts out nil, and `false == nil` is not
    # the no-op the old comparison happened to make it.
    def active=(status)
      status = status ? true : false
      if status == (@active ? true : false)
        return
      end
      @active = status
      if active?
        activate
      else
        deactivate(Sketchup.active_model.active_view)
      end
      DimsUI.toggle_active(active?)
    end
    def active_itself?
      @model.tools.active_tool == self
    end
    def activate
      @model = Sketchup.active_model
      @view = @model.active_view
      @selection = @model.selection
      if @on_push_tool
      else
        reset
        redraw(@view)
      end
      @on_call_back = false
    end
    def reset
      @dims = nil
      @data_dims = nil
      @store_bb = nil
      @state = nil
    end
    def deactivate(view)
      # SketchUp calls this for two very different things, and they must not be
      # treated alike: the user leaving the Scale tool, and this tool being popped
      # off the stack after its own push. The second happens constantly -- every
      # time the cursor comes back over the grips, #call_back pops it.
      if @on_push_tool
        @on_push_tool = false
      end
      unlock_axis
      @selected = []
      store_bounds_points
    end
    def onToolStateChanged(tool_state)
      unless @overlay.enabled?
        return
      end
      @tool_state = tool_state
      if @tool_state == 1
        @data_dims.each do |dim|
          if dim
            dim[:hover] = false
          end
        end
      end
      UI.start_timer(0.0099999999983992893, false) do
        redraw(@view)
        @view.invalidate
      end
    end
    def store_bounds_size
      unless @bb_points
        return
      end
      lenx = @bb_points[0].distance(@bb_points[1])
      leny = @bb_points[0].distance(@bb_points[2])
      lenz = @bb_points[0].distance(@bb_points[4])
      @store_bb = [lenx, leny, lenz]
      @state = nil
    end
    def get_state
      unless @store_bb && @bb
        return
      end
      lenx = @bb_points[0].distance(@bb_points[1])
      leny = @bb_points[0].distance(@bb_points[2])
      lenz = @bb_points[0].distance(@bb_points[4])
      sizes = [[@store_bb[0], lenx], [@store_bb[1], leny], [@store_bb[2], lenz]]
      changes = sizes.each_with_index.find_all do |ar, i|
  ar[0] != ar[1]
end
      if changes.empty?
        changes = nil
      end
      changes
    end
    def redraw(view)
      pick_object = false
      if @selected != @selection.to_a
        @selected = @selection.to_a
        pick_object = true
      end
      store_bounds_points
      if pick_object
        store_bounds_size
      else
        @state = get_state
      end
      compute_dimensions(view, true)
    end
    def suspend(view)
      view.invalidate
    end
    def resume(view)
      view.invalidate
    end
    def selection_changed?
      @model.selection.to_a != @selected
    end
    def bounds_changed?
      bounds_points = @bb_points.clone
      new_bb = compute_selected_bounds
      bounds_points != new_bb[:points]
    end
    def on_hover?
      @data_dims && @data_dims.find do |d|
  d && d[:hover]
end
    end
    def hovered_dim
      unless @data_dims
        return
      end
      @data_dims.find do |d|
        d && d[:hover]
      end
    end
    # Which model axis a dimension runs along. The parallel? chain used to be
    # repeated at every call site; the menu and the VCB path both need it.
    def dim_axis(dim)
      unless dim && dim[:line] && @tr_bb
        return
      end
      vec = dim[:line][1] - dim[:line][0]
      unless vec.valid?
        return
      end
      if vec.parallel?(@tr_bb.xaxis)
        "lenx"
      elsif vec.parallel?(@tr_bb.yaxis)
        "leny"
      elsif vec.parallel?(@tr_bb.zaxis)
        "lenz"
      end
    end
    def onMouseMove(flags, x, y, view)
      @mouse = [x, y]
      unless active?
        return
      end
      if @tool_state == 0 && @data_dims
        @data_dims.each do |dim|
          unless dim
            next
          end
          hover = dim[:hover]
          dim[:hover] = Geom.point_in_polygon_2D(@mouse, dim[:bb_text_2d], true)
          if hover != dim[:hover]
            view.invalidate
          end
        end
      end
      # While an axis is locked the tool must survive the cursor leaving the
      # dimension text, otherwise a nudge of the mouse would discard whatever
      # the user has typed into the VCB.
      if @on_push_tool && !on_hover? && !@locked_axis
        return call_back
      end
      unless bounds_changed?
        return
      end
      if @tool_state == 1 || selection_changed?
        redraw(view)
      end
    end
    def call_back
      @on_call_back = true
      @model.tools.pop_tool
    end
    # Clicking a dimension locks its axis and hands the VCB over, replacing the
    # old modal "Resize Entity" inputbox. A click anywhere else releases the lock
    # and hands the stack straight back, so the click lands on SketchUp's own Scale
    # tool -- this tool is only ever on the stack because the cursor was over a
    # label, and off a label it has no business with the mouse.
    def onLButtonDown(flags, x, y, view)
      dim = hovered_dim
      if dim
        return lock_axis(dim_axis(dim), dim)
      end
      unlock_axis
      call_back
    end
    def lock_axis(axis, dim = nil)
      unless axis
        return
      end
      @locked_axis = axis
      # nil means "nothing typed yet", which is what draws the number selected.
      # The first keystroke turns it into a string and the selection gives way
      # to the typed text, the way replacing a selection works in a text field.
      @edit_buffer = nil
      @edit_echo = true
      dim ||= dim_for_axis(axis)
      length = dim && dim[:line].first.distance(dim[:line].last)
      Sketchup.set_status_text("Len#{axis[-1].upcase}", SB_VCB_LABEL)
      Sketchup.set_status_text(length ? length.to_s : "", SB_VCB_VALUE)
      Sketchup.set_status_text("Type a length and press Enter. Esc to cancel.", SB_PROMPT)
      @view.invalidate
    end
    def unlock_axis
      unless @locked_axis
        return
      end
      @locked_axis = nil
      @edit_buffer = nil
      @edit_echo = true
      Sketchup.set_status_text("", SB_VCB_LABEL)
      Sketchup.set_status_text("", SB_VCB_VALUE)
      Sketchup.set_status_text("", SB_PROMPT)
      if @view
        @view.invalidate
      end
    end
    def dim_for_axis(axis)
      unless @data_dims
        return
      end
      @data_dims.find do |d|
        d && dim_axis(d) == axis
      end
    end
    # VCB entry. An unreadable or non-positive value keeps the lock so the user
    # can simply retype instead of having to re-click the dimension.
    def onUserText(text, view = @view)
      unless @locked_axis
        return
      end
      begin
        value = text.to_s.strip.to_l
      rescue StandardError
        value = nil
      end
      if value.nil? || value.to_f <= 0
        UI.beep
        return lock_axis(@locked_axis)
      end
      apply_dim_value(@locked_axis, value)
    end
    def onCancel(reason, view)
      unlock_axis
      if @on_push_tool
        call_back
      end
    end
    # Virtual-key -> character, for echoing what is typed onto the dimension
    # itself. Only the keys a length can be written with are listed; everything
    # else switches the echo off rather than guessing (see #onKeyDown).
    EDIT_KEYS = {
      8 => :backspace,
      46 => :delete,
      48 => "0", 49 => "1", 50 => "2", 51 => "3", 52 => "4",
      53 => "5", 54 => "6", 55 => "7", 56 => "8", 57 => "9",
      96 => "0", 97 => "1", 98 => "2", 99 => "3", 100 => "4",
      101 => "5", 102 => "6", 103 => "7", 104 => "8", 105 => "9",
      110 => ".", 190 => ".", 188 => ",",
      109 => "-", 189 => "-",
      106 => "*", 111 => "/",
    }.freeze
    # Keys that belong to SketchUp, not to the edit buffer: modifiers, Enter,
    # Esc, arrows, function keys. Listing them stops a harmless Shift press from
    # tripping the "unknown key" bail-out below.
    EDIT_IGNORED = [9, 13, 16, 17, 18, 20, 27, 33, 34, 35, 36,
                    37, 38, 39, 40, 45, 91, 92, 93, 144, 145].freeze
    # The dimension is the text field while an axis is locked, so what the user
    # types has to appear on it. SketchUp gives no way to read the VCB as it is
    # being filled, so the keystrokes are mirrored here.
    #
    # This is a PREVIEW ONLY -- onUserText applies the VCB's own text on Enter,
    # so a mismatched echo can never resize by the wrong amount. Key codes are
    # virtual keys, which do not track the keyboard layout: on a layout where a
    # digit needs Shift, or under an IME, the mirror would lie. So an
    # unrecognised key gives up on the echo for the rest of the entry and the
    # VCB is left as the only display, rather than showing something wrong.
    def onKeyDown(key, repeat, flags, view)
      unless @locked_axis && @edit_echo
        return
      end
      entry = edit_char(key)
      if entry.nil?
        unless EDIT_IGNORED.include?(key) || (112..135).cover?(key)
          @edit_echo = false
          view.invalidate
        end
        return
      end
      buffer = @edit_buffer || ""
      if entry == :backspace
        buffer = buffer[0...-1].to_s
      elsif entry == :delete
        buffer = ""
      else
        buffer += entry
      end
      @edit_buffer = buffer
      view.invalidate
      nil
    end
    # Letters are their ASCII uppercase as virtual keys, so unit suffixes can be
    # mirrored too. Separate from EDIT_KEYS to keep that table about digits.
    def edit_char(key)
      if (65..90).cover?(key)
        return key.chr.downcase
      end
      EDIT_KEYS[key]
    end
    # The single apply path, shared by the VCB and by the saved sizes in the
    # context menu.
    def apply_dim_value(axis, value)
      axis = axis.to_s
      unlock_axis
      @model.start_operation("Resize", true)
      set_dim(axis, value)
      @model.commit_operation
      Sketchup.active_model.select_tool(nil)
      Sketchup.send_action("selectScaleTool:")
    end
    def set_dim_value(dim, value)
      line = dim[:line]
      vec = dim[:line][0].vector_to(dim[:line][1])
      len = dim[:line].first.distance(dim[:line].last)
      scale_x = 1
      scale_y = 1
      scale_z = 1
      if vec.parallel?(@tr_bb.xaxis)
        scale_x = value / len
        name = "lenx"
      elsif vec.parallel?(@tr_bb.yaxis)
        scale_y = value / len
        name = "leny"
      elsif vec.parallel?(@tr_bb.zaxis)
        scale_z = value / len
        name = "lenz"
      end
      if @model.selection.length == 1 && @model.selection[0].respond_to?(:definition)
        tr = Geom::Transformation.scaling(scale_x, scale_y, scale_z)
        @model.selection[0].transformation *= tr
        save_dim_to_object(name, value, @model.selection[0])
      else
        point = line[0].project_to_line([@bb_center, vec])
        tr = Geom::Transformation.scaling(point, scale_x, scale_y, scale_z)
        @model.active_entities.transform_entities(tr, @model.selection.to_a)
        # The branch above has saved the size to the list since Curic Scale++, which
        # is where "type a size and it joins the saved list" already comes from. This
        # branch did not, so the same keystrokes did or did not fill the list
        # depending on how many objects happened to be selected. The size typed
        # against a multi-object bounding box is still a size this workshop works
        # to, and the list is machine-wide, not a property of the one object -- so
        # there is nothing about a group selection that makes it belong less.
        #
        # nil object: no single definition to read a legacy attribute off, and
        # DimFavorites only uses the object for that one-time import.
        if name
          save_dim_to_object(name, value, nil)
        end
      end
    end
    def set_dim(len, value, redraw_dc = true)
      begin
        begin
          unless active?
            return
          end
          unless @data_dims
            return
          end
          dim = @data_dims.find do |d|
  unless d
    next
  end
  line = d[:line]
  vec = line[1] - line[0]
  case len
  when "lenx"
    vec.parallel?(@tr_bb.xaxis)
  when "leny"
    vec.parallel?(@tr_bb.yaxis)
  when "lenz"
    vec.parallel?(@tr_bb.zaxis)
  end
end
          unless dim
            return
          end
          set_dim_value(dim, value)
          if redraw_dc
            dc_redraw
          end
        rescue => exception
          p(exception)
        end
      ensure
      end
    end
    def dc_redraw
      begin
        ob = ObjectSpace.each_object(DCObservers::DCToolsObserver).to_a[0]
        unless ob
          return
        end
        dc_observers = ob.instance_variable_get(:@dcobservers)
        unless $dc_observers && $dc_observers == dc_observers
          return
        end
        ob.instance_variable_set(:@started_tool, true)
        ob.onToolStateChanged(@model.tools, @tool_name, 21236, 0)
      rescue => exception
        p(exception)
      end
    end
    def save_dim_to_object(len, value, object)
      begin
        PLUGIN.save_dim_to_object(len, value, object)
      rescue => exception
        p(exception)
      end
    end
    def object_dims(object, len)
      PLUGIN.object_dims(object, len)
    end
    def clear_object_dims(object, len)
      PLUGIN.clear_object_dims(object, len)
    end
    # #referenced_dims and #same_dc_definition were here. They answered "what sizes
    # is this same component already built at elsewhere?" and fed the context menu's
    # "Referenced Dimensions" block, which was removed on request -- the sizes it
    # turned up were whatever the neighbouring instances had been dragged to, so it
    # offered values like "~ 592" that nobody chose on purpose.
    #
    # Utils#definition_paths and #get_path were the walk underneath them and have no
    # caller left. They stay, unused, the way listbox.rb does: they are the original
    # plugin's own utilities, not something added for this.
    def onLButtonUp(flags, x, y, view)
    end
    # No #onSetCursor on purpose. SketchUp asks the tool on top of the stack what the
    # cursor should be, and a tool that does not answer leaves whatever was set last
    # -- the Scale tool's own arrow-with-a-grip-box. That is what the user wants back,
    # so the way to keep it is to stay silent here.
    #
    # It was briefly answered with the plain arrow (id 0), on the reasoning that the
    # grip cursor lies wherever this tool holds the stack: outside the padded box a
    # click retargets, over a label it edits a number. True, and not wanted -- the icon
    # says "Scale++ is running", which is worth more than being literal about what the
    # next click does. See Overlay#onMouseLeave for the other half that was removed.
    def getExtents
      bb = Sketchup.active_model.bounds
      bb
    end
    def compute_dimensions(view = Sketchup.active_model.active_view, redraw = false)
      @dims = compute_dimensions_lines(view)
      unless @dims && !@dims.empty?
        return
      end
      if redraw
        redraw_dim_data(view)
      end
    end
    def store_bounds_points
      @bb_data = compute_selected_bounds
      @bb = @bb_data[:bounds]
      @tr_bb = @bb_data[:tr]
      @bb_center = @bb_data[:center]
      @bb_points = @bb_data[:points]
      @bb_lines = @bb_data[:lines]
    end
    def selected_bounds
      entities = @selection.reject do |e|
  e.respond_to?(:locked?) && e.locked?
end
      h = {}
      if entities.empty?
        return nil
      end
      object = entities[0]
      tr = IDENTITY
      if entities.length == 1 && object.respond_to?(:definition)
        bb = object.is_a?(Sketchup::Group) ? object.local_bounds : object.definition.bounds
        tr = object.transformation
      else
        bb = Geom::BoundingBox.new
        entities.each do |e|
          bb.add(e.bounds)
        end
      end
      [bb, tr]
    end
    def compute_selected_bounds
      @model = Sketchup.active_model
      @selection = @model.selection
      compute_bounds_for(@selection.reject do |e|
  e.respond_to?(:locked?) && e.locked?
end)
    end
    # Everything derived from a bounding box -- corners, edges, centre lines, the
    # handle set the mask allows -- for ANY list of entities rather than for the
    # selection specifically.
    #
    # Split out so the object under the cursor is measured by exactly the code
    # that measures the selected one. A second implementation for hover labels
    # could disagree with the real thing, and a number that changes when you
    # click is worse than no number.
    def compute_bounds_for(entities)
      entities = entities.to_a
      h = {}
      if entities.empty?
        return h
      end
      object = entities[0]
      tr = IDENTITY
      if entities.length == 1 && object.respond_to?(:definition)
        bb = object.is_a?(Sketchup::Group) ? object.local_bounds : object.definition.bounds
        tr = object.transformation
        no_scale_mask = object.definition.behavior.no_scale_mask?
        h[:control_mask] = true
      else
        bb = Geom::BoundingBox.new
        entities.each do |e|
          bb.add(e.bounds)
        end
        no_scale_mask = 0
        h[:control_mask] = false
      end
      h[:bounds] = bb
      h[:tr] = tr
      h[:lines] = bounds_lines(bb, tr)
      h[:center] = bb.center.transform(tr)
      h[:points] = bound_points(bb).map do |pt|
  pt.transform(tr)
end
      h[:centers] = bounds_centers(bb, tr)
      h[:center_lines] = bounds_center_lines(bb, tr)
      all = 0
      xyz = 120
      x = 126
      y = 125
      z = 123
      h[:all] = h[:points] + h[:lines].map do |l|
  midpoint(l)
end + h[:centers]
      h[:xyz] = h[:center_lines].flatten
      h[:x] = h[:center_lines][0]
      h[:y] = h[:center_lines][1]
      h[:z] = h[:center_lines][2]
      case no_scale_mask
      when all
        scale_points = h[:all]
      when xyz
        scale_points = h[:xyz]
      when x
        scale_points = h[:x]
      when y
        scale_points = h[:y]
      when z
        scale_points = h[:z]
      end
      h[:scale_points] = scale_points
      h
    end
    def get_dim_line(vec, lines, bb_data = @bb_data)
      plines = lines.find_all do |l|
  l[0].vector_to(l[1]).valid? && l[0].vector_to(l[1]).parallel?(vec)
end
      sort_line = bounds_center_lines(bb_data[:bounds], bb_data[:tr])[2]
      plines = sort_lines_by_line(plines, sort_line.reverse)
      plines.first
    end
    # bb_data rather than the ivars, so a second box can be measured without
    # swapping @bb/@bb_points out from under #draw -- which runs on the same
    # ivars every frame, and would draw the wrong box for as long as the swap
    # lasted. The camera is read off the view passed in for the same reason.
    def compute_dimensions_lines(view = Sketchup.active_model.active_view, bb_data = @bb_data)
      direction = view.camera.direction
      points = bb_data && bb_data[:points]
      unless points && !points.empty?
        return
      end
      center = bb_data[:center]
      dims = []
      lines = bb_data[:lines].clone
      lines.sort_by! do |l|
        midpoint(l).distance(view.camera.eye)
      end
      vecx = points[0].vector_to(points[1])
      vecy = points[1].vector_to(points[3])
      vecz = points[0].vector_to(points[4])
      if vecx.valid?
        line = get_dim_line(vecx, lines, bb_data)
        vec_offset = vecy.valid? ? vecy.reverse : vecz.cross(vecx)
        if vec_offset.angle_between(direction).radians < 90
          vec_offset.reverse!
        end
        if vec_offset.parallel?(direction)
          vec_offset = view.camera.up
        end
        dims << [line, vec_offset]
      else
      end
      if vecy.valid?
        line = get_dim_line(vecy, lines, bb_data)
        vec_offset = vecx.valid? ? vecx : vecz.cross(vecy)
        if vec_offset.angle_between(direction).radians < 90
          vec_offset.reverse!
        end
        if vec_offset.parallel?(direction)
          vec_offset = view.camera.up
        end
        dims << [line, vec_offset]
      else
      end
      # parallel?(vecz), not parallel?(Z_AXIS). The whole branch offsets the label by
      # vecz.cross(direction), which collapses to a zero-length vector exactly when
      # the camera looks ALONG the box's third edge -- and the box's third edge is
      # the world Z axis only while the object is unrotated. Testing the world axis
      # got both cases wrong:
      #
      #   - a component rotated so its third edge lies horizontal lost that label in
      #     plan view, though there was nothing wrong with drawing it. A whole
      #     dimension simply absent, and with it any way to retype that size.
      #   - looking down that rotated edge sailed past the guard and built the label
      #     off a zero vector.
      #
      # The x and y branches have carried the equivalent test all along -- they fall
      # back to camera.up when their offset comes out parallel to the view.
      if vecz.valid? && !direction.parallel?(vecz)
        line = [points[0], points[4]]
        ls = lines.find_all do |l|
  l[0].vector_to(l[1]).valid? && l[0].vector_to(l[1]).parallel?(vecz)
end
        vec = vecz.cross(direction)
        ls = sort_lines_by_line(ls, [center, vec])
        line = ls.first
        vec_offset = vecz.cross(direction)
        dims << [line, vec_offset]
      else
      end
      dims
    end
    def redraw_dim_data(view)
      unless @dims && !@dims.empty?
        return
      end
      @offset = view.pixels_to_model(20, @bb_center)
      @data_dims = build_dim_data(view, @dims, @bb_data)
    end
    # Text, boxes and witness lines for one set of dimension lines.
    #
    # bb_data is a parameter rather than read off @bb_data so a second box could be
    # measured without swapping the ivars #draw runs on every frame. Only the
    # selection's box is measured now, but the parameter stays: the swap-and-restore
    # it replaced is the kind of thing that draws the wrong box for as long as it
    # lasts, and there is nothing to gain by inviting it back.
    def build_dim_data(view, dims, bb_data)
      center = bb_data[:center]
      point = dims.map(&:first).flatten.find do |pt|
  point_inside_screen?(view, pt)
end
      point ||= center
      dim_offset = view.pixels_to_model(20, point)
      data = dims.map do |ar|
  unless ar
    next
  end
  line, vector_offset = ar
  unless line[0].vector_to(line[1]).valid?
    next
  end
  unless vector_offset.valid?
    next
  end
  parse_dimemsion_geometry(view, line, vector_offset, true, dim_offset, bb_data)
end
      data.each do |d|
        unless d
          next
        end
        d[:color] = axis_color(d[:line], bb_data[:tr])
      end
      data
    end
    def axis_color(line, tr)
      vec = line[0].vector_to(line[1])
      if vec.parallel?(tr.xaxis)
        "red"
      elsif vec.parallel?(tr.yaxis)
        "darkgreen"
      elsif vec.parallel?(tr.zaxis)
        "blue"
      else
        "black"
      end
    end
    def parse_dimemsion_geometry(view, line, vector_offset, extension_line = true, dim_offset = 50.mm, bb_data = @bb_data)
      if extension_line
        sp, ep = line
        dim = line.map do |pt|
  pt.offset(vector_offset, 2 * dim_offset)
end
        extensions = [[sp, dim.first], [ep, dim.last]]
      else
        extensions = []
        dim = line
      end
      text = dim[0].distance(dim[1])
      point = midpoint(dim)
      point.offset!(vector_offset, dim_offset / 4)
      vector = dim.first.vector_to(dim.last)
      if vector.parallel?(bb_data[:tr].zaxis)
        vector.reverse!
      end
      normal = vector.cross(vector_offset).reverse
      if PLUGIN.settings[:dim_text_size] == PLUGIN::DIM_SMALL
        size = dim_offset * 0.75
      elsif PLUGIN.settings[:dim_text_size] == PLUGIN::DIM_LARGE
        size = dim_offset * 1.25
      else
        size = dim_offset
      end
      options = {:size => size, :align => TextAlignCenter, :vertical_align => TextVerticalAlignBaseline, :direction => vector, :normal => normal}
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
      vec = options[:direction].cross(options[:normal])
      unless vec.valid?
        return
      end
      point = pj_point.offset(vec, dim_offset / 4)
      options[:position] = point
      geometry = text_geometry(view, text.to_s, options)
      unless geometry
        return
      end
      {:line => dim, :extensions => extensions, :options => options}.merge(geometry)
    end
    # Glyph loops, triangles and the surrounding box for one string, laid out in
    # the frame `options` describes. Split out of parse_dimemsion_geometry so the
    # in-place editor can re-render a dimension with the text being typed
    # without redoing the dimension line, offsets and orientation.
    def text_geometry(view, string, options)
      char_loops = @text_typeface.convert(string, options)
      triangles = []
      char_loops.each do |_i, loops|
        unless loops
          next
        end
        triangles << Geom.tesselate(loops.first, *loops[1..-1])
      end
      pts = triangles.flatten
      if pts.empty?
        return
      end
      direction = options[:direction]
      normal = options[:normal]
      tr = Geom::Transformation.axes(options[:position], direction, normal.cross(direction), normal)
      pts = pts.map do |pt|
  pt.transform(tr.inverse)
end
      bb = Geom::BoundingBox.new.add(pts)
      tr_scale = Geom::Transformation.scaling(bb.center, 1.25)
      bb.add(pts.map do |pt|
  pt.transform(tr_scale)
end)
      rect = bottom_bound_points(bb)
      bb_text = rect.map do |pt|
  pt.transform(tr)
end
      bb_text_2d = bb_text.map do |pt|
  view.screen_coords(pt)
end
      {:text_char_loops => char_loops, :text_triangles => triangles, :bb_text => bb_text, :bb_text_2d => bb_text_2d}
    rescue StandardError => e
      # Reached from #draw on every frame while typing, where a raise would
      # turn one bad glyph into a viewport that stops redrawing. Callers treat
      # nil as "no geometry": the dimension is skipped, or the stored label is
      # kept and only the preview is lost.
      p(e)
      nil
    end
# The context menu only exists on a dimension: the tool is pushed on hover
# and pops as soon as the cursor leaves, so there is no other state it can
# be opened from. DimMenu owns the contents.
def getMenu(menu, flags, x, y, view)
  dim = hovered_dim
  unless dim
    return true
  end
  axis = dim_axis(dim)
  unless axis
    return true
  end
  length = dim[:line].first.distance(dim[:line].last)
  DimMenu.build(menu, self, selected_object, axis, length)
  true
end
    def selected_object
      s = Sketchup.active_model.selection.to_a.reject do |o|
  o.respond_to?(:locked?) && o.locked?
end
      if s.length == 1 && s[0].respond_to?(:definition)
        return s[0]
      end
    end
    def selected_size_change?
      bb, tr = selected_bounds
      unless bb
        return
      end
      lines = bounds_center_lines(bb, tr)
      lens = lines.map do |l|
  l[0].distance(l[1])
end
      lens_o = @bb_data[:center_lines].map do |l|
  l[0].distance(l[1])
end
      lens_o.each_index.find do |i|
        lens[i] != lens_o[i]
      end
    end
    def draw(view)
      begin
        unless active?
          return
        end
        unless @dims && !@dims.empty?
          return
        end
        if IS_OSX && selected_size_change?
          redraw(view)
        end
        redraw = false
        if @camera
          cam = store_camera(view)
          if cam[:up] != @camera[:up] || (cam[:target] != @camera[:target] || cam[:eye].distance(@camera[:eye]) > 10)
            redraw = true
          end
        end
        if redraw
          redraw_dim_data(view)
        end
        @camera = store_camera(view)
        if PLUGIN.show_dim?
          draw_dimensions(view)
        end
        if draw_bounds?
          draw_selected_bounds(view)
        end
        if @tool_state == 0
          draw_scale_points(view)
        end
      rescue => exception
        p(exception)
      end
    end
    # Whether to draw the Scale tool's own highlight on the bounding box -- the
    # thick yellow one that says "this is what you are scaling". Without it the box
    # drops back to the plain blue selection colour, which reads as having left the
    # Scale tool.
    #
    # Same condition as the grip fill in #draw_scale_points, because it turned out
    # to be the same loss: SketchUp drops the yellow AND the grips for every gesture
    # it reports as a tool change. They were briefly given different conditions on
    # the mistaken belief that pan kept its grips.
    def draw_bounds?
      active_itself? || PLUGIN.navigating?
    end
    # @bb can be nil while @dims is not, so the guard in #draw is not enough.
    # #deactivate nils the bounds -- store_bounds_points with an empty selection --
    # and does NOT recompute @dims, so a frame can arrive with stale dimension
    # lines and no box at all. bound_points then asks a nil box for its #width and
    # every frame ends in a rescued NoMethodError: nothing below the raise is drawn
    # and the Ruby Console fills up at frame rate.
    def draw_selected_bounds(view)
      unless @bb
        return
      end
      @bb_lines = bounds_lines(@bb, @tr_bb)
      view.line_stipple = ""
      view.drawing_color = "yellow"
      view.line_width = 3
      view.draw(GL_LINES, hack_point_draw(view, @bb_lines.flatten))
    end
    # The gray outlines here sit exactly on top of SketchUp's own scale grips,
    # which are green. Normally that is fine -- the green shows through the
    # middle. But the moment this tool takes the stack, the Scale tool stops
    # drawing and the green goes with it, leaving the outlines standing on
    # nothing: the grips read as switched off just for moving the cursor away.
    # So while this tool holds the stack it fills them in and stands in for the
    # real ones. Pure green, read off SketchUp's own grips.
    GRIP_FILL = [0, 255, 0].freeze
    def draw_scale_points(view)
      # Same stale-@dims-with-no-box case as #draw_selected_bounds above.
      unless @bb
        return
      end
      # Only while standing in for grips SketchUp has stopped drawing. When the
      # native Scale tool is drawing its own, these add nothing -- and on some
      # selections they add something worse.
      #
      # #bounds_center_lines produces the six face-centre positions. SketchUp does
      # not always offer that set: on a flat selection it collapses the pair on the
      # thin axis and drops the rest, so four grey outlines were left standing where
      # there is no grip at all, with one green grip in the middle. They read as
      # grips that had been switched off -- which is exactly what choosing XYZ on a
      # flat panel was reported as doing.
      #
      # Nothing is lost by staying quiet: SketchUp is drawing the real ones, and the
      # real ones are always right about which grips exist. The substitutes below are
      # for the case where there are none to be right about.
      unless active_itself? || PLUGIN.navigating?
        return
      end
      # The axis lock applies whether or not this tool holds the stack. It used
      # to be skipped while it did, so taking the stack put back the two axes
      # the lock had just taken away.
      entity = view.model.selection.length == 1 ? view.model.selection[0] : nil
      lines = mask_lines(bounds_center_lines(@bb, @tr_bb), entity)
      # With an axis lock the six centre-line grips ARE what SketchUp shows, so the
      # copy is faithful and the dotted axis lines belong. With no lock SketchUp shows
      # all 26, and drawing six instead made the grips visibly change in number every
      # time this tool took or gave back the stack -- reported as "the points blink
      # when I move the mouse near the object". No axis lines either: SketchUp
      # draws none, so drawing three would blink in and out the same way.
      if axis_locked?(entity)
        draw_grip_boxes(view, lines, @bb_center, true)
      else
        draw_grip_boxes(view, [], @bb_center, true, all_scale_points(lines))
      end
    end
    # Whether the selection is held to particular axes. Not the same question as
    # #mask_lines answers: that keeps all three lines both for "no lock" (0) and for
    # "xyz" (120), and those two differ in exactly the way that matters here -- xyz
    # offers six grips, no lock offers twenty-six.
    def axis_locked?(entity)
      unless entity && entity.respond_to?(:definition)
        return false
      end
      entity.definition.behavior.no_scale_mask? != 0
    rescue StandardError
      false
    end
    # The 26 positions SketchUp offers with no lock: eight corners, twelve edge
    # midpoints, six face centres. #compute_bounds_for already works this set out from
    # the mask; falling back to the centre lines keeps a box with no bb_data drawing
    # something rather than nothing.
    def all_scale_points(lines)
      points = @bb_data && @bb_data[:scale_points]
      points && !points.empty? ? points : lines.flatten
    end
    # Which of the three centre lines survive the object's own no_scale_mask. Split
    # out so the hovered object is filtered by ITS mask rather than the selection's.
    def mask_lines(lines, entity)
      unless entity && entity.respond_to?(:definition)
        return lines
      end
      x = 126
      y = 125
      z = 123
      case entity.definition.behavior.no_scale_mask?
      when x
        [lines[0]]
      when y
        [lines[1]]
      when z
        [lines[2]]
      else
        lines
      end
    end
    # `lines` are pairs whose endpoints get a grip AND a dotted axis line between them.
    # `loose_points` get a grip and nothing else, for the no-lock set where SketchUp
    # draws no axis lines.
    def draw_grip_boxes(view, lines, center, fill, loose_points = nil)
      box_lines = {}
      d = view.pixels_to_model(8, center)
      view.line_width = 1
      lines.each do |line|
        line.each do |point|
          box = create_box(point.to_a, d)
          box2d = box.map do |face|
  face.map do |pt|
    view.screen_coords(pt)
  end
end
          box_lines[line] ||= []
          box_lines[line] << box2d
        end
      end
      Array(loose_points).each do |point|
        box = create_box(point.to_a, d)
        box2d = box.map do |face|
          face.map { |pt| view.screen_coords(pt) }
        end
        # Keyed by the point itself so each grip gets its own entry; the drawing loop
        # below reads the key back as a line, so a one-point key must draw no axis.
        box_lines[[point]] ||= []
        box_lines[[point]] << box2d
      end
      # Only when there is no real grip underneath to bury. Two cases where there
      # is not: this tool holds the stack, which suspends the Scale tool, and any
      # camera navigation, during which SketchUp draws no Scale grips at all.
      #
      # Measured, not reasoned -- and the reasoning was wrong twice. A pan hides
      # the grips exactly like an orbit does: a capture of a pan shows only the gray
      # outline drawn below, with nothing green inside it. A previous version
      # narrowed this to orbit on the theory that pan kept its grips, and took them
      # away for every pan.
      #
      # navigating? asks the live tool stack rather than the observer's flag, so the
      # fill stops on the very frame the real grips come back -- the flag clears a
      # tick late, which would leave a window with both drawn.
      #
      # A scroll-wheel zoom is not a tool change, so navigating? is false, nothing
      # is painted and the real grips show through. That is what keeps this from
      # ever burying a real grip, including the colour it turns under the cursor.
      #
      # `fill` is decided by the caller now: the selection's grips fill when there
      # is no real grip underneath to bury.
      #
      # This used to draw only the six centre-line grips whatever the mask said, and
      # noted it as a known limit: with no lock SketchUp shows 26 and the other 20 were
      # absent for as long as this tool held the stack. Not a cosmetic gap -- the swap
      # is visible as a blink every time the stack changes hands.
      # #draw_scale_points now passes the set the mask actually calls for.
      box_lines.each do |line, box2ds|
        view.line_stipple = ""
        box2ds.each do |box2d|
          if fill
            view.drawing_color = GRIP_FILL
            box2d.each do |f|
              view.draw2d(GL_POLYGON, f)
            end
          end
          view.drawing_color = "gray"
          box2d.each do |f|
            view.draw2d(GL_LINE_LOOP, f)
          end
        end
        # A loose point keys a one-element "line", and GL_LINES with a single vertex
        # draws nothing useful -- skip rather than hand OpenGL half a segment.
        if line.length < 2
          next
        end
        view.line_stipple = "."
        view.drawing_color = "gray"
        view.draw2d(GL_LINES, line.map do |pt|
view.screen_coords(pt)
end)
      end
    end
    def draw_dimensions(view)
      unless @data_dims
        return
      end
      @data_dims.each do |dim|
        unless dim
          next
        end
        draw_dimension(view, dim, true)
      end
    end
    # One dimension: label box, witness lines, text, and the editor decorations.
    #
    # `editable` is false for the hovered object's labels, and it switches off
    # exactly three things -- the in-place editor, the caret, and the outline that
    # marks a label as under the cursor or locked. Everything else is shared on
    # purpose: it is the same drawing, so the two sets cannot drift apart into
    # looking like different features.
    def draw_dimension(view, dim, editable)
      # A locked dimension doubles as the text field. Before the first
      # keystroke the number is drawn selected; after it, the box carries what
      # is being typed instead -- the same replace-the-selection behaviour a
      # text field has. @edit_echo going false means the keyboard could not be
      # mirrored safely, so it falls back to a plain unselected label.
      locked = editable && @locked_axis && dim_axis(dim) == @locked_axis
      selected = locked && @edit_echo && @edit_buffer.nil?
      typed = locked && @edit_echo && @edit_buffer && !@edit_buffer.empty?
      box = typed && text_geometry(view, @edit_buffer, dim[:options]) || dim
      text_color = selected ? EDIT_TEXT : dim[:color]
      view.drawing_color = selected ? EDIT_FILL : [255, 255, 255, 150]
      view.draw2d(GL_POLYGON, box[:bb_text_2d])
      lines = []
      if dim[:extensions] && !dim[:extensions].empty?
        lines = lines + dim[:extensions]
      end
      if dim[:line] && !dim[:line].empty?
        lines << dim[:line]
      end
      view.line_stipple = ""
      view.line_width = 1
      if active_itself?
        view.drawing_color = dim[:color]
        drawVec2D(dim[:line].map do |pt|
  view.screen_coords(pt)
end, view, 5)
      else
        view.draw_points(dim[:line], 10, 3, dim[:color])
      end
      view.line_width = 1
      view.drawing_color = dim[:color]
      view.draw(GL_LINES, lines.flatten)
      view.line_stipple = "_"
      view.draw2d(GL_LINES, lines.flatten.map do |pt|
  view.screen_coords(pt)
end)
      view.drawing_color = text_color
      # An emptied buffer must draw an empty field, not the old number: the
      # box stays put but nothing is written in it.
      triangles = @edit_buffer == "" && locked && @edit_echo ? [] : box[:text_triangles]
      view.draw2d(GL_TRIANGLES, triangles.flatten.map do |pt|
  view.screen_coords(pt)
end)
      view.draw(GL_TRIANGLES, triangles.flatten)
      if locked && @edit_echo && @edit_buffer
        draw_caret(view, box[:bb_text_2d])
      end
      # The outline marks both the dimension under the cursor and the one
      # locked for VCB entry. Same weight for both: the locked dimension used
      # to be stroked at 4, and on a box only as wide as "870" that border
      # nearly closed over the text and read as a filled badge.
      unless dim[:hover] || locked
        return
      end
      view.drawing_color = dim[:color]
      view.line_stipple = ""
      view.line_width = 2
      view.draw(GL_LINE_LOOP, box[:bb_text])
      view.draw2d(GL_LINE_LOOP, box[:bb_text_2d])
    end
    # A caret at the right edge of the field, so an empty box still reads as
    # "waiting for input" rather than as a dimension that lost its label. Drawn
    # in 2D from the screen-space box, which stays the trailing edge whichever
    # way the text ended up facing.
    def draw_caret(view, box2d)
      xs = box2d.map(&:x)
      ys = box2d.map(&:y)
      x = xs.max - 2
      pad = (ys.max - ys.min) * 0.15
      view.line_stipple = ""
      view.line_width = 2
      view.drawing_color = EDIT_CARET
      view.draw2d(GL_LINES, [Geom::Point3d.new(x, ys.min + pad, 0),
                             Geom::Point3d.new(x, ys.max - pad, 0)])
    end
    def snap_text_normal_to_model_axes(vector)
      xaxis = @model.axes.xaxis
      yaxis = @model.axes.yaxis
      zaxis = @model.axes.zaxis
      vecs = [xaxis, xaxis.reverse, yaxis, yaxis.reverse, zaxis, zaxis.reverse]
      vec = vecs.min_by do |v|
  v.angle_between(vector).radians
end
      vec
    end
    def debug_dim(view, point, options)
      d = 3 * @offset
      direction = options[:direction]
      normal = options[:normal]
      view.drawing_color = "lime"
      line = [point, point.offset(direction, d)].map do |pt|
  view.screen_coords(pt)
end
      drawVec2D(line, view)
      view.drawing_color = "blue"
      line = [point, point.offset(normal, d)].map do |pt|
  view.screen_coords(pt)
end
      drawVec2D(line, view)
      view.drawing_color = "red"
      line = [point, point.offset(direction.cross(normal), d)].map do |pt|
  view.screen_coords(pt)
end
      drawVec2D(line, view)
      view.draw_points(point, 7, 2, "cyan")
    end
  end
end
