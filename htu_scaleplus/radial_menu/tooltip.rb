module TRINH_VAN_PHUC::HTU_ScalePlus::RadialMenu
  class Tooltip < LabelText
    def initialize(*args)
      super(*args)
      @visible = false
    end
    attr_writer(:visible)
    def visible?
      @visible
    end
    def inside_viewport?
      rect = screen_rectangle
      bounds2d_points(bounds).all? do |pt|
        Geom.point_in_polygon_2D(pt, rect, false)
      end
    end
    def draw(view)
      unless visible?
        return
      end
      super(view)
    end
  end
end
