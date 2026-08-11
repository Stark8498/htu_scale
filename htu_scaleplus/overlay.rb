module TRINH_VAN_PHUC::HTU_ScalePlus
  class ScalePP2Overlay < Sketchup::Overlay
    include(Utils)
    attr_reader(:id, :name, :mouse, :ip_mouse, :tools, :dim_scale)
    def initialize
      @id = "HTU.HTU_ScalePlus"
      @name = "ScalePlus"
      @mouse = [0, 0]
      super(@id, @name)
      start
    end
    def onMouseMove(flags, x, y, view)
      if @mouse && @mouse == [x, y]
        return
      end
      @mouse = [x, y]
      @ip_mouse.pick(view, x, y)
      at = Sketchup.active_model.tools.active_tool
      @tools.each do |tool|
        if tool.active? && at != tool
          tool.onMouseMove(flags, x, y, view)
        end
      end
      active_tool = @tools.find do |t|
  t.active?
end
      if active_tool && active_tool.tool_name == "ScaleTool"
        if !active_tool.on_push_tool && active_tool.on_hover?
          active_tool.on_push_tool = true
          Sketchup.active_model.tools.push_tool(active_tool)
        end
      end
    end
    def onMouseEnter(flags, x, y, view)
      @mouse = [x, y]
    end
    def onMouseLeave(view)
    end
    def register_tool(tool)
      @tools << tool
    end
    def tool_changed(tool_name)
      unless enabled?
        return
      end
      unless @tools
        return
      end
      @tools.each do |tool|
        if tool_name == "ScaleTool" && tool.tool_name == tool_name
          PLUGIN.toggle_tool(true)
        else
          tool.active = tool.tool_name == tool_name
        end
      end
      Sketchup.active_model.active_view.invalidate
    end
    def onToolStateChanged(tool_name, tool_state)
      unless enabled?
        return
      end
      unless @tools
        return
      end
      if tool_name == "ScaleTool"
        if tool_state == 1
          @on_resize = true
          @bb_data = @dim_scale.compute_selected_bounds
        else
          fit_to_length = false
          if @on_resize && fit_to_length
            new_bb = @dim_scale.compute_selected_bounds
            old_lines = @bb_data[:center_lines]
            change_len = new_bb[:center_lines].each_with_index.find do |l, i|
  l[0].distance(l[1]) != old_lines[i][0].distance(old_lines[i][1])
end
            if change_len
              new_line, index = change_len
              old_line = old_lines[index]
              new_len = new_line[0].distance(new_line[1])
              old_len = old_line[0].distance(old_line[1])
              factor = (new_len / old_len).round(3)
              if_length = LengthUtils.number_to_current_length(factor)
              object = @dim_scale.selected_object
              if object
                model = Sketchup.active_model
                model.start_operation("Scale bt length", true, false, true)
                dim = {}
                dim[:line] = new_line
                @dim_scale.set_dim_value(dim, if_length)
                model.commit_operation
              end
            end
          end
          @on_resize = false
        end
      end
      @tools.each do |tool|
        unless tool.tool_name == tool_name
          next
        end
        tool.onToolStateChanged(tool_state)
      end
    end
    def activate
      view = Sketchup.active_model.active_view
      start
      view.invalidate
    end
    def deactivate(view)
      stop
      view.invalidate
    end
    def suspend(view)
      view.invalidate
    end
    def resume(view)
      view.invalidate
    end
    def reset
      @none_solids = nil
      @geometry_same_level_object = nil
    end
    def start
      begin
        @tools = []
        @ip_mouse = Sketchup::InputPoint.new
        @dim_scale = ScalePPTool.new(self)
        register_tool(@dim_scale)
        if PLUGIN.observer
          tool_changed(PLUGIN.observer.last_tool_name)
        end
      rescue => exception
        p(exception)
      end
    end
    def stop
    end
    def getExtents
      unless enabled?
        return
      end
      unless @dim_scale && @dim_scale.active?
        return
      end
      unless @dim_scale.bb_data
        return
      end
      model = Sketchup.active_model
      view = model.active_view
      cam = view.camera
      bb = model.bounds
      if cam.perspective?
        bb.add(cam.eye)
      else
        pts = @dim_scale.bb_data[:points]
        if pts && !pts.empty?
          bb.add(pts)
        end
        mp = max_point
        if mp
          bb.add(mp)
        end
      end
      bb
    end
    def max_point
      view = Sketchup.active_model.active_view
      cam = view.camera
      plane = [cam.eye, cam.direction]
      points = @dim_scale.bb_data[:points].clone || []
      points = points + bound_points(view.model.bounds)
      points.delete_if do |pt|
        pj = pt.project_to_plane(plane)
        !pj.vector_to(pt).samedirection?(cam.direction)
      end
      point0 = points.min_by do |pt|
  pt.distance_to_plane(plane)
end
      if point0
        d = view.pixels_to_model(10, point0)
        return point0.offset(cam.direction.reverse, d)
      end
    end
    def draw(view)
      at = Sketchup.active_model.tools.active_tool
      @tools.each do |tool|
        if tool.active? && at != tool
          tool.draw(view)
        end
      end
    end
    def inspect
      name = self.class.name.split("::").last
      module_name = self.class.name.split("::")[-2]
      hex_id = format("0x%x", object_id << 1)
      "#<#{module_name}::#{name}:#{hex_id}>"
    end
  end
end
