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
      # Track the position, then stop. Two things must not happen while the user
      # is dragging the camera, and both used to.
      #
      # An orbit moves the selection's box across the screen under a cursor being
      # held still, so a dimension label slides under that cursor by itself,
      # #on_hover? turns true and the tool grabs the stack -- suspending the real
      # Scale tool and its grips in the middle of an orbit, which is the one thing
      # the user was looking at.
      #
      # And ScalePPTool#onMouseMove can decide to hand the stack back, but
      # #pop_tool pops whatever is on TOP, which during a navigation is SketchUp's
      # own camera tool. That aborts the orbit the user is in the middle of.
      #
      # Nothing is merely postponed here: #navigation_finished replays the whole
      # decision as soon as the camera is released.
      if PLUGIN.navigating?
        return
      end
      dispatch_mouse(flags, x, y, view)
    end
    # The push/pop decision, split out of #onMouseMove so it can also run without
    # one. That is the whole point of the split: the pop lives inside
    # ScalePPTool#onMouseMove, so before this existed the real grips stayed
    # suspended after an orbit until the user moved the mouse -- and a cursor left
    # sitting still never got them back at all.
    def dispatch_mouse(flags, x, y, view)
      @ip_mouse.pick(view, x, y)
      at = Sketchup.active_model.tools.active_tool
      @tools.each do |tool|
        unless tool.active?
          next
        end
        # Skipped when the tool is on the stack: SketchUp is calling its
        # #onMouseMove itself there, and calling it again here would double every
        # mouse event.
        if at != tool
          tool.onMouseMove(flags, x, y, view)
        end
      end
      active_tool = @tools.find do |t|
  t.active?
end
      if active_tool && active_tool.tool_name == "ScaleTool"
        # on_hover? -- the cursor is over a dimension's own text. That is the only
        # reason this tool ever takes the stack: overlays get no mouse-button
        # callback, so catching the click that locks an axis means being a tool for
        # as long as the cursor is on the label, and no longer.
        if !active_tool.on_push_tool && active_tool.on_hover?
          active_tool.on_push_tool = true
          Sketchup.active_model.tools.push_tool(active_tool)
        end
      end
    end
    # SketchUp has handed the Scale tool back after an orbit, pan or zoom. Replay
    # the decision against the new camera and the last known cursor position, so
    # the Scale tool is fully live again the moment the middle button comes up.
    #
    # Deferred a tick: SketchUp is still unwinding its own camera tool off the
    # stack while this callback runs, and a push or a pop landing in the middle of
    # that is exactly the damage this method exists to avoid.
    def navigation_finished
      unless enabled? && @mouse
        return
      end
      x, y = @mouse
      id = UI.start_timer(0, false) do
        UI.stop_timer(id)
        begin
          view = Sketchup.active_model.active_view
          dispatch_mouse(0, x, y, view)
          view.invalidate
        rescue StandardError => e
          p(e)
        end
      end
    end
    def onMouseEnter(flags, x, y, view)
      @mouse = [x, y]
    end
    # The Scale tool's cursor -- the arrow with a little box and a red grip corner --
    # is SketchUp's, and it stays. This overlay used to overwrite it with the plain
    # arrow on every mouse move; the user asked for the icon back, so nothing here
    # touches the cursor any more. The gate in navigation_test.rb holds it that way.
    #
    # Worth keeping because it took a while to find, and because putting it back is a
    # ten-line job: UI.set_cursor is a plain GLOBAL call, not something only a
    # callback may make, and an overlay is handed mouse moves whichever tool is
    # active. So calling it from #onMouseMove reaches even the frames where the
    # NATIVE Scale tool owns the mouse -- which ScalePPTool#onSetCursor could not,
    # since SketchUp only asks the tool on TOP of the stack. If it ever comes back it
    # must skip camera moves (orbit and pan have cursors that mean something) and any
    # tool other than Scale.
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
      # `at != tool` is there to avoid drawing twice when SketchUp is calling the
      # tool's own #draw. During a navigation it is not: a camera tool sits on top
      # of the stack and everything below it is suspended.
      #
      # Measured with dev/htu_nav_probe.rb: orbiting with the tool OFF the stack
      # reports at=nil, so `at != tool` holds and this clause changes nothing
      # there. Orbiting with the tool ON the stack was not measured, and if
      # #active_tool reports the suspended tool in that case then `at != tool` is
      # false and the grips vanish again. So the navigation case is stated rather
      # than relied upon. Drawing the same grips twice would be invisible anyway --
      # same colour, same screen position -- while not drawing them is the whole
      # bug being fixed.
      navigating = PLUGIN.navigating?
      @tools.each do |tool|
        if tool.active? && (navigating || at != tool)
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
