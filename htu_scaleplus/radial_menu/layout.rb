module TRINH_VAN_PHUC::HTU_ScalePlus::RadialMenu
  class Layout < Item
    attr_reader(:items)
    attr_reader(:type)
    def initialize
      super
      @items = []
      @show = true
      redraw(true)
      reset
    end
    def reset
      super
      @items.each(&:reset)
    end
    def commands
      @items
    end
    def bounds2d
      bb3d = Geom::BoundingBox.new
      bb3d.add(@outer_draw)
      upper_left = Geom::Point2d.new(bb3d.corner(0).to_a[0..1])
      lower_right = Geom::Point2d.new(bb3d.corner(3).to_a[0..1])
      Geom::Bounds2d.new(upper_left, lower_right)
    end
    def bounds3d
      bb3d = Geom::BoundingBox.new
      bb3d.add(@outer_draw)
    end
    def tree
      {:item => self, :radius => @radius, :position => @position, :items => @items.map(&:tree)}
    end
    def to_h
      struct = {}
      struct[:item] = self.class
      struct[:position] = @position.to_a
      struct[:radius] = @radius
      struct[:items] = @items.map(&:to_h)
      struct
    end
    def padding
      size / 6
    end
    def add_item(item, _index = nil)
      unless @items.include?(item)
        @items << item
      end
      item.parent = self
      auto_layout_items
    end
    def onMouseMove(flag, x, y, view)
      @items.each do |item|
        item.onMouseMove(flag, x, y, view)
      end
      check_hover(flag, x, y, view)
    end
    def onLButtonDown(flag, x, y, view)
      @items.each do |i|
        i.onLButtonDown(flag, x, y, view)
      end
      check_hover(flag, x, y, view)
      self.active = hover?
    end
    def onLButtonUp(flag, x, y, view)
      @items.each do |i|
        i.onLButtonUp(flag, x, y, view)
      end
    end
    def draw(view)
      unless menu.visible?
        return
      end
      draw_shape(view)
      draw_items(view)
    end
    def draw_items(view)
      items = @items.clone
      active_item = items.find(&:active?)
      items.each do |item|
        if active_item && item == active_item
          next
        end
        item.draw(view)
      end
      if active_item
        active_item.draw(view)
      end
      items.each do |i|
        unless i.tooltip && i.hover?
          next
        end
        i.tooltip.draw(view)
      end
    end
    def drawing_line_width
      if active?
        return 2
      end
      1
    end
  end
end
