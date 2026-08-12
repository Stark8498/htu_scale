# frozen_string_literal: true

# The grips belong to SketchUp, and this tool only ever stands in for them.
#
# It has to stand in at all because clicking a dimension's number means being a tool
# for as long as the cursor is on that number -- an overlay gets no mouse-button
# callback -- and being a tool suspends SketchUp's Scale tool, which takes its green
# grips with it. Without a substitute they read as switched off for as long as the
# cursor rests on a label.
#
# So the rule these checks pin is: draw them only while SketchUp is not, and draw the
# same set SketchUp would have. The second half is what makes the swap invisible.
#
# Split out of retarget_test.rb, which went with the retarget feature. The grips are
# older than that feature and outlived it.

require_relative "su_shim"
require File.expand_path("../htu_scaleplus.rb", __dir__)
$SU_CALLS[:register_extension].first.load_extension

PLUG = TRINH_VAN_PHUC::HTU_ScalePlus
TOOL = PLUG::ScalePPTool
MODEL = Sketchup.active_model
VIEW = MODEL.active_view

$fails = 0

def check(label)
  ok = yield
  puts format("  %-58s %s", label, ok ? "OK" : "FAIL")
  $fails += 1 unless ok
rescue Exception => e
  puts format("  %-58s RAISED %s: %s", label, e.class, e.message)
  puts "    #{e.backtrace.reject { |l| l.include?('su_shim') }.first}"
  $fails += 1
end

def selected(*entities)
  MODEL.selection.clear
  MODEL.selection.add(*entities) unless entities.empty?
  MODEL.selection
end

# A real box, really selected, really measured. The fixture used to hand the tool an
# EMPTY Geom::BoundingBox and a @bb_data carrying nothing but :points, so
# #draw_scale_points never reached the mask's own grip set and every check below was
# measuring the fallback path instead of the code that runs.
def grip_tool(mask = 0)
  group = Sketchup::Group.new
  group.local_bounds.add(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(100, 60, 30))
  group.definition.behavior.no_scale_mask = mask
  MODEL.entities.add_entity(group)
  selected(group)
  tool = TOOL.new(nil)
  # @active directly, not `active = true`: the setter runs activate, which recomputes
  # from the real selection and would throw away the state set up here.
  tool.instance_variable_set(:@active, true)
  tool.instance_variable_set(:@tool_state, 0)
  tool.instance_variable_set(:@selection, MODEL.selection)
  tool.store_bounds_points
  tool
end

# Each recorded call is [mode, points, colour, line width in force].
def grips_drawn(pushed, mask = 0)
  tool = grip_tool(mask)
  MODEL.tools.stack.clear
  MODEL.tools.push_tool(tool) if pushed
  $SU_CALLS[:draw2d].clear
  tool.draw_scale_points(VIEW)
  MODEL.tools.stack.clear
  $SU_CALLS[:draw2d].dup
end

# One grip is a cube: six faces, so six GL_POLYGON when filled and six GL_LINE_LOOP.
def grip_count(calls, mode = GL_POLYGON)
  calls.count { |m, _, _, _| m == mode } / 6
end

def axis_lines(calls)
  calls.count { |m, _, _, _| m == GL_LINES }
end

puts "--- only while SketchUp is not drawing its own ---"

# It used to draw grey outlines in both states, on the theory that they would sit on
# top of SketchUp's green ones and let the green show through the middle. On a flat
# selection that is untrue: SketchUp offers a different set than #bounds_center_lines
# produces, so four outlines were left standing where there was no grip at all.
# Reported as "choosing XYZ makes the axis grips go inactive".
check "while the Scale tool draws its own, this tool draws none" do
  grips_drawn(false).empty?
end

check "once this tool holds the stack it draws them, filled in" do
  filled = grips_drawn(true).select { |mode, _, _, _| mode == GL_POLYGON }
  !filled.empty? && filled.all? { |_, _, color, _| color == TOOL::GRIP_FILL }
end

check "and outlines them too, so a grip keeps its edge" do
  grips_drawn(true).any? { |mode, _, _, _| mode == GL_LINE_LOOP }
end

puts "\n--- the same set SketchUp would show ---"

# The substitutes stand in for grips the user was looking at a frame earlier, so the
# COUNT has to match or the swap is visible. It did not match: with no lock SketchUp
# offers 26 and this drew 6. Reported as "the points blink when I move the mouse near
# the object being scaled".
#
# 26 = 8 corners + 12 edge midpoints + 6 face centres, which is what
# #compute_bounds_for already works out from the mask -- the numbers here are read off
# bb_data as well as off the draw calls, so a change in either has to be a change in
# both.
EXPECTED_GRIPS = { 0 => 26, 120 => 6, 126 => 2, 125 => 2, 123 => 2 }.freeze

EXPECTED_GRIPS.each do |mask, expected|
  name = { 0 => "no lock", 120 => "xyz", 126 => "x", 125 => "y", 123 => "z" }[mask]
  check "#{name}: the substitutes are the #{expected} grips the mask calls for" do
    tool = grip_tool(mask)
    from_bounds = Array(tool.bb_data[:scale_points]).flatten.length
    MODEL.tools.stack.clear
    MODEL.tools.push_tool(tool)
    $SU_CALLS[:draw2d].clear
    tool.draw_scale_points(VIEW)
    MODEL.tools.stack.clear
    from_bounds == expected && grip_count($SU_CALLS[:draw2d]) == expected
  end
end

# The dotted axis line is part of the same faithfulness question: SketchUp draws one
# along a locked axis and none at all with no lock, so drawing three unlocked lines
# blinked them in and out at the very same moment.
check "a locked axis gets its dotted line, the way SketchUp shows it" do
  axis_lines(grips_drawn(true, 126)) == 1
end

check "and with no lock there are no axis lines to blink" do
  axis_lines(grips_drawn(true, 0)).zero?
end

puts "\n--- the cursor is SketchUp's business too ---"

# Holding the stack changes what a click does -- over a label it edits a number -- and
# the Scale cursor keeps saying "drag a grip" throughout. That was answered once, with
# the plain arrow, and the user asked for the icon back: it is how they can see
# Scale++ is running. So taking the stack must not change the cursor at all. That
# nothing anywhere sets one is pinned in navigation_test.rb.
check "taking the stack leaves the cursor alone" do
  $SU_CALLS[:set_cursor].clear
  tool = grip_tool
  tool.onMouseMove(0, 900, 700, VIEW)
  tool.on_push_tool = true
  $SU_CALLS[:set_cursor].empty?
end

puts "\n--- a frame with dimensions but no box ---"

# #deactivate runs store_bounds_points with an empty selection, which sets @bb to nil,
# and does NOT recompute @dims. The next frame got past the @dims guard and handed a
# nil box to bound_points, asking for #width on nil. draw rescues and prints, so the
# symptom was a Ruby Console filling with "undefined method 'width' for nil".
# Measured with the box still selected, then the selection dropped -- which is the
# order #deactivate does it in.
def stale_dims_tool
  tool = grip_tool
  tool.compute_dimensions(VIEW, true)
  selected
  tool.store_bounds_points
  tool
end

check "stale dimension lines with no bounds is a state that happens" do
  tool = stale_dims_tool
  tool.instance_variable_get(:@bb).nil? && !Array(tool.instance_variable_get(:@dims)).empty?
end

check "the grips are skipped rather than measured from nothing" do
  tool = stale_dims_tool
  MODEL.tools.stack.clear
  MODEL.tools.push_tool(tool)
  $SU_CALLS[:draw2d].clear
  tool.draw_scale_points(VIEW)
  MODEL.tools.stack.clear
  $SU_CALLS[:draw2d].empty?
end

puts "\n--- result ---"
if $fails.zero?
  puts "PASS — the substitutes match what SketchUp would have drawn"
  exit 0
else
  puts "FAIL — #{$fails} problem(s)"
  exit 1
end
