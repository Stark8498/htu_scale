module TRINH_VAN_PHUC::HTU_ScalePlus::RadialMenu
  class Submenu < Command
    attr_accessor(:menu, :show_items)
    attr_reader(:items)
    def initialize(menu, name)
      @menu = menu
      @name = name
      @items = []
      @show_items = false
      @zone_menu = nil
      @zone_commands = nil
      super()
    end
    def reset
      @show_items = false
      super
      @items.each(&:reset)
    end
    def parent=(item)
      super(item)
    end
    def tree
      {:item => self, :position => @position, :menu_text => @name, :icon => @icon, :tooltip => @tooltip ? @tooltip.text : "", :items => @items.map(&:tree)}
    end
    def show_items?
      @show_items
    end
    def padding
      size / 6
    end
    def onMouseMove(flag, x, y, view)
      super(flag, x, y, view)
      if hover?
        @show_items = true
      elsif @zone_menu
        self.hover = Geom.point_in_polygon_2D([x, y], @zone_menu, true)
        if hover?
          @show_items = true
        elsif @zone_commands && (!hover? && @show_items)
          self.hover = Geom.point_in_polygon_2D([x, y], @zone_commands, false)
        end
      end
      unless hover?
        self.hover = @items.any? do |i|
  i.is_a?(Submenu) && i.show_items?
end
      end
      unless hover?
        @show_items = false
        return
      end
      @items.each do |item|
        item.onMouseMove(flag, x, y, view)
      end
    end
    def onLButtonDown(flag, x, y, view)
      super(flag, x, y, view)
      if @show_items
        @items.each do |item|
          item.onLButtonDown(flag, x, y, view)
        end
      end
    end
    def onLButtonUp(flag, x, y, view)
      super(flag, x, y, view)
      if @show_items
        @items.each do |item|
          item.onLButtonUp(flag, x, y, view)
        end
      end
    end
    def add_item(item)
      unless item.is_a?(PLUGIN::RadialMenu::Command)
        raise("Error item")
      end
      @items << item
      item.parent = self
    end
    def redraw(*args)
      super(*args)
      auto_layout_items
    end
    def auto_layout_items
      if @items.empty?
        return
      end
      point = absolute_position
      vec = menu.position.vector_to(point)
      radius = vec.length
      radius = radius + (PLUGIN::RadialMenu.pie_size + 2 * padding)
      start_position = menu.position.offset(vec, radius)
      angle = Math.asin((size / 2 + padding).to_f / radius).radians * 2
      tr = Geom::Transformation.rotation(menu.position, Z_AXIS.reverse, (angle * ((@items.length - 1) / 2)).degrees)
      start_position.transform!(tr)
      tr = Geom::Transformation.rotation(menu.position, Z_AXIS, angle.degrees)
      positions = [start_position]
      0.upto(@items.length - 2) do
        positions << positions.last.transform(tr)
      end
      positions.each_with_index do |position, i|
        unless @items[i]
          next
        end
        @items[i].set_absolute_position(position)
      end
      @items.each(&:redraw)
      compute_zones
    end
    def compute_zone(items, total_angle, sides = 6)
      item = items[0]
      point = item.absolute_position
      center = menu.position
      vec = center.vector_to(point)
      point.offset!(vec.reverse, item.size / 2 + padding)
      tr = Geom::Transformation.rotation(center, Z_AXIS.reverse, (total_angle.to_f / items.length / 2).degrees)
      point.transform!(tr)
      point0 = point
      point1 = point0.offset(center.vector_to(point0), item.size + 2 * padding)
      tr = Geom::Transformation.rotation(center, Z_AXIS, (total_angle / sides).degrees)
      pts0 = [point0]
      pts1 = [point1]
      0.upto(sides - 1) do
        pts0 << pts0.last.transform(tr)
        pts1 << pts1.last.transform(tr)
      end
      pts0 + pts1.reverse
    end
    def compute_zones
      begin
        vec0 = menu.position.vector_to(parent.items[0].absolute_position)
        vec1 = menu.position.vector_to(parent.items[1].absolute_position)
        anlge = vec0.angle_between(vec1).radians
        @zone_menu = compute_zone([self], anlge)
        @zone_commands = nil
        if @items.empty?
          return
        end
        if @items.length == 1
          command_anlge = anlge
        else
          vec0 = menu.position.vector_to(@items[0].absolute_position)
          vec1 = menu.position.vector_to(@items[1].absolute_position)
          vec2 = menu.position.vector_to(@items[-1].absolute_position)
          unit_angle = vec0.angle_between(vec1).radians
          total_angle = vec0.angle_between(vec2).radians
          command_anlge = unit_angle + total_angle
        end
        @zone_commands = compute_zone(@items, command_anlge)
      rescue StandardError
        # Swallowed, as in the original. Only the unused `=> e` was removed; making
        # this report would be a behaviour change, and this file is never loaded.
      end
    end
    def draw(view)
      super
      if hover? || @items.any? do |i|
  i.is_a?(Submenu) && i.show_items?
end
        @items.each do |item|
          item.draw(view)
        end
      end
      if PLUGIN::RadialMenu.debug
        view.drawing_color = "lime"
        if @zone_menu
          view.draw2d(GL_LINE_LOOP, @zone_menu)
        end
        if @zone_commands
          view.draw2d(GL_LINE_LOOP, @zone_commands)
        end
      end
    end
    def inspect
      name = self.class.name.split("::").last
      module_name = self.class.name.split("::")[-2]
      hex_id = format("0x%x", object_id << 1)
      "#<#{module_name}::#{name}:#{hex_id}> #{@name}"
    end
  end
end
