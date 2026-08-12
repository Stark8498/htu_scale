# encoding: UTF-8
#
# htu_nav_probe.rb
#
# Why the grips still vanish during an orbit, answered with numbers instead of
# reasoning. Reading the code got pan wrong, so this reads the running plugin.
#
#   load "E:/htu_scaleplus/dev/htu_nav_probe.rb"
#   HTU_NavProbe.on      # then orbit, pan, zoom -- watch the lines
#   HTU_NavProbe.off
#
# One line every 250ms. Drag for a second and an orbit gives four or five.
#
# Do ONE gesture per run and say which one it was. The tool names SketchUp reports
# are not the ones the docs suggest -- a pan comes through as "CameraDollyTool" --
# so a log with three gestures mixed together cannot be attributed afterwards.
#
# Survives HTU_ScalePlusReload.run, so the counters stay live across a reload.
#
#   tool=          what Sketchup::Tools#active_tool_name reports RIGHT NOW.
#                  The whole navigation guard keys off this string.
#   nav=           PLUGIN.navigating? -- true means "SketchUp is drawing neither
#                  the grips nor the yellow box, so paint substitutes".
#   active=        is ScalePPTool still active? If false, Tool#draw returns at once.
#   state=         @tool_state. draw_scale_points only runs at 0.
#   ov=            times Overlay#draw was called since the last line. 0 means
#                  SketchUp is not drawing the overlay at all during the gesture,
#                  and then nothing can be painted from Ruby -- a hard wall.
#   grips=         times draw_scale_points was called since the last line. 0 while
#                  ov>0 means Tool#draw bailed out before reaching it.
#   fill=          what the fill decision came out as on the last call. false
#                  during a navigation means navigating? said no.
#
# Reading the result:
#   tool= is not "CameraOrbitTool"  -> the guard never matches. Report the string.
#   ov=0                           -> native wall, nothing to be done from Ruby.
#   ov>0 grips=0                   -> Tool#draw bailed: check active= and state=.
#   grips>0 fill=false             -> navigating? wrong for this tool name.
#   grips>0 fill=true              -> it IS being painted; the problem is elsewhere.

module HTU_NavProbe
  P = TRINH_VAN_PHUC::HTU_ScalePlus

  class << self
    attr_accessor :overlay_draws, :grip_draws, :last_fill
  end
  @overlay_draws = 0
  @grip_draws = 0
  @last_fill = nil

  # Counted from prepended modules, not by aliasing.
  #
  # The first version aliased draw -> draw_unprobed and guarded on "does
  # draw_unprobed exist yet". HTU_ScalePlusReload.run then reloaded overlay.rb,
  # which redefined #draw and threw the wrapper away -- while draw_unprobed
  # survived, so the guard said "already instrumented" and refused to put it back.
  # Every count read 0 after a reload and the plugin looked like it had stopped
  # drawing entirely. A measuring instrument that lies is worse than none.
  #
  # A prepended module survives the class being reopened: the reload replaces
  # #draw in the class, and super still reaches it from here. prepend is also
  # idempotent, so re-running #on cannot double the counts.
  module CountOverlayDraw
    def draw(view)
      HTU_NavProbe.overlay_draws += 1
      super
    end
  end

  module CountGripDraw
    def draw_scale_points(view)
      HTU_NavProbe.grip_draws += 1
      HTU_NavProbe.last_fill =
        begin
          active_itself? || TRINH_VAN_PHUC::HTU_ScalePlus.navigating?
        rescue StandardError => e
          "raised #{e.class}"
        end
      super
    end
  end

  def self.instrument
    P::ScalePP2Overlay.prepend(CountOverlayDraw)
    P::ScalePPTool.prepend(CountGripDraw)
    true
  end

  def self.tool
    overlay = P::PLUGIN.active_overlay
    overlay && overlay.dim_scale
  rescue StandardError
    nil
  end

  def self.on
    instrument
    off
    @timer = UI.start_timer(0.25, true) do
      begin
        model = Sketchup.active_model
        t = tool
        # at= answers the one thing left unknown: whether Tools#active_tool still
        # reports our suspended tool while a native camera tool sits on top of it.
        # If it does, `at != tool` in Overlay#draw is a second way to lose the
        # grips, which is why that condition now also passes on navigating?.
        at = model.tools.active_tool
        puts format("tool=%-20s nav=%-5s active=%-5s flag=%-5s state=%-4s at=%-8s ov=%-3d grips=%-3d fill=%s",
                    model.tools.active_tool_name.to_s,
                    P.navigating?.to_s,
                    (t ? t.active?.to_s : "no tool"),
                    (t ? t.instance_variable_get(:@active).inspect : "-"),
                    (t ? t.instance_variable_get(:@tool_state).inspect : "-"),
                    (at.nil? ? "nil" : (t && at.equal?(t) ? "ours" : at.class.name.split("::").last)),
                    @overlay_draws,
                    @grip_draws,
                    @last_fill.inspect)
        @overlay_draws = 0
        @grip_draws = 0
      rescue StandardError => e
        puts "probe: #{e.class}: #{e.message}"
      end
    end
    puts "HTU_NavProbe: on. Chon 1 group, bam S, roi orbit / pan / zoom."
    puts "              HTU_NavProbe.off de tat."
    true
  end

  def self.off
    UI.stop_timer(@timer) if @timer
    @timer = nil
    true
  end
end
