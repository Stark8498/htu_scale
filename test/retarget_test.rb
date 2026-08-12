# frozen_string_literal: true

# With the Scale tool running on one object, clicking another should scale that
# one instead -- no leaving the tool, reselecting and pressing S again. Clicking
# empty space drops the selection and waits for the next object.
#
# Doing that means taking the click away from SketchUp's Scale tool, and its
# scale grips are the thing that must not be taken away. The whole design is one
# rule: outside the selection's padded screen box the click is this tool's,
# inside it belongs to the grips. These checks pin that rule and the retarget
# behaviour it enables.

require_relative "su_shim"
require File.expand_path("../htu_scaleplus.rb", __dir__)
$SU_CALLS[:register_extension].first.load_extension

PLUG = TRINH_VAN_PHUC::HTU_ScalePlus
TOOL = PLUG::ScalePPTool
MODEL = Sketchup.active_model
VIEW = MODEL.active_view
MARGIN = TOOL::GRIP_MARGIN

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

# The shim projects a point (x, y, z) to screen (x, y), so a bounds box given in
# model coordinates lands on screen at the same numbers.
def tool_with_bounds(corners)
  tool = TOOL.new(nil)
  # @active directly, not `active = true`: the setter runs activate, which
  # recomputes the bounds from the real selection and would throw away the box
  # being set up here.
  tool.instance_variable_set(:@active, true)
  tool.instance_variable_set(:@tool_state, 0)
  tool.instance_variable_set(:@bb_data, { :points => corners.map { |x, y| Geom::Point3d.new(x, y, 0) } })
  tool
end

BOX = [[100, 100], [300, 100], [300, 200], [100, 200]].freeze

def selected(*entities)
  MODEL.selection.clear
  MODEL.selection.add(*entities) unless entities.empty?
  MODEL.selection
end

def under_cursor(entity)
  VIEW.pick_helper.picked = entity
end

puts "--- where the grips end and this tool begins ---"
tool = tool_with_bounds(BOX)

check "dead centre of the selection is the Scale tool's" do
  !tool.outside_grips?(200, 150, VIEW)
end

check "just outside the box is still the Scale tool's, that is the margin" do
  !tool.outside_grips?(300 + MARGIN - 2, 150, VIEW)
end

check "past the margin the click is ours" do
  tool.outside_grips?(300 + MARGIN + 2, 150, VIEW)
end

check "the margin applies on every side" do
  [[100 - MARGIN - 2, 150], [200, 100 - MARGIN - 2], [200, 200 + MARGIN + 2]].all? do |x, y|
    tool.outside_grips?(x, y, VIEW)
  end
end

check "with nothing selected there is no box, so every click is ours" do
  TOOL.new(nil).outside_grips?(200, 150, VIEW)
end

puts "\n--- staying on the stack to catch that click ---"

check "the tool wants the stack once the cursor leaves the grips" do
  t = tool_with_bounds(BOX)
  t.onMouseMove(0, 900, 700, VIEW)
  t.wants_push? && t.own_click?
end

check "and gives it back over the grips, so dragging still works" do
  t = tool_with_bounds(BOX)
  t.onMouseMove(0, 200, 150, VIEW)
  !t.own_click?
end

check "mid-drag it never takes the stack, wherever the cursor is" do
  t = tool_with_bounds(BOX)
  t.instance_variable_set(:@tool_state, 1)
  t.onMouseMove(0, 900, 700, VIEW)
  !t.own_click?
end

check "a pushed tool is not popped while it is holding the click" do
  t = tool_with_bounds(BOX)
  t.on_push_tool = true
  before = $SU_CALLS[:pop_tool].size
  t.onMouseMove(0, 900, 700, VIEW)
  $SU_CALLS[:pop_tool].size == before
end

check "but it does pop once the cursor is back on the grips" do
  t = tool_with_bounds(BOX)
  t.on_push_tool = true
  before = $SU_CALLS[:pop_tool].size
  t.onMouseMove(0, 200, 150, VIEW)
  $SU_CALLS[:pop_tool].size > before
end

puts "\n--- the cursor while it holds the stack ---"

# Holding the stack changes what a click does -- outside the padded box it retargets,
# over a label it edits a number -- and the Scale cursor keeps saying "drag a grip"
# throughout. That was answered once, with the plain arrow, and the user asked for the
# icon back: it is how they can see Scale++ is running. So taking the stack must not
# change the cursor at all. Whether it stays that way across BOTH removed halves is
# pinned in navigation_test.rb.
check "taking the stack leaves the cursor alone" do
  $SU_CALLS[:set_cursor].clear
  tool = tool_with_bounds(BOX)
  tool.onMouseMove(0, 900, 700, VIEW)
  tool.on_push_tool = true
  $SU_CALLS[:set_cursor].empty?
end

puts "\n--- the click itself ---"
a = Sketchup::Group.new
b = Sketchup::Group.new

check "clicking another object makes it the one being scaled" do
  t = tool_with_bounds(BOX)
  selected(a)
  under_cursor(b)
  t.onLButtonDown(0, 900, 700, VIEW)
  MODEL.selection.to_a == [b]
end

check "the model is asked what is there, not guessed from the last hover" do
  t = tool_with_bounds(BOX)
  selected(a)
  under_cursor(b)
  $SU_CALLS[:do_pick].clear
  t.onLButtonDown(0, 640, 480, VIEW)
  $SU_CALLS[:do_pick].last == [640, 480]
end

check "clicking empty space drops the selection and waits" do
  t = tool_with_bounds(BOX)
  selected(a)
  under_cursor(nil)
  t.onLButtonDown(0, 900, 700, VIEW)
  MODEL.selection.empty?
end

check "clicking what is already being scaled changes nothing" do
  t = tool_with_bounds(BOX)
  selected(a)
  under_cursor(a)
  t.onLButtonDown(0, 900, 700, VIEW)
  MODEL.selection.to_a == [a]
end

check "raw geometry is not a scale target, so it is ignored" do
  t = tool_with_bounds(BOX)
  selected(a)
  under_cursor(Sketchup::Face.new)
  t.onLButtonDown(0, 900, 700, VIEW)
  MODEL.selection.empty?
end

check "a locked object is left alone" do
  t = tool_with_bounds(BOX)
  locked = Sketchup::Group.new
  locked.define_singleton_method(:locked?) { true }
  selected(a)
  under_cursor(locked)
  t.onLButtonDown(0, 900, 700, VIEW)
  !MODEL.selection.to_a.include?(locked)
end

puts "\n--- what the click must not disturb ---"

check "a click on a dimension still locks the axis, not retargets" do
  t = tool_with_bounds(BOX)
  selected(a)
  under_cursor(b)
  dim = { :hover => true, :line => [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 0, 0)] }
  t.instance_variable_set(:@data_dims, [dim])
  t.instance_variable_set(:@tr_bb, Geom::Transformation.new)
  t.onLButtonDown(0, 900, 700, VIEW)
  MODEL.selection.to_a == [a]
end

puts "\n--- the grips must not read as switched off ---"

# The moment this tool takes the stack, SketchUp stops drawing the Scale tool's
# green grips, and without a substitute they read as disabled for as long as the
# cursor is away. So this tool draws its own -- but ONLY then.
#
# It used to draw grey outlines in both states, on the theory that they would sit on
# top of SketchUp's green ones and let the green show through the middle. On a flat
# selection that is untrue: SketchUp offers a different set of grips than
# #bounds_center_lines produces, so four outlines were left standing where there was
# no grip at all. Reported as "choosing XYZ makes the axis grips go inactive".
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
  t = TOOL.new(nil)
  t.instance_variable_set(:@active, true)
  t.instance_variable_set(:@tool_state, 0)
  t.instance_variable_set(:@selection, MODEL.selection)
  t.store_bounds_points
  t
end

# Each recorded call is [mode, points, colour in force].
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
  calls.count { |m, _, _| m == mode } / 6
end

def axis_lines(calls)
  calls.count { |m, _, _| m == GL_LINES }
end

# The rule, and the whole of it: SketchUp is drawing the real grips, and the real
# ones are always right about which grips exist. Nothing this tool draws can improve
# on that, and on a flat selection it disagrees.
check "while the Scale tool draws its own, this tool draws none" do
  grips_drawn(false).empty?
end

check "once this tool holds the stack it draws them, filled in" do
  filled = grips_drawn(true).select { |mode, _, _| mode == GL_POLYGON }
  !filled.empty? && filled.all? { |_, _, color| color == TOOL::GRIP_FILL }
end

check "and outlines them too, so a grip keeps its edge" do
  grips_drawn(true).any? { |mode, _, _| mode == GL_LINE_LOOP }
end

# The substitutes stand in for grips the user was looking at a frame earlier, so the
# COUNT has to match or the swap is visible. It did not match: with no lock SketchUp
# offers 26 and this drew 6, and the cursor crosses GRIP_MARGIN constantly while
# approaching the object. Reported as "the points blink when I move the mouse near the
# object being scaled".
#
# 26 = 8 corners + 12 edge midpoints + 6 face centres, which is what
# #compute_bounds_for already works out from the mask -- the numbers here are read off
# bb_data rather than retyped, so a change in either has to be a change in both.
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
# blinked them in and out at the very same boundary.
check "a locked axis gets its dotted line, the way SketchUp shows it" do
  axis_lines(grips_drawn(true, 126)) == 1
end

check "and with no lock there are no axis lines to blink" do
  axis_lines(grips_drawn(true, 0)).zero?
end

puts "\n--- result ---"
if $fails.zero?
  puts "PASS — click to switch objects, grips still belong to SketchUp"
  exit 0
else
  puts "FAIL — #{$fails} problem(s)"
  exit 1
end
