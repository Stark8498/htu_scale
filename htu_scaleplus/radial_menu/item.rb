module TRINH_VAN_PHUC::HTU_ScalePlus::RadialMenu
  class Item
    include(ShapeGeom)
    attr_reader(:position)
    attr_accessor(:parent)
    attr_accessor(:active_line_width, :hover_line_width)
    def initialize
      @hover = false
      @active = false
      @hover_line_width = 1
      @active_line_width = 3
      @position = Geom::Point3d.new(0, 0, 0)
      @view = Sketchup.active_model.active_view
    end
    def reset
      @hover = false
      @active = false
    end
    def menu
      unless @parent
        return
      end
      if @parent.is_a?(PLUGIN::RadialMenu::Menu)
        @parent
      else
        @parent.menu
      end
    end
    def size
      @size || PLUGIN::RadialMenu.pie_size
    end
    def center_screen
      [@view.vpwidth / 2, @view.vpheight / 2]
    end
    def position=(position)
      set_relative_position(position)
    end
    def set_absolute_position(position)
      parent_ab = @parent.is_a?(PLUGIN::RadialMenu::Menu) ? @parent.position : @parent.absolute_position
      vector = parent_ab.vector_to(ORIGIN)
      new_position = position.offset(vector)
      set_relative_position(new_position)
    end
    alias move_to set_absolute_position
    def absolute_position
      to_absolute_position(@position)
    end
    def to_absolute_position(point)
      unless parent
        return point
      end
      parent_ab = parent.is_a?(PLUGIN::RadialMenu::Menu) ? parent.position : parent.absolute_position
      point.offset(ORIGIN.vector_to(parent_ab))
    end
    def to_relative_position(point)
      parent_ab = @parent.is_a?(PLUGIN::RadialMenu::Menu) ? @parent.position : @parent.absolute_position
      point.offset(parent_ab.vector_to(ORIGIN))
    end
    def set_relative_position(position)
      @position = position
      redraw
    end
    def path
      pt = [self]
      while pt.last.respond_to?(:parent) && (pt.last.parent && pt.last.parent != menu)
        pt << pt.last.parent
      end
      pt.reverse
    end
    def hover=(state)
      if @hover == state
        return
      end
      @hover = state
    end
    def hover?
      @hover
    end
    def on_hover(&block)
      @on_hover = block
    end
    def on_blur(&block)
      @on_blur = block
    end
    def on_click(&block)
      @on_click = block
    end
    def active=(status)
      unless @active != status
        return
      end
      @active = status
    end
    def active?
      @active
    end
    def redraw(*args)
    end
  end
end
