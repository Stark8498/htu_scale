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
    # Padding around the selection's screen box, in pixels. SketchUp's scale
    # grips all sit ON that box, and they stick out past the silhouette.
    GRIP_MARGIN = 24
    # Splits the viewport in two, and everything about retargeting follows from
    # it: inside the padded box the click may be a grip, so it belongs to the
    # Scale tool and this tool must stay off the stack. Outside it there is no
    # grip to hit, so the click is safely ours to read as "scale that one
    # instead" or "deselect".
    #
    # A screen-space box beats testing each grip position: SketchUp decides
    # where its grips go, and the box is the one thing guaranteed to contain
    # them however it decides.
    def outside_grips?(x, y, view)
      points = @bb_data && @bb_data[:points]
      unless points && !points.empty? && view
        return true
      end
      xs = []
      ys = []
      points.each do |pt|
        sp = view.screen_coords(pt)
        xs << sp.x
        ys << sp.y
      end
      x < xs.min - GRIP_MARGIN || x > xs.max + GRIP_MARGIN ||
        y < ys.min - GRIP_MARGIN || y > ys.max + GRIP_MARGIN
    end
    # Whether this tool wants the next click. Only in state 0: mid-drag the
    # Scale tool owns the mouse wherever it goes.
    def own_click?
      !!@own_click
    end
    def wants_push?
      on_hover? || own_click?
    end
    # The top-level group or instance under the cursor, or nil over raw
    # geometry and empty space. Only these can be scaled as a unit, which is
    # what the whole plugin is about.
    def pick_object(x, y, view)
      helper = view.pick_helper
      helper.do_pick(x, y)
      entity = helper.best_picked
      unless entity.respond_to?(:definition)
        return
      end
      if entity.respond_to?(:locked?) && entity.locked?
        return
      end
      entity
    rescue StandardError => e
      p(e)
      nil
    end
    # Click outside the grips: switch the scale straight to whatever was
    # clicked, or drop the selection on empty space and wait for the next one.
    # Saves leaving the tool, selecting, and pressing S again for every object.
    def retarget(x, y, view)
      entity = pick_object(x, y, view)
      selection = @model.selection
      if entity.nil?
        if selection.empty?
          return
        end
        selection.clear
      elsif selection.length == 1 && selection.to_a.first == entity
        # A click on what is already being scaled changes nothing.
        return
      else
        selection.clear
        selection.add(entity)
      end
      redraw(view)
      view.invalidate
      entity
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
      @own_click = @tool_state == 0 && outside_grips?(x, y, view)
      # While an axis is locked the tool must survive the cursor leaving the
      # dimension text, otherwise a nudge of the mouse would discard whatever
      # the user has typed into the VCB. Away from the grips it stays on the
      # stack too, so the next click can retarget instead of being swallowed.
      if @on_push_tool && !on_hover? && !@locked_axis && !own_click?
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
    # old modal "Resize Entity" inputbox. Clicking anywhere else releases.
    def onLButtonDown(flags, x, y, view)
      dim = hovered_dim
      if dim
        return lock_axis(dim_axis(dim), dim)
      end
      unlock_axis
      # No pop here any more. After retargeting, the cursor is over the new
      # selection, and the next mouse move pops this tool so the Scale tool
      # gets its grips back. Popping now would just make that a round trip.
      retarget(x, y, view)
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
    def same_dc_definition(definition)
      dc_name = definition.get_attribute("dynamic_attributes", "name")
      unless dc_name
        return []
      end
      attributes = definition.attribute_dictionaries["dynamic_attributes"]
      model = definition.model
      model.definitions.find_all do |d|
        if d == definition
          next
        end
        unless d.count_used_instances > 0
          next
        end
        d.get_attribute("dynamic_attributes", "name") == dc_name && d.attribute_dictionaries["dynamic_attributes"].keys == attributes.keys
      end
    end
    def onLButtonUp(flags, x, y, view)
    end
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
      entities = @selection.reject do |e|
  e.respond_to?(:locked?) && e.locked?
end
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
    def get_dim_line(vec, lines)
      plines = lines.find_all do |l|
  l[0].vector_to(l[1]).valid? && l[0].vector_to(l[1]).parallel?(vec)
end
      sort_line = bounds_center_lines(@bb, @tr_bb)[2]
      plines = sort_lines_by_line(plines, sort_line.reverse)
      plines.first
    end
    def compute_dimensions_lines(view = Sketchup.active_model.active_view)
      direction = @view.camera.direction
      unless @bb_points
        return
      end
      dims = []
      lines = @bb_lines.clone
      lines.sort_by! do |l|
        midpoint(l).distance(view.camera.eye)
      end
      vecx = @bb_points[0].vector_to(@bb_points[1])
      vecy = @bb_points[1].vector_to(@bb_points[3])
      vecz = @bb_points[0].vector_to(@bb_points[4])
      if vecx.valid?
        line = get_dim_line(vecx, lines)
        vec_offset = vecy.valid? ? vecy.reverse : vecz.cross(vecx)
        if vec_offset.angle_between(direction).radians < 90
          vec_offset.reverse!
        end
        if vec_offset.parallel?(direction)
          vec_offset = @view.camera.up
        end
        dims << [line, vec_offset]
      else
      end
      if vecy.valid?
        line = get_dim_line(vecy, lines)
        vec_offset = vecx.valid? ? vecx : vecz.cross(vecy)
        if vec_offset.angle_between(direction).radians < 90
          vec_offset.reverse!
        end
        if vec_offset.parallel?(direction)
          vec_offset = @view.camera.up
        end
        dims << [line, vec_offset]
      else
      end
      if vecz.valid? && !direction.parallel?(Z_AXIS)
        line = [@bb_points[0], @bb_points[4]]
        ls = lines.find_all do |l|
  l[0].vector_to(l[1]).valid? && l[0].vector_to(l[1]).parallel?(vecz)
end
        vec = vecz.cross(direction)
        ls = sort_lines_by_line(ls, [@bb_center, vec])
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
      point = @dims.map(&:first).flatten.find do |pt|
  point_inside_screen?(view, pt)
end
      point ||= @bb_center
      dim_offset = view.pixels_to_model(20, point)
      @data_dims = @dims.map do |ar|
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
  parse_dimemsion_geometry(view, line, vector_offset, true, dim_offset)
end
      @data_dims.each_with_index do |d, i|
        unless d
          next
        end
        l = d[:line]
        vec = l[0].vector_to(l[1])
        if vec.parallel?(@tr_bb.xaxis)
          color = "red"
        elsif vec.parallel?(@tr_bb.yaxis)
          color = "darkgreen"
        elsif vec.parallel?(@tr_bb.zaxis)
          color = "blue"
        else
          color = "black"
        end
        d[:color] = color
      end
    end
    def parse_dimemsion_geometry(view, line, vector_offset, extension_line = true, dim_offset = 50.mm)
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
      if vector.parallel?(@tr_bb.zaxis)
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
    def draw_selected_bounds(view)
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
      lines = bounds_center_lines(@bb, @tr_bb)
      entity = view.model.selection[0]
      # The axis lock applies whether or not this tool holds the stack. It used
      # to be skipped while it did, so taking the stack put back the two axes
      # the lock had just taken away.
      if view.model.selection.length == 1 && entity.respond_to?(:definition)
        no_scale_mask = entity.definition.behavior.no_scale_mask?
        x = 126
        y = 125
        z = 123
        case no_scale_mask
        when x
          lines = [lines[0]]
        when y
          lines = [lines[1]]
        when z
          lines = [lines[2]]
        end
      end
      box_lines = {}
      d = view.pixels_to_model(8, @bb_center)
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
      # Known limit, and it predates this: what gets drawn is the six face grips
      # #bounds_center_lines produces. With a lock on that is exactly what
      # SketchUp shows too, so the copy is faithful. With no lock the real tool
      # shows all 27 and the other 21 are simply absent for the duration -- the
      # same partial copy this already drew whenever it held the stack.
      fill = active_itself? || PLUGIN.navigating?
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
        # A locked dimension doubles as the text field. Before the first
        # keystroke the number is drawn selected; after it, the box carries what
        # is being typed instead -- the same replace-the-selection behaviour a
        # text field has. @edit_echo going false means the keyboard could not be
        # mirrored safely, so it falls back to a plain unselected label.
        locked = @locked_axis && dim_axis(dim) == @locked_axis
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
          next
        end
        view.drawing_color = dim[:color]
        view.line_stipple = ""
        view.line_width = 2
        view.draw(GL_LINE_LOOP, box[:bb_text])
        view.draw2d(GL_LINE_LOOP, box[:bb_text_2d])
      end
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
