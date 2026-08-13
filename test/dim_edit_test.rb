# frozen_string_literal: true

# Clicking a dimension turns it into a text field: the number shows selected,
# and typing replaces it. The drawing half needs a real viewport, but the state
# machine behind it does not -- and that is where the behaviour lives, so it is
# pinned here.
#
# The echo is a preview only. onUserText applies the VCB's own text, so these
# checks also cover the rule that an unmirrorable key gives up on the preview
# instead of showing something that does not match what will be applied.

require_relative "su_shim"
require File.expand_path("../htu_scaleplus.rb", __dir__)
$SU_CALLS[:register_extension].first.load_extension

TOOL = TRINH_VAN_PHUC::HTU_ScalePlus::ScalePPTool
VIEW = Sketchup.active_model.active_view

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

# A tool with an axis already locked, i.e. straight after the click.
def locked
  tool = TOOL.new(nil)
  tool.lock_axis("lenx")
  tool
end

def type(tool, *keys)
  keys.each { |k| tool.onKeyDown(k, 1, 0, VIEW) }
  tool
end

DIGITS = { "0" => 48, "1" => 49, "2" => 50, "4" => 52, "5" => 53, "8" => 56 }.freeze
BACKSPACE = 8
NUMPAD_7 = 103
PERIOD = 190
LETTER_M = 77
ENTER = 13
SHIFT = 16
F5 = 116
DELETE = 46

puts "--- straight after the click ---"

check "the axis is locked" do
  locked.locked_axis == "lenx"
end

check "nothing typed yet, so the number draws selected" do
  locked.edit_buffer.nil?
end

check "the VCB is primed with a label and a prompt" do
  locked
  $SU_CALLS[:status_text].last(3).map(&:first).any? { |t| t.to_s.include?("Type a length") }
end

puts "\n--- typing replaces the selection ---"

check "the first keystroke ends the selected state" do
  t = type(locked, DIGITS["4"])
  t.edit_buffer == "4"
end

check "digits accumulate in order" do
  type(locked, DIGITS["4"], DIGITS["5"], DIGITS["0"]).edit_buffer == "450"
end

check "numpad digits count the same as the top row" do
  type(locked, NUMPAD_7, DIGITS["5"]).edit_buffer == "75"
end

check "a decimal point is accepted" do
  type(locked, DIGITS["1"], PERIOD, DIGITS["5"]).edit_buffer == "1.5"
end

check "letters are accepted so a unit suffix mirrors too" do
  type(locked, DIGITS["8"], LETTER_M, LETTER_M).edit_buffer == "8mm"
end

puts "\n--- editing what was typed ---"

check "backspace removes the last character" do
  type(locked, DIGITS["4"], DIGITS["5"], BACKSPACE).edit_buffer == "4"
end

check "backspacing everything leaves an empty field, not the old number" do
  t = type(locked, DIGITS["4"], BACKSPACE)
  t.edit_buffer == "" && !t.edit_buffer.nil?
end

check "backspace on an empty field does not underflow" do
  type(locked, BACKSPACE, BACKSPACE).edit_buffer == ""
end

check "Delete clears the whole field" do
  type(locked, DIGITS["4"], DIGITS["5"], DELETE).edit_buffer == ""
end

puts "\n--- keys that are not the buffer's business ---"

check "Enter, Shift and F5 leave the echo alone" do
  t = type(locked, DIGITS["4"], SHIFT, ENTER, F5)
  t.edit_echo && t.edit_buffer == "4"
end

check "an unmirrorable key gives up the preview rather than guessing" do
  t = type(locked, DIGITS["4"], 219) # VK_OEM_4, layout dependent
  !t.edit_echo
end

check "once given up it stays given up for the rest of the entry" do
  t = type(locked, 219, DIGITS["4"], DIGITS["5"])
  !t.edit_echo && t.edit_buffer.nil?
end

check "the next click starts a fresh, mirrorable entry" do
  t = type(locked, 219)
  t.lock_axis("leny")
  t.edit_echo && t.edit_buffer.nil?
end

puts "\n--- leaving the field ---"

check "unlocking clears what was typed" do
  t = type(locked, DIGITS["4"])
  t.unlock_axis
  t.locked_axis.nil? && t.edit_buffer.nil?
end

check "keystrokes are ignored when no axis is locked" do
  t = TOOL.new(nil)
  type(t, DIGITS["4"])
  t.edit_buffer.nil?
end

check "an unreadable VCB entry re-selects instead of dropping the lock" do
  t = type(locked, DIGITS["4"])
  t.onUserText("nonsense", VIEW)
  t.locked_axis == "lenx" && t.edit_buffer.nil?
end

# Everything above is the field in front of the resize. None of it proves a resize
# happens, and until Geom::Transformation in the shim became a real matrix nothing
# could: .scaling ignored its arguments and #* returned self, so every size came out
# the same whatever the plugin did.
puts "\n--- typing a number actually resizes the object ---"

MODEL = Sketchup.active_model

def box(dx, dy, dz, tr = nil)
  group = Sketchup::Group.new
  group.local_bounds.add(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(dx, dy, dz))
  group.transformation = tr if tr
  MODEL.entities.add_entity(group)
  group
end

def armed(entity)
  tool = TOOL.new(nil)
  # @active directly: the setter runs activate, which recomputes from the real
  # selection and would throw away the state set up here.
  tool.instance_variable_set(:@active, true)
  tool.instance_variable_set(:@tool_state, 0)
  tool.instance_variable_set(:@model, MODEL)
  tool.instance_variable_set(:@view, VIEW)
  MODEL.selection.clear
  MODEL.selection.add(entity)
  tool.instance_variable_set(:@selection, MODEL.selection)
  tool.store_bounds_points
  tool.compute_dimensions(VIEW, true)
  tool
end

# How far the instance transformation stretches each of its own axes -- which is what
# #set_dim_value changes. Read as axis LENGTHS, not as the matrix diagonal: on a
# rotated object the diagonal is not the scale (a 90-degree turn puts the z scale at
# index 9), and a check reading it would be measuring itself rather than the plugin.
def scales(entity)
  tr = entity.transformation
  [tr.xaxis, tr.yaxis, tr.zaxis].map { |v| v.length.round(4) }
end

# 40 as the VCB reads it, so the expected factor can be stated exactly.
FORTY = "40".to_l

def resize(entity, axis, text = "40")
  tool = armed(entity)
  tool.lock_axis(axis)
  tool.onUserText(text, VIEW)
  tool
end

check "the harness scales at all, or nothing below means anything" do
  # Guard on the shim: a Transformation that swallowed #* would leave every check in
  # this section green while the plugin did nothing.
  tr = Geom::Transformation.scaling(2, 3, 4) * Geom::Transformation.new
  tr.to_a[0] == 2.0 && tr.to_a[5] == 3.0 && tr.to_a[10] == 4.0
end

check "the x label resizes x, and leaves y and z alone" do
  g = box(100, 60, 30)
  resize(g, "lenx")
  scales(g) == [(FORTY / 100).round(4), 1.0, 1.0]
end

check "the y label resizes y" do
  g = box(100, 60, 30)
  resize(g, "leny")
  scales(g) == [1.0, (FORTY / 60).round(4), 1.0]
end

# The one that was reported: "trục z mà thay đổi dimension không được".
check "the z label resizes z" do
  g = box(100, 60, 30)
  resize(g, "lenz")
  scales(g) == [1.0, 1.0, (FORTY / 30).round(4)]
end

check "an axis lock on the object does not block retyping a size" do
  # no_scale_mask governs SketchUp's grips. It has no say over a transformation set
  # from Ruby, and the labels must keep working under every one of them.
  [0, 120, 126, 125, 123].all? do |mask|
    g = box(100, 60, 30)
    g.definition.behavior.no_scale_mask = mask
    resize(g, "lenz")
    scales(g) == [1.0, 1.0, (FORTY / 30).round(4)]
  end
end

check "a nonsense entry resizes nothing" do
  g = box(100, 60, 30)
  resize(g, "lenz", "nonsense")
  scales(g) == [1.0, 1.0, 1.0]
end

check "a selection of two goes through transform_entities instead" do
  a = box(100, 60, 30)
  b = box(10, 10, 10)
  MODEL.selection.clear
  MODEL.selection.add(a, b)
  tool = TOOL.new(nil)
  tool.instance_variable_set(:@active, true)
  tool.instance_variable_set(:@tool_state, 0)
  tool.instance_variable_set(:@model, MODEL)
  tool.instance_variable_set(:@view, VIEW)
  tool.instance_variable_set(:@selection, MODEL.selection)
  tool.store_bounds_points
  tool.compute_dimensions(VIEW, true)
  $SU_CALLS[:transform_entities].clear
  tool.lock_axis("lenz")
  tool.onUserText("40", VIEW)
  tr, entities = $SU_CALLS[:transform_entities].last
  tr && tr.to_a[10] != 1.0 && entities.length == 2
end

# Resizing does NOT put the size on the saved list, removed on request 2026-08-13.
# Curic Scale++ did: set_dim_value ended in save_dim_to_object, which is
# DimFavorites.add, so every size ever typed joined the list. It is now only what the
# user put there deliberately, through the Dimensions window -- which is also the only
# place values come back out, so a list that filled itself was a list needing pruning.
#
# Every check here needs a positive control on the same line. "The list did not grow"
# passes just as well when the resize never happened, so each one asserts the object
# actually changed size too. Without that these are six checks that a no-op is a
# no-op.
puts "\n--- typing a size does not touch the saved list ---"

PLUG = TRINH_VAN_PHUC::HTU_ScalePlus
FAV = PLUG::DimFavorites

def reset_favorites!
  PLUG.settings = PLUG::Settings.new("HTU ScalePlus")
  Sketchup.defaults.delete(["HTU ScalePlus", FAV::SHARED_KEY.to_s])
  FAV::AXES.each { |axis| Sketchup.defaults.delete(["HTU ScalePlus", FAV.attribute(axis)]) }
end

X_RESIZED = [("40".to_l / 100).round(4), 1.0, 1.0].freeze

check "typing 40 resizes, and leaves the list empty" do
  reset_favorites!
  g = box(100, 60, 30)
  resize(g, "lenx")
  scales(g) == X_RESIZED && FAV.list(g, "lenx").empty?
end

# One list serves all three axes, so a leak on any one of them shows up on all three.
check "on none of the three axes" do
  ["lenx", "leny", "lenz"].all? do |axis|
    reset_favorites!
    g = box(100, 60, 30)
    resize(g, axis)
    scales(g) != [1.0, 1.0, 1.0] && FAV.list(g, "lenx").empty?
  end
end

# A list the user has filled must stay exactly as they left it -- not merely "not
# grow". An add that deduplicated would look like a no-op against an empty list.
check "a list the user filled is left exactly as it was" do
  reset_favorites!
  good, = FAV.parse("45, 200")
  FAV.add(nil, "lenx", good)
  before = FAV.list(nil, "lenx").map(&:to_f)
  g = box(100, 60, 30)
  resize(g, "lenx")
  scales(g) == X_RESIZED && FAV.list(nil, "lenx").map(&:to_f) == before
end

# Saving sat below apply_dim_value rather than on the typing path, so picking a size
# off the context menu saved it too. Both are gone with the one removal.
check "nor does picking a size off the menu" do
  reset_favorites!
  g = box(100, 60, 30)
  armed(g).apply_dim_value("lenx", "40".to_l)
  scales(g) == X_RESIZED && FAV.list(g, "lenx").empty?
end

check "nor does typing against a selection of two" do
  reset_favorites!
  a = box(100, 60, 30)
  b = box(10, 10, 10)
  MODEL.selection.clear
  MODEL.selection.add(a, b)
  tool = TOOL.new(nil)
  tool.instance_variable_set(:@active, true)
  tool.instance_variable_set(:@tool_state, 0)
  tool.instance_variable_set(:@model, MODEL)
  tool.instance_variable_set(:@view, VIEW)
  tool.instance_variable_set(:@selection, MODEL.selection)
  tool.store_bounds_points
  tool.compute_dimensions(VIEW, true)
  $SU_CALLS[:transform_entities].clear
  tool.lock_axis("lenz")
  tool.onUserText("40", VIEW)
  tr, = $SU_CALLS[:transform_entities].last
  tr && tr.to_a[10] != 1.0 && FAV.list(nil, "lenz").empty?
end

# The whole point of removing it: nothing reaches the list except the window. If
# DimFavorites.add is called at all on a resize, this raises rather than quietly
# saving, so it catches a save through any route -- not just the two known ones.
check "nothing on the resize path calls the list's writer at all" do
  reset_favorites!
  g = box(100, 60, 30)
  reached = false
  FAV.define_singleton_method(:add) { |*| reached = true }
  resize(g, "lenx")
  armed(box(100, 60, 30)).apply_dim_value("leny", "40".to_l)
  scales(g) == X_RESIZED && !reached
ensure
  FAV.singleton_class.send(:remove_method, :add)
end

# save_dim_to_object itself stays: dims.rb calls it for the Vue manager's own explicit
# save, which is a user asking to store a value rather than a side effect of resizing.
# DimsUI has no entry point left (HANDOFF section 8), so that caller is unreachable
# today -- the method is kept because removing it is a separate job, not because
# anything reaches it.
check "the storage method is still there for the manager's own save" do
  PLUG.respond_to?(:save_dim_to_object)
end

# A label can be legitimately absent: a dimension seen end-on is a dot, and there is
# nothing to draw or click. Which dimension that is depends on the camera, and it
# used to be decided against the WORLD z axis rather than the box's own third edge.
puts "\n--- which labels exist, and why one can be missing ---"

# 90 degrees about x, so the box's third edge lies horizontal. Built as a matrix
# because the shim's Transformation.rotation is still a stub.
ROT_X90 = Geom::Transformation.new([1, 0, 0, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1]).freeze

def looking_from(x, y, z)
  VIEW.camera.set(Geom::Point3d.new(x, y, z), Geom::Point3d.new(0, 0, 0))
  yield
ensure
  VIEW.camera.set(Geom::Point3d.new(100, 100, 100), Geom::Point3d.new(0, 0, 0))
end

def axes_of(tool)
  (tool.instance_variable_get(:@data_dims) || []).compact.map { |d| tool.dim_axis(d) }
end

def offsets_valid?(tool)
  (tool.instance_variable_get(:@dims) || []).all? { |(_line, vec)| vec && vec.valid? }
end

check "a three-quarter view offers all three" do
  axes_of(armed(box(100, 60, 30))).sort == %w[lenx leny lenz]
end

check "plan view drops the vertical one, it is a dot from there" do
  looking_from(0, 0, 100) { !axes_of(armed(box(100, 60, 30))).include?("lenz") }
end

check "a rotated object keeps its third label in plan view" do
  # The regression. Its third edge is horizontal, so the label draws perfectly well;
  # testing the world axis threw it away and took the only way to retype that size.
  looking_from(0, 0, 100) { axes_of(armed(box(100, 60, 30, ROT_X90))).include?("lenz") }
end

check "and that label still resizes the right axis" do
  looking_from(0, 0, 100) do
    g = box(100, 60, 30, ROT_X90)
    resize(g, "lenz")
    scales(g) == [1.0, 1.0, (FORTY / 30).round(4)]
  end
end

check "looking down that edge drops it rather than offsetting by nothing" do
  looking_from(0, 100, 0) do
    tool = armed(box(100, 60, 30, ROT_X90))
    !axes_of(tool).include?("lenz") && offsets_valid?(tool)
  end
end

# Being on the tool stack is the whole cost of this feature: an overlay gets no
# mouse-button callback, so catching the click that locks an axis means being a tool,
# and being a tool suspends SketchUp's Scale tool and its grips. So the tool must hold
# the stack for exactly as long as it needs the mouse and not a frame longer.
#
# There was a second reason to hold it -- retarget, where a click away from the
# selection switched the scale to another object. That went, and these checks are what
# replaced its. The one that matters most is the last: a click off a label must now
# leave the selection alone, because SketchUp's own Scale tool is getting it.
puts "\n--- holding the tool stack, and letting go ---"

def hovering(hover)
  tool = TOOL.new(nil)
  tool.instance_variable_set(:@active, true)
  tool.instance_variable_set(:@tool_state, 0)
  tool.instance_variable_set(:@model, MODEL)
  tool.instance_variable_set(:@view, VIEW)
  tool.instance_variable_set(:@bb_data, { :points => [] })
  # bb_text_2d is the label's screen box; an empty polygon is never hit, a big one
  # always is. #onMouseMove recomputes :hover from it on every move.
  box = hover ? [[0, 0], [9999, 0], [9999, 9999], [0, 9999]] : []
  dim = { :hover => hover, :bb_text_2d => box,
          :line => [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 0, 0)] }
  tool.instance_variable_set(:@data_dims, [dim])
  tool.instance_variable_set(:@tr_bb, Geom::Transformation.new)
  tool
end

def pops?(tool)
  MODEL.tools.stack.clear
  before = $SU_CALLS[:pop_tool].size
  tool.onMouseMove(0, 500, 400, VIEW)
  $SU_CALLS[:pop_tool].size > before
end

check "the cursor on a label keeps the stack, that is what it is for" do
  tool = hovering(true)
  tool.on_push_tool = true
  !pops?(tool)
end

check "off the label it hands the stack straight back" do
  tool = hovering(false)
  tool.on_push_tool = true
  pops?(tool)
end

# A nudge of the mouse would otherwise discard everything typed so far.
check "but not while an axis is locked and a number is being typed" do
  tool = hovering(false)
  tool.on_push_tool = true
  tool.lock_axis("lenx")
  !pops?(tool)
end

check "a click on the label locks its axis" do
  tool = hovering(true)
  tool.onLButtonDown(0, 500, 400, VIEW)
  tool.locked_axis == "lenx"
end

check "a click off the label releases the lock and gives the stack back" do
  tool = hovering(false)
  tool.on_push_tool = true
  tool.lock_axis("lenx")
  MODEL.tools.stack.clear
  before = $SU_CALLS[:pop_tool].size
  tool.onLButtonDown(0, 500, 400, VIEW)
  tool.locked_axis.nil? && $SU_CALLS[:pop_tool].size > before
end

# Retarget is gone, and this is the check that says so: the click belongs to
# SketchUp's Scale tool now, and it is the only thing that may change the selection.
check "and it does NOT change what is selected" do
  target = box(100, 60, 30)
  MODEL.selection.clear
  MODEL.selection.add(target)
  other = box(10, 10, 10)
  VIEW.pick_helper.picked = other
  tool = hovering(false)
  tool.on_push_tool = true
  tool.onLButtonDown(0, 500, 400, VIEW)
  MODEL.selection.to_a == [target]
end

puts "\n--- result ---"
if $fails.zero?
  puts "PASS — click selects the number, typing replaces it, the preview never lies"
  exit 0
else
  puts "FAIL — #{$fails} problem(s)"
  exit 1
end
