# frozen_string_literal: true

# With the Scale tool running, pointing at an object shows that object's
# dimensions -- no selecting it, no leaving the tool, no pressing S again.
#
# The labels are READ-ONLY, and that is not a limitation, it is the design. The
# tool takes the tool stack whenever #on_hover? is true, and taking the stack
# suspends SketchUp's Scale tool and its grips. If a hover label were a thing
# that could be clicked, the grips would switch off every time the cursor
# drifted across an object. So the labels live in their own array, outside
# everything that decides who owns the next click.
#
# The other rule these checks pin: the hovered object is measured by exactly the
# code that measures the selected one. A second implementation could disagree,
# and a number that changes when you click is worse than no number at all.

require_relative "su_shim"
require File.expand_path("../htu_scaleplus.rb", __dir__)
$SU_CALLS[:register_extension].first.load_extension

PLUG = TRINH_VAN_PHUC::HTU_ScalePlus
TOOL = PLUG::ScalePPTool
LOCK = PLUG::GroupLock
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

# A group of known size, in the model. The sizes are what the labels have to come
# out as, so they are deliberately all different and none of them square.
def box(dx, dy, dz)
  group = Sketchup::Group.new
  group.local_bounds.add(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(dx, dy, dz))
  MODEL.entities.add_entity(group)
  group
end

def hover_tool
  tool = TOOL.new(nil)
  # @active directly: the setter runs activate, which recomputes from the real
  # selection and would throw away the state each check sets up.
  tool.instance_variable_set(:@active, true)
  tool.instance_variable_set(:@tool_state, 0)
  tool
end

def selected(*entities)
  MODEL.selection.clear
  MODEL.selection.add(*entities) unless entities.empty?
  MODEL.selection
end

def under_cursor(entity)
  VIEW.pick_helper.picked = entity
end

def lengths(dims)
  (dims || []).compact.map { |d| d[:line].first.distance(d[:line].last).round(2) }.sort
end

# Each recorded call is [mode, points, colour in force]. Returns the 3D pass and
# the 2D pass separately, because which pass a thing is drawn in is part of what
# these checks are about.
def drawn(tool)
  $SU_CALLS[:draw].clear
  $SU_CALLS[:draw2d].clear
  tool.draw(VIEW)
  [$SU_CALLS[:draw].dup, $SU_CALLS[:draw2d].dup]
end

def navigating(name)
  MODEL.tools.active_tool_name = name
  yield
ensure
  MODEL.tools.active_tool_name = nil
end

puts "--- pointing at something measures it ---"

check "the shim itself can measure a box, or nothing below means anything" do
  # Guard on the harness, not on the plugin. Every check here reads lengths off a
  # bounding box, and the shim used to answer every corner with the origin -- so
  # all of them would have passed on an empty list of dimensions.
  lengths(hover_tool.build_hover_dims(VIEW, box(100, 60, 30))) == [30.0, 60.0, 100.0]
end

check "with nothing selected, the object under the cursor gets its sizes" do
  tool = hover_tool
  selected
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  lengths(tool.hover_dims) == [30.0, 60.0, 100.0]
end

check "and the object itself is remembered, not just its numbers" do
  tool = hover_tool
  target = box(10, 20, 40)
  selected
  under_cursor(target)
  tool.update_hover(500, 400, VIEW)
  tool.hover_object.equal?(target)
end

check "empty space clears them again" do
  tool = hover_tool
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  under_cursor(nil)
  tool.update_hover(300, 300, VIEW)
  tool.hover_dims.nil? && tool.hover_object.nil?
end

puts "\n--- loose geometry, which a click still refuses ---"

# Measured, because a model whose parts are drawn as loose faces rather than
# groups is exactly where reading a size off the cursor is most wanted. Found by
# probe, not by guessing: dev/htu_hover_probe.rb reported
#   raw: count=1 best=Face#41632 defn=NO -- bi bo qua
# on the surface the user said had no labels, while the ones that did were groups.
# The "near face fails, far face works" this was first reported as turned out to be
# coincidence -- two different kinds of thing at two different distances.
def face(dx, dy, dz = 0)
  f = Sketchup::Face.new
  f.bounds.add(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(dx, dy, dz))
  f
end

check "a loose face is measured, in world coordinates" do
  tool = hover_tool
  selected
  under_cursor(face(600, 494))
  tool.update_hover(500, 400, VIEW)
  lengths(tool.hover_dims) == [494.0, 600.0]
end

# Two, not three: a flat face has no third dimension to give. all_connected would
# find one, and on geometry welded to its neighbours it would report the size of
# everything it is welded to -- worse than a missing number.
check "and gets two dimensions, because a flat face has no thickness" do
  tool = hover_tool
  under_cursor(face(600, 494))
  tool.update_hover(500, 400, VIEW)
  tool.hover_dims.compact.size == 2
end

check "so only two grip axes are drawn, not a pair stacked in one place" do
  tool = hover_tool
  selected
  under_cursor(face(600, 494))
  tool.update_hover(500, 400, VIEW)
  _d3, d2 = drawn(tool)
  # Two live axes = four grips = twenty-four faces. The third centre line has zero
  # length and is dropped.
  d2.count { |mode, _, _| mode == GL_LINE_LOOP } == 4 * 6
end

# The whole point of keeping #pick_object as it was. Hover may measure a face;
# a click may not retarget to one, because a loose face is not something this
# plugin can scale as a unit.
check "but a click still refuses it -- hover measures more than a click targets" do
  tool = hover_tool
  loose = face(600, 494)
  under_cursor(loose)
  tool.pick_object(500, 400, VIEW).nil? && tool.hover_pick(500, 400, VIEW).equal?(loose)
end

check "empty space is still nothing at all" do
  tool = hover_tool
  under_cursor(nil)
  tool.update_hover(500, 400, VIEW)
  tool.hover_dims.nil? && tool.hover_pick(500, 400, VIEW).nil?
end

check "an edge is not measured -- one dimension is not worth the noise" do
  tool = hover_tool
  under_cursor(Sketchup::Edge.new)
  tool.update_hover(500, 400, VIEW)
  tool.hover_dims.nil?
end

puts "\n--- whole objects again ---"

check "a locked object is left alone, as everywhere else in the plugin" do
  tool = hover_tool
  locked = box(100, 60, 30)
  locked.define_singleton_method(:locked?) { true }
  under_cursor(locked)
  tool.update_hover(500, 400, VIEW)
  tool.hover_dims.nil?
end

check "moving to another object switches the labels to it" do
  tool = hover_tool
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  under_cursor(box(7, 8, 9))
  tool.update_hover(600, 400, VIEW)
  lengths(tool.hover_dims) == [7.0, 8.0, 9.0]
end

puts "\n--- the same numbers you get after clicking ---"

# The point of measuring the hovered object with compute_bounds_for rather than a
# second implementation. If these two ever disagree, the label lies about what
# the user is going to get.
check "hovering an object reports what selecting it would report" do
  tool = hover_tool
  target = box(123, 45, 67)
  under_cursor(target)
  tool.update_hover(500, 400, VIEW)
  hovered = lengths(tool.hover_dims)
  selected(target)
  tool.redraw(VIEW)
  hovered == lengths(tool.data_dims)
end

puts "\n--- what must not be disturbed ---"

# The grips are SketchUp's, and they are gone for as long as this tool holds the
# stack. #on_hover? is what makes it hold the stack, and it scans @data_dims --
# so a hover label put in there would cost the grips on every cursor drift.
check "a hover label is not something the tool takes the stack for" do
  tool = hover_tool
  selected
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  !tool.hover_dims.nil? && !tool.on_hover? && !tool.wants_push?
end

check "and it is not in the array the click handling reads" do
  tool = hover_tool
  selected
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  tool.data_dims.nil? || tool.data_dims.compact.empty?
end

check "pointing at something selects nothing and edits nothing" do
  tool = hover_tool
  keep = box(1, 2, 3)
  selected(keep)
  under_cursor(box(100, 60, 30))
  $SU_CALLS[:start_operation].clear
  tool.update_hover(500, 400, VIEW)
  MODEL.selection.to_a == [keep] && $SU_CALLS[:start_operation].empty?
end

check "what is already selected is skipped, so labels do not double up" do
  tool = hover_tool
  target = box(100, 60, 30)
  selected(target)
  under_cursor(target)
  tool.update_hover(500, 400, VIEW)
  tool.hover_dims.nil?
end

# The multi-object axis lock wraps the selection in a scratch group that exists
# only while the Scale tool is up. Labelling it would put numbers on something
# that is about to be exploded, and name a size the user never asked about.
check "the axis lock's wrapper group is not measured" do
  tool = hover_tool
  wrapper = box(100, 60, 30)
  wrapper.set_attribute(LOCK::TEMP_DICT, LOCK::TEMP_KEY, true)
  selected
  under_cursor(wrapper)
  tool.update_hover(500, 400, VIEW)
  tool.hover_dims.nil?
end

check "mid-drag there are no hover labels -- the user is busy scaling" do
  tool = hover_tool
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  tool.instance_variable_set(:@tool_state, 1)
  tool.update_hover(510, 400, VIEW)
  tool.hover_dims.nil?
end

check "nor while a dimension is being typed into" do
  tool = hover_tool
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  tool.instance_variable_set(:@locked_axis, "lenx")
  tool.update_hover(510, 400, VIEW)
  tool.hover_dims.nil?
end

check "leaving the tool takes them with it" do
  tool = hover_tool
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  tool.deactivate(VIEW)
  tool.hover_dims.nil?
end

# SketchUp calls #deactivate for two unrelated things. One is the user leaving the
# Scale tool, above. The other is this tool being popped off the stack after its
# own push, which happens every time the cursor comes back over the grips -- and
# clearing there wiped the labels on the same mouse event that had just computed
# them.
check "but being popped off the stack does not -- that is not leaving" do
  tool = hover_tool
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  tool.on_push_tool = true
  tool.deactivate(VIEW)
  !tool.hover_dims.nil?
end

puts "\n--- cost ---"

# Every pixel of movement arrives at update_hover. The pick is cheap; measuring
# is not -- text_geometry tessellates every glyph of every label -- so the same
# object must not be measured twice.
check "the same object is not re-measured for every pixel moved" do
  tool = hover_tool
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  first = tool.hover_dims
  tool.update_hover(540, 420, VIEW)
  tool.hover_dims.equal?(first)
end

check "a cursor that has not moved at all is not even picked" do
  tool = hover_tool
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  before = $SU_CALLS[:do_pick].size
  tool.update_hover(500, 400, VIEW)
  $SU_CALLS[:do_pick].size == before
end

# A camera move puts the labels somewhere else on screen without any mouse event
# arriving to say so, which is why #draw asks as well.
check "a camera move re-measures, so the labels follow the object" do
  tool = hover_tool
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  first = tool.hover_dims
  tool.instance_variable_set(:@hover_camera, { :eye => [0, 0, 0], :up => [0, 0, 1], :target => [1, 1, 1] })
  tool.refresh_hover(VIEW)
  !tool.hover_dims.nil? && !tool.hover_dims.equal?(first)
end

check "a camera that has not moved re-measures nothing" do
  tool = hover_tool
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  first = tool.hover_dims
  tool.refresh_hover(VIEW)
  tool.hover_dims.equal?(first)
end

check "an object deleted under the cursor drops its labels" do
  tool = hover_tool
  target = box(100, 60, 30)
  under_cursor(target)
  tool.update_hover(500, 400, VIEW)
  target.mark_deleted!
  tool.refresh_hover(VIEW)
  tool.hover_dims.nil?
end

puts "\n--- during a camera move ---"

# Nothing is picked and nothing is measured while the camera is being dragged:
# the pick is stale from the first frame of the gesture, and re-measuring on
# every frame of an orbit is the one place the cost would be felt.
check "no labels and no picking while the camera is being dragged" do
  tool = hover_tool
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  navigating("CameraOrbitTool") do
    before = $SU_CALLS[:do_pick].size
    tool.update_hover(520, 410, VIEW)
    tool.hover_dims.nil? && $SU_CALLS[:do_pick].size == before
  end
end

check "a pan hides them too, not just an orbit" do
  tool = hover_tool
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  navigating("CameraDollyTool") { tool.refresh_hover(VIEW) }
  tool.hover_dims.nil?
end

# The cursor has not moved when the middle button comes up, so the "same object,
# nothing to do" guard has to have been reset -- otherwise the labels stay away
# until the user happens to jiggle the mouse.
check "and they come back on the replay, with the cursor still where it was" do
  tool = hover_tool
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  navigating("CameraOrbitTool") { tool.update_hover(500, 400, VIEW) }
  tool.update_hover(500, 400, VIEW)
  lengths(tool.hover_dims) == [30.0, 60.0, 100.0]
end

puts "\n--- how they are drawn ---"

# #draw returns early when the SELECTION has no dimensions, and that is exactly
# the case hovering is most useful in: press S, then point at things.
check "labels are drawn with nothing selected at all" do
  tool = hover_tool
  selected
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  _d, d2 = drawn(tool)
  d2.any? { |mode, _, _| mode == GL_TRIANGLES }
end

# The look is measured off the reference capture, not chosen. An earlier version
# painted these flat grey, in 2D, without witness lines, reasoning that a label
# which cannot be clicked should not look like one that can. The capture shows the
# hovered object drawn in full -- axis colours, witness lines, grip cubes -- and
# the muted version read as a different, lesser feature. These three checks are
# what stop it drifting back.
check "in the axis colours, exactly like the selected object's dimensions" do
  tool = hover_tool
  selected
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  tool.hover_dims.compact.map { |d| d[:color] }.sort == %w[blue darkgreen red]
end

check "with witness lines" do
  tool = hover_tool
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  tool.hover_dims.compact.all? { |d| d[:extensions] && !d[:extensions].empty? }
end

check "and text in the model, not pasted flat on the screen" do
  tool = hover_tool
  selected
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  d3, _d2 = drawn(tool)
  d3.any? { |mode, _, _| mode == GL_TRIANGLES }
end

# Six grey cubes and three dotted centre lines, the same ones the selection gets.
check "the hovered object gets grip cubes too" do
  tool = hover_tool
  selected
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  _d3, d2 = drawn(tool)
  # Counted on the cubes, not on the dotted centre lines: the dimension witness
  # lines are GL_LINES too, so that mode cannot tell the two apart. Six grips,
  # six faces each, one LINE_LOOP per face.
  d2.count { |mode, _, _| mode == GL_LINE_LOOP } == 6 * 6
end

# SketchUp pre-highlights the object under the cursor in blue, but only while the
# Scale tool has nothing selected -- while it is still asking which object to scale.
# With a selection live it is not asking, and draws no box. Retargeting is exactly
# that case, so the box has to come from here or there is none: reported as "no blue
# highlight when hovering another object while scaling".
def hover_bounds_lines(tool)
  d3, _d2 = drawn(tool)
  d3.select { |mode, _, color| mode == GL_LINES && color == TOOL::HOVER_BOUNDS }
end

check "with an object being scaled, the hovered one gets a box" do
  tool = hover_tool
  selected(box(10, 10, 10))
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  # Twelve edges of a box, two points each.
  lines = hover_bounds_lines(tool)
  lines.length == 1 && lines.first[1].length == 24
end

check "and it is the hovered object's box, not the selection's" do
  tool = hover_tool
  selected(box(10, 10, 10))
  target = box(100, 60, 30)
  under_cursor(target)
  tool.update_hover(500, 400, VIEW)
  line = hover_bounds_lines(tool).first
  points = line && line[1]
  # The 2px camera-ward offset in #hack_point_draw is why this compares extents
  # rather than corners.
  spread = points && [0, 1, 2].map { |i| points.map { |pt| pt[i] }.minmax.reverse.reduce(:-).round }
  spread ? spread.sort == [30, 60, 100] : false
end

check "with nothing selected there is none, that box is SketchUp's" do
  tool = hover_tool
  selected
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  hover_bounds_lines(tool).empty?
end

check "and none once there is nothing under the cursor" do
  tool = hover_tool
  selected(box(10, 10, 10))
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  under_cursor(nil)
  tool.update_hover(300, 300, VIEW)
  hover_bounds_lines(tool).empty?
end

# It must not be mistaken for the selection's own box: one is what is being scaled,
# the other is what a click would scale instead. Each recorded draw carries the colour
# AND the width in force, so both halves of that are checkable here.
check "in blue, thinner than the yellow box on the object being scaled" do
  tool = hover_tool
  selected(box(10, 10, 10))
  target = box(100, 60, 30)
  under_cursor(target)
  tool.update_hover(500, 400, VIEW)
  d3, _d2 = drawn(tool)
  hover = d3.find { |mode, _, color, _| mode == GL_LINES && color == TOOL::HOVER_BOUNDS }
  # The selection's own box comes from a later part of the frame, behind the @dims
  # guard #draw returns on here, so it is asked for directly rather than faked.
  tool.instance_variable_set(:@bb, target.local_bounds)
  tool.instance_variable_set(:@tr_bb, Geom::Transformation.new)
  $SU_CALLS[:draw].clear
  tool.draw_selected_bounds(VIEW)
  own = $SU_CALLS[:draw].find { |mode, _, color, _| mode == GL_LINES && color == "yellow" }
  hover && own && hover[3] == 2 && own[3] == 3
end

# The green fill is this plugin standing in for a real grip that stopped being
# drawn. SketchUp draws its own grips on the object it is pre-highlighting, so a
# fill here would bury them -- and claim the object is the scale target when it
# is not.
check "but never filled green, which would claim it is the scale target" do
  tool = hover_tool
  selected
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  _d3, d2 = drawn(tool)
  d2.none? { |_, _, color| color == TOOL::GRIP_FILL }
end

# An axis lock on the hovered object is ITS mask, not the selection's -- the
# selection may have a different one, or there may be no selection at all.
check "a lock on the hovered object leaves one grip axis, not three" do
  tool = hover_tool
  locked_box = box(100, 60, 30)
  locked_box.definition.behavior.no_scale_mask = 126
  selected
  under_cursor(locked_box)
  tool.update_hover(500, 400, VIEW)
  _d3, d2 = drawn(tool)
  # One axis left = two grips = twelve faces.
  d2.count { |mode, _, _| mode == GL_LINE_LOOP } == 2 * 6
end

check "the toggle off means nothing is measured and nothing is drawn" do
  tool = hover_tool
  under_cursor(box(100, 60, 30))
  tool.update_hover(500, 400, VIEW)
  Sketchup.write_default(PLUG::PLUGIN_NAME, "hover_dim", false)
  tool.update_hover(520, 410, VIEW)
  _d, d2 = drawn(tool)
  ok = tool.hover_dims.nil? && d2.empty?
  Sketchup.write_default(PLUG::PLUGIN_NAME, "hover_dim", true)
  ok
end

check "on by default, and the toggle is remembered" do
  Sketchup.defaults.delete([PLUG::PLUGIN_NAME.to_s, "hover_dim"])
  on = PLUG.show_hover_dim?
  PLUG.toggle_hover_dimensions
  off = PLUG.show_hover_dim?
  PLUG.toggle_hover_dimensions
  on && !off && PLUG.show_hover_dim?
end

check "it is its own toggle, separate from the selection's dimensions" do
  Sketchup.write_default(PLUG::PLUGIN_NAME, "show_dim", true)
  PLUG.toggle_hover_dimensions
  still_on = PLUG.show_dim?
  PLUG.toggle_hover_dimensions
  still_on
end

puts "\n--- a frame with dimensions but no box ---"

# @dims outliving @bb is a real state, not a hypothetical: #deactivate nils the
# bounds (store_bounds_points with an empty selection) and does NOT recompute
# @dims. The next frame then hands a nil box to bound_points, which asks it for
# #width. #draw rescues that and prints it, so the symptom is the Ruby Console
# filling at frame rate while everything below the raise -- including the hover
# labels -- silently stops being drawn.
def tool_with_stale_dims
  tool = hover_tool
  selected(box(100, 60, 30))
  tool.redraw(VIEW)
  selected
  tool.deactivate(VIEW)
  tool
end

check "stale dimension lines with no bounds is a state that happens" do
  tool = tool_with_stale_dims
  # If this stops being true the two checks below are testing nothing.
  tool.instance_variable_get(:@bb).nil?
end

check "the yellow box is skipped rather than measured from nothing" do
  tool = tool_with_stale_dims
  $SU_CALLS[:draw].clear
  tool.draw_selected_bounds(VIEW)
  $SU_CALLS[:draw].empty?
end

check "and so are the grips" do
  tool = tool_with_stale_dims
  $SU_CALLS[:draw2d].clear
  tool.draw_scale_points(VIEW)
  $SU_CALLS[:draw2d].empty?
end

puts "\n--- the mouse events that feed it ---"

# An overlay is handed mouse moves whichever tool is active, and that is the only
# reason this works at all: while SketchUp's own Scale tool is up, the plugin's
# tool is off the stack and gets no events of its own.
def overlay_with_tool
  overlay = PLUG::ScalePP2Overlay.new
  overlay.enabled = true
  tool = overlay.dim_scale
  tool.instance_variable_set(:@active, true)
  tool.instance_variable_set(:@tool_state, 0)
  [overlay, tool]
end

check "a move relayed by the overlay updates the labels" do
  overlay, tool = overlay_with_tool
  MODEL.tools.stack.clear
  selected
  under_cursor(box(100, 60, 30))
  overlay.onMouseMove(0, 480, 380, VIEW)
  lengths(tool.hover_dims) == [30.0, 60.0, 100.0]
end

# While the tool holds the stack SketchUp calls its #onMouseMove itself, so the
# overlay must not call it again -- but the labels still have to keep up, and
# this is the only callback that arrives either way.
check "and so does one arriving while the tool holds the stack" do
  overlay, tool = overlay_with_tool
  relays = 0
  tool.define_singleton_method(:onMouseMove) { |*| relays += 1 }
  MODEL.tools.stack.clear
  MODEL.tools.push_tool(tool)
  selected
  under_cursor(box(11, 22, 33))
  overlay.onMouseMove(0, 470, 370, VIEW)
  MODEL.tools.stack.clear
  relays.zero? && lengths(tool.hover_dims) == [11.0, 22.0, 33.0]
end

puts "\n--- result ---"
if $fails.zero?
  puts "PASS — point at an object, read its size, grips untouched"
  exit 0
else
  puts "FAIL — #{$fails} problem(s)"
  exit 1
end
