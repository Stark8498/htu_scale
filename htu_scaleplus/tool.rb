module TRINH_VAN_PHUC::HTU_ScalePlus
  class Tool
    include(Utils)
    attr_reader(:tool_name)
    attr_accessor(:active)
    def initialize(*args)
      @text_typeface = PLUGIN::Typeface::TextTypeface.new
      @model = Sketchup.active_model
    end
    def active?
      @active || @model.tools.active_tool == self
    end
    def onToolStateChanged(tool_state)
    end
    def onMouseMove(flags, x, y, view)
    end
  end
end
