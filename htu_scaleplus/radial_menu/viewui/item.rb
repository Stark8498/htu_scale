module TRINH_VAN_PHUC
  module ViewUI
    class Item
      attr_accessor(:active)
      include(TRINH_VAN_PHUC::PieMenu::ShapeGeom)
      def initialize(*_args)
        @hover = false
        @active = false
        @on_move = false
        @on_resize = false
        @position = Geom::Point3d.new(0, 0, 0)
        @view = Sketchup.active_model.active_view
      end
      def hover=(state)
        if @hover == state
          return
        end
        @hover = state
      end
      def on_hover?
        @hover
      end
      def active?
        @active
      end
      def check_hover(x, y)
        pls = bound_polygons
        unless pls[0].is_a?(Array)
          pls = [pls]
        end
        Geom.point_in_polygon_2D([x, y], pls[0], true) && pls[1..-1].none? do |pl|
  Geom.point_in_polygon_2D([x, y], pl, true)
end
      end
    end
  end
end
