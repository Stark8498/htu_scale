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

# SketchUp asks the tool on top of the stack what the cursor should be, and a tool
# that does not answer leaves whatever was set last -- here, the Scale tool's
# arrow-with-a-grip-box. That box says "drag a grip", which is untrue everywhere
# this tool holds the stack: outside the padded box a click retargets, and over a
# label it edits a number.
check "it answers, rather than leaving the Scale cursor standing" do
  $SU_CALLS[:set_cursor].clear
  answered = tool_with_bounds(BOX).onSetCursor
  answered && $SU_CALLS[:set_cursor] == [TOOL::PLAIN_CURSOR]
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
def grip_tool
  t = tool_with_bounds(BOX)
  t.instance_variable_set(:@bb, Geom::BoundingBox.new)
  t.instance_variable_set(:@tr_bb, Geom::Transformation.new)
  t.instance_variable_set(:@bb_center, Geom::Point3d.new)
  t
end

# Each recorded call is [mode, points, colour in force].
def grips_drawn(pushed)
  tool = grip_tool
  MODEL.tools.stack.clear
  MODEL.tools.push_tool(tool) if pushed
  $SU_CALLS[:draw2d].clear
  tool.draw_scale_points(VIEW)
  MODEL.tools.stack.clear
  $SU_CALLS[:draw2d].dup
end

def component_locked_to(mask)
  group = Sketchup::Group.new
  group.definition.behavior.no_scale_mask = mask
  group
end

# The rule, and the whole of it: SketchUp is drawing the real grips, and the real
# ones are always right about which grips exist. Nothing this tool draws can improve
# on that, and on a flat selection it disagrees.
check "while the Scale tool draws its own, this tool draws none" do
  selected
  grips_drawn(false).empty?
end

check "once this tool holds the stack it draws them, filled in" do
  selected
  filled = grips_drawn(true).select { |mode, _, _| mode == GL_POLYGON }
  !filled.empty? && filled.all? { |_, _, color| color == TOOL::GRIP_FILL }
end

check "and outlines them too, so a grip keeps its edge" do
  selected
  grips_drawn(true).any? { |mode, _, _| mode == GL_LINE_LOOP }
end

# The lock used to be ignored while this tool held the stack, so taking the stack
# handed back the two axes the lock had just taken off. That is what these two pin,
# and the mask still has to be obeyed by the substitutes.
check "an axis lock leaves one axis in the substitutes" do
  selected(component_locked_to(126))
  grips_drawn(true).count { |mode, _, _| mode == GL_LINES } == 1
end

check "and with no lock all three are offered" do
  selected(component_locked_to(0))
  grips_drawn(true).count { |mode, _, _| mode == GL_LINES } == 3
end

puts "\n--- result ---"
if $fails.zero?
  puts "PASS — click to switch objects, grips still belong to SketchUp"
  exit 0
else
  puts "FAIL — #{$fails} problem(s)"
  exit 1
end
