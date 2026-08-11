module TRINH_VAN_PHUC::HTU_ScalePlus
  def self.toggle_tool(status)
    tool = PLUGIN.active_overlay.tools.find do |t|
  t.tool_name == "ScaleTool"
end
    tool.active = status
    Sketchup.active_model.active_view.invalidate
  end
  def self.save_dim_to_object(len, value, object)
    begin
      dims = object_dims(object, len)
      unless dims.include?(value)
        dims << value
      end
      dims.sort!
      object.set_attribute(PLUGIN, "#{len}_dims", dims)
      object.definition.set_attribute(PLUGIN, "#{len}_dims", dims)
    rescue => exception
      p(exception)
    end
  end
  def self.object_dims(object, len)
    if object.is_a?(Sketchup::ComponentDefinition)
      dims = object.get_attribute(PLUGIN, "#{len}_dims", [])
    else
      dims = object.definition.get_attribute(PLUGIN, "#{len}_dims", [])
    end
    dims
  end
  def self.clear_object_dims(object, len)
    object.set_attribute(PLUGIN, "#{len}_dims", [])
    if object.is_a?(Sketchup::ComponentDefinition)
      return
    end
    object.definition.set_attribute(PLUGIN, "#{len}_dims", [])
  end
  class ScalePPTool < Tool
    attr_reader(:data_dims)
    attr_accessor(:on_push_tool)
    attr_accessor(:highlight_center)
    attr_reader(:bb_data)
    attr_reader(:pet_toolbar)
    def initialize(overlay)
      super
      @overlay = overlay
      @tool_name = "ScaleTool"
      @tool_state = 0
      @on_push_tool = false
      @pet_toolbar = PetToolbar.new(self)
      @pet_toolbar.command_on_hover do |cmd|
        unless active_itself?
          next
        end
        @highlight_center = cmd.ui_command.menu_text.gsub("Behavior Scale ", "")
      end
      @pet_toolbar.command_on_blur do
        @highlight_center = nil
      end
      @model = Sketchup.active_model
      @selection = @model.selection
      @view = @model.active_view
    end
    def active=(status)
      if status == active?
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
    def place_menu
      rect = @pet_toolbar.menu.items[0].bounds.map do |pt|
  pt.to_a[0..1]
end
      unless @bb_points
        return
      end
      container = [[0, 0], [@view.vpwidth, 0], [@view.vpwidth, @view.vpheight], [0, @view.vpheight]]
      d = RadialMenu.pie_size * 2
      pts = @bb_points
      pts = pts + @bb_data[:centers]
      pts = pts + @bb_lines.map do |l|
  midpoint(l)
end
      existing_rects = pts.map do |pt|
  x, y = @view.screen_coords(pt).to_a[0..1]
  r = square_from_center(x, y, d)
  r
end
      @existing_rects = existing_rects.map do |r|
  r.map do |pt|
    Geom::Point3d.new(pt)
  end
end
      ranger = -75..95
      rect_w = rect[3][0] - rect[0][0]
      rect_h = rect[1][1] - rect[0][1]
      rect_center_x = rect[0][0] + rect_w / 2
      rect_center_y = rect[0][1] + rect_h / 2
      rect_half_width = rect_w / 2
      rect_half_height = rect_h / 2
      @new_rects = {}
      radius = RadialMenu.pie_size * 5
      fit = false
      new_rect_points = nil
      c = 0
      until fit || (radius > @view.vpwidth / 2 || c > 100)
        ranger.step(15) do |angle|
          circle_center_x = rect_center_x + radius * Math.cos(angle * Math::PI / 180)
          circle_center_y = rect_center_y + radius * Math.sin(angle * Math::PI / 180)
          new_rect_points = [[circle_center_x - rect_half_width, circle_center_y - rect_half_height], [circle_center_x + rect_half_width, circle_center_y - rect_half_height], [circle_center_x + rect_half_width, circle_center_y + rect_half_height], [circle_center_x - rect_half_width, circle_center_y + rect_half_height]]
          fit = can_fit?(new_rect_points, existing_rects, container)
          @new_rects[new_rect_points.map do |pt|
  Geom::Point3d.new(pt)
end] = fit
          if fit
            break
          end
          c = c + 1
        end
        radius = radius + RadialMenu.pie_size * 1.5
      end
      if fit
        return new_rect_points
      end
      false
    end
    def menu_can_fit?
      unless @bb_points
        return
      end
      rect = @pet_toolbar.menu.items[0].bounds.map do |pt|
  pt.to_a[0..1]
end
      container = [[0, 0], [@view.vpwidth, 0], [@view.vpwidth, @view.vpheight], [0, @view.vpheight]]
      d = RadialMenu.pie_size * 2
      pts = @bb_points
      pts = pts + @bb_data[:centers]
      pts = pts + @bb_lines.map do |l|
  midpoint(l)
end
      existing_rects = pts.map do |pt|
  x, y = @view.screen_coords(pt).to_a[0..1]
  r = square_from_center(x, y, d)
  r
end
      can_fit?(rect, existing_rects, container)
    end
    def can_fit?(rect, existing_rects, container)
      if rect[2][0] > container[2][0] || (rect[2][1] > container[2][1] || (rect[0][0] < container[0][0] || rect[0][1] < container[0][1]))
        return false
      end
      existing_rects.each do |existing_rect|
        if !(rect[2][0] <= existing_rect[0][0] || (rect[0][0] >= existing_rect[2][0] || (rect[2][1] <= existing_rect[0][1] || rect[0][1] >= existing_rect[2][1])))
          return false
        end
      end
      true
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
        update_menu_position
      end
      @on_call_back = false
    end
    def update_menu_position
      if @on_call_back && menu_can_fit?
        return
      else
        menu_position = @overlay.mouse.clone
        menu_position.x += RadialMenu.size * 1.5
        menu_position.y += RadialMenu.size * 1.5
        @pet_toolbar.menu.show(menu_position)
        rect = place_menu
        if rect
          menu_position = rect[0]
          menu_position.x += RadialMenu.size / 2 + RadialMenu.size / 6
          menu_position.y += RadialMenu.size / 2 + RadialMenu.size / 6
        else
          menu_position = @overlay.mouse.clone
          menu_position.x += RadialMenu.size * 1.5
          menu_position.y += RadialMenu.size * 1.5
        end
      end
      @pet_toolbar.menu.show(menu_position)
    end
    def reset
      @dims = nil
      @data_dims = nil
      @store_bb = nil
      @state = nil
      @highlight_center = nil
    end
    def deactivate(view)
      if @on_push_tool
        @on_push_tool = false
      end
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
        @pet_toolbar.visible = false
      else
        @pet_toolbar.visible = true
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
end || @pet_toolbar.on_hover?
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
      if @pet_toolbar
        @pet_toolbar.onMouseMove(flags, x, y, view)
      end
      if @on_push_tool && !on_hover?
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
    def onLButtonDown(flags, x, y, view)
      if @pet_toolbar
        @pet_toolbar.onLButtonDown(flags, x, y, view)
      end
      if @pet_toolbar.on_hover?
        return
      end
      unless @data_dims
        return call_back
      end
      dim = @data_dims.find do |d|
  d && d[:hover]
end
      unless dim
        return call_back
      end
      line = dim[:line]
      vec = line[1] - line[0]
      len = "Len" + (vec.parallel?(@tr_bb.xaxis) ? "X" : vec.parallel?(@tr_bb.yaxis) ? "Y" : vec.parallel?(@tr_bb.zaxis) ? "Z" : "")
      prompts = ["Resize #{len}"]
      len = dim[:line].first.distance(dim[:line].last)
      defaults = [len]
      title = "Resize Entity"
      if IS_WIN
        id = UI.start_timer(0.099999999976716936, false) do
  UI.stop_timer(id)
  r = UI.inputbox(prompts, defaults, title)
  click_dim(dim, len, r)
end
      else
        r = UI.inputbox(prompts, defaults, title)
        click_dim(dim, len, r)
      end
    end
    def click_dim(dim, len, ipbox)
      unless ipbox
        return call_back
      end
      new_len = ipbox[0]
      if new_len == 0
        return call_back
      end
      if new_len == len
        return call_back
      end
      @model.start_operation("Resize", true)
      set_dim_value(dim, new_len)
      @model.commit_operation
      dc_redraw
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
      if @pet_toolbar
        @pet_toolbar.onLButtonUp(flags, x, y, view)
      end
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
      char_loops = @text_typeface.convert(text.to_s, options)
      triangles = []
      char_loops.each do |_i, loops|
        unless loops
          next
        end
        triangles << Geom.tesselate(loops.first, *loops[1..-1])
      end
      direction = options[:direction]
      normal = options[:normal]
      tr = Geom::Transformation.axes(options[:position], direction, normal.cross(direction), normal)
      pts = triangles.flatten.map do |pt|
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
      {:line => dim, :extensions => extensions, :text_char_loops => char_loops, :text_triangles => triangles, :bb_text => bb_text, :bb_text_2d => bb_text_2d, :options => options}
    end
    def getMenu(menu, flags, x, y, view)
      dim = @data_dims.find do |d|
  d && d[:hover]
end
      if dim
        dimGetMenu(dim, menu, flags, x, y, view)
      else
        submenu = menu.add_submenu("UI Scale Factor")
        submenu.add_item("Auto Scale Factor") do
          PLUGIN.verify_ui_scale
        end
        [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2].each do |scale|
          cmd = submenu.add_item("x#{scale}") do
  PLUGIN.scale_factor = scale
  view.invalidate
end
          submenu.set_validation_proc(cmd) do
            if PLUGIN::SCALE_FACTOR == scale
              MF_CHECKED
            else
              MF_UNCHECKED
            end
          end
        end
      end
      true
    end
    def dimGetMenu(dim, menu, flags, x, y, view)
      object = selected_object
      line = dim[:line]
      vec = line[1] - line[0]
      len = line[0].distance(line[1])
      if vec.parallel?(@tr_bb.xaxis)
        name = "lenx"
      elsif vec.parallel?(@tr_bb.yaxis)
        name = "leny"
      elsif vec.parallel?(@tr_bb.zaxis)
        name = "lenz"
      end
      lens = object ? object_dims(object, name) : []
      if object && dim
        lens_empty = lens.empty?
        if lens.empty?
          lens << (len * 0.5).to_l
          lens << (len * 2).to_l
          lens.each do |l|
            menu.add_item("#{l} (x#{(l / len).round(1)})") do
              @model.start_operation("Resize", true)
              set_dim_value(dim, l)
              @model.commit_operation
              dc_redraw
              view.model.select_tool(nil)
              Sketchup.send_action("selectScaleTool:")
            end
          end
        else
          cmd = menu.add_item("Favorite Dimensions") do
end
          menu.set_validation_proc(cmd) do
            MF_GRAYED
          end
          lens.each do |l|
            c = menu.add_item(l.to_s) do
  @model.start_operation("Resize", true)
  set_dim_value(dim, l)
  @model.commit_operation
  dc_redraw
  view.model.select_tool(nil)
  Sketchup.send_action("selectScaleTool:")
end
            menu.set_validation_proc(c) do
              if l == len
                MF_CHECKED
              else
                MF_ENABLED
              end
            end
          end
        end
        if object
          menu.add_item("Show Manager") do
            DimsUI.show_dialog
          end
        end
        same_dc = same_dc_definition(object.definition)
        same_dc << object.definition
        if same_dc.length > 0
          dc_lens = []
          same_dc.each do |d|
            paths = definition_paths(d)
            paths.each do |path|
              tr = Sketchup::InstancePath.new(path).transformation
              o = path.last
              bb = o.definition.bounds
              len_lines = bounds_center_lines(bb, tr)
              if vec.parallel?(@tr_bb.xaxis)
                len_line = len_lines[0]
              elsif vec.parallel?(@tr_bb.yaxis)
                len_line = len_lines[1]
              else
                len_line = len_lines[2]
              end
              l = len_line[0].distance(len_line[1])
              unless dc_lens.include?(l)
                dc_lens << l
              end
            end
          end
          dc_lens = dc_lens - lens
          dc_lens.delete(len)
          if dc_lens.length > 0
            menu.add_separator
            cmd = menu.add_item("Referenced Dimensions") do
end
            menu.set_validation_proc(cmd) do
              MF_GRAYED
            end
            dc_lens.each do |l|
              menu.add_item("#{l} (in model)") do
                @model.start_operation("Resize", true)
                set_dim_value(dim, l)
                @model.commit_operation
                dc_redraw
                view.model.select_tool(nil)
                Sketchup.send_action("selectScaleTool:")
              end
            end
          end
        end
        menu.add_separator
        smenu = menu.add_submenu("Text size")
        c = smenu.add_item("Small") do
  PLUGIN.settings[:dim_text_size] = DIM_SMALL
end
        smenu.set_validation_proc(c) do
          if PLUGIN.settings[:dim_text_size] == DIM_SMALL
            MF_CHECKED
          else
            MF_ENABLED
          end
        end
        c = smenu.add_item("Medium") do
  PLUGIN.settings[:dim_text_size] = DIM_MEDIUM
end
        smenu.set_validation_proc(c) do
          if PLUGIN.settings[:dim_text_size] == DIM_MEDIUM
            MF_CHECKED
          else
            MF_ENABLED
          end
        end
        c = smenu.add_item("Large") do
  PLUGIN.settings[:dim_text_size] = DIM_LARGE
end
        smenu.set_validation_proc(c) do
          if PLUGIN.settings[:dim_text_size] == DIM_LARGE
            MF_CHECKED
          else
            MF_ENABLED
          end
        end
      end
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
        if @existing_rects
        end
        if active_itself?
          draw_selected_bounds(view)
        end
        if @tool_state == 0
          draw_scale_points(view)
        end
        @pet_toolbar.draw(view)
      rescue => exception
        p(exception)
      end
    end
    def draw_selected_bounds(view)
      @bb_lines = bounds_lines(@bb, @tr_bb)
      view.line_stipple = ""
      view.drawing_color = "yellow"
      view.line_width = 3
      view.draw(GL_LINES, hack_point_draw(view, @bb_lines.flatten))
    end
    def draw_scale_points(view)
      lines = bounds_center_lines(@bb, @tr_bb)
      entity = view.model.selection[0]
      if !active_itself? && (view.model.selection.length == 1 && entity.respond_to?(:definition))
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
      points = @bb_points
      points = points + @bb_lines.map do |l|
  midpoint(l)
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
      draw_boxs = []
      draw_lines = []
      if @highlight_center
        case @highlight_center
        when "All"
          points.each do |point|
            box = create_box(point.to_a, d)
            draw_boxs << box.map do |face|
  face.map do |pt|
    view.screen_coords(pt)
  end
end
          end
          box_lines.each do |line, bs|
            bs.each do |b|
              draw_boxs << b
            end
          end
        when "XYZ"
          box_lines.each do |line, box2ds|
            vec_line = line[1] - line[0]
            unless vec_line.valid?
              next
            end
            if [@tr_bb.xaxis, @tr_bb.yaxis, @tr_bb.zaxis].any? do |v|
  v.parallel?(vec_line)
end
              draw_boxs = draw_boxs + box2ds
              draw_lines << line
            end
          end
        when "X"
          box_lines.each do |line, box2ds|
            vec_line = line[1] - line[0]
            unless vec_line.valid?
              next
            end
            unless vec_line.parallel?(@tr_bb.xaxis)
              next
            end
            draw_boxs = draw_boxs + box2ds
            draw_lines << line
          end
        when "Y"
          box_lines.each do |line, box2ds|
            vec_line = line[1] - line[0]
            unless vec_line.valid?
              next
            end
            unless vec_line.parallel?(@tr_bb.yaxis)
              next
            end
            draw_boxs = draw_boxs + box2ds
            draw_lines << line
          end
        when "Z"
          box_lines.each do |line, box2ds|
            vec_line = line[1] - line[0]
            unless vec_line.valid?
              next
            end
            unless vec_line.parallel?(@tr_bb.zaxis)
              next
            end
            draw_boxs = draw_boxs + box2ds
            draw_lines << line
          end
        end
        if !draw_boxs.empty?
          view.line_stipple = ""
          view.drawing_color = "gray"
          draw_boxs.each do |b|
            b.each do |f|
              view.draw2d(GL_LINE_LOOP, f)
            end
          end
          view.drawing_color = "lime"
          view.draw2d(GL_QUADS, draw_boxs.flatten)
        end
        if !draw_lines.empty?
          view.drawing_color = "gray"
          view.line_stipple = "."
          view.draw2d(GL_LINES, draw_lines.map do |l|
  l.map do |pt|
    view.screen_coords(pt)
  end
end.flatten)
        end
      else
        box_lines.each do |line, box2ds|
          view.line_stipple = ""
          view.drawing_color = "gray"
          box2ds.each do |box2d|
            box2d.each do |f|
              view.draw2d(GL_LINE_LOOP, f)
            end
          end
          view.line_stipple = "."
          view.draw2d(GL_LINES, line.map do |pt|
  view.screen_coords(pt)
end)
        end
      end
    end
    def draw_debug_place(view)
      view.drawing_color = "red"
      @existing_rects.each do |r|
        view.draw2d(GL_POLYGON, r)
      end
      @new_rects.each do |r, fit|
        view.drawing_color = fit ? "cyan" : "blue"
        view.draw2d(GL_POLYGON, r)
        view.drawing_color = "lime"
        view.draw2d(GL_LINE_LOOP, r)
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
        view.drawing_color = [255, 255, 255, 150]
        view.draw2d(GL_POLYGON, dim[:bb_text_2d])
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
        triangles = dim[:text_triangles]
        view.draw2d(GL_TRIANGLES, triangles.flatten.map do |pt|
  view.screen_coords(pt)
end)
        view.draw(GL_TRIANGLES, triangles.flatten)
        unless dim[:hover]
          next
        end
        view.drawing_color = dim[:color]
        view.line_stipple = ""
        view.line_width = 2
        view.draw(GL_LINE_LOOP, dim[:bb_text])
        view.draw2d(GL_LINE_LOOP, dim[:bb_text].map do |pt|
  view.screen_coords(pt)
end)
      end
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
