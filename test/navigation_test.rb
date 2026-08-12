# frozen_string_literal: true

# Orbiting, panning and zooming in the middle of a scale must cost nothing.
#
# SketchUp implements all three as tool changes: hold the middle mouse button and
# the active tool becomes CameraOrbitTool, shift+middle makes it CameraPanTool,
# and both hand the Scale tool back the moment the button comes up. The plugin
# hangs everything off onActiveToolChanged, so each of those looked exactly like
# the user leaving the Scale tool for good.
#
# Only orbit was recognised, which meant a pan or a zoom cost three things at
# once: the dimensions stopped being drawn, a dimension being typed into lost its
# axis lock and everything typed so far, and the multi-object wrapper was
# exploded out from under a scale in progress. These checks pin the whole set of
# navigation tools, including the mangled names macOS reports.

require_relative "su_shim"
require File.expand_path("../htu_scaleplus.rb", __dir__)
$SU_CALLS[:register_extension].first.load_extension

PLUG = TRINH_VAN_PHUC::HTU_ScalePlus
LOCK = PLUG::GroupLock
OBS = PLUG::ScalePP2Observer
MODEL = Sketchup.active_model

XYZ = 120

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

# Stands in for the overlay so the question "was this tool change relayed at all?"
# can be answered. PLUGIN.active_overlay reads model.overlays, which the shim
# keeps empty, so the observer would otherwise return early for every name and
# every check below would pass without testing anything.
class OverlaySpy
  attr_reader :seen
  def initialize; @seen = []; end
  def enabled?; true; end
  def valid?; true; end
  def tool_changed(tool_name); @seen << tool_name; end
  def onToolStateChanged(*); end
end

# Restored by delegating back to the captured Method rather than by removing the
# override: both live in the same singleton method table, so remove_method would
# take the real one with it and every later test in this file would break.
def with_overlay(spy)
  original = PLUG.method(:active_overlay)
  PLUG.define_singleton_method(:active_overlay) { |*_a| spy }
  yield spy
ensure
  PLUG.define_singleton_method(:active_overlay) { |*a| original.call(*a) }
end

def observer
  OBS::ScalePP2_ToolsOb.new(OBS.new)
end

def relayed(tool_name)
  with_overlay(OverlaySpy.new) do |spy|
    observer.onActiveToolChanged(MODEL.tools, tool_name, 21_236)
    return spy.seen
  end
end

# Every name SketchUp reports while the camera is being moved, and nothing else.
#
# CameraOrbitTool and CameraDollyTool are MEASURED, straight out of
# dev/htu_nav_probe.rb on SU 2026. CameraDollyTool was the surprise: the docs point
# at "CameraPanTool", which SketchUp does not appear to report at all. It was
# caught anyway, but only because the guard matches keywords and "Camera" is one of
# them -- an exact-name list would have missed it and cost pan its dimensions.
#
# The rest are still documentation, not observation. Kept because being generous
# here is the safe direction, but do not read them as confirmed.
NAVIGATION = [
  "CameraOrbitTool",       # measured: middle-mouse orbit
  "CameraDollyTool",       # measured
  "CameraPanTool",
  "CameraZoomTool",
  "CameraZoomWindowTool",
  "WalkTool",
  "LookAroundTool",
  "PositionCameraTool",
].freeze

puts "--- navigating the camera is not a tool change ---"

NAVIGATION.each do |name|
  check "#{name} is never relayed to the overlay" do
    relayed(name).empty?
  end
end

# fix_mac_tool_name exists because macOS reports these with the front chopped
# off, which is why the guard matches on a keyword instead of a whole name. What
# is claimed here is exactly what a keyword can deliver: any truncation that
# leaves the word itself intact.
check "a truncated macOS navigation name is still recognised" do
  ["raOrbitTool", "aPanTool", "ZoomTool", "kAroundTool"].all? { |name| relayed(name).empty? }
end

# The other half of the same fact, stated so it cannot rot into a surprise: the
# truncations already recorded in fix_mac_tool_name go as far as "ool" for
# MoveTool, and no keyword survives that. Such a name reads as a real tool
# change, which costs the dimensions -- the safe direction to fail in, and the
# reason this is a known limit rather than a bug. tool_id is the real fix, once
# someone can capture the ids on a mac.
#
# "omTool" is what CameraZoomTool truncated past its keyword would look like.
# Not "ool", which fix_mac_tool_name already maps back to MoveTool.
check "a truncation past the keyword is a known miss, not a silent one" do
  relayed("omTool") == ["omTool"]
end

# And the mapping that does exist still runs before the guard, so a mangled name
# it knows about arrives as the real tool rather than as itself.
check "fix_mac_tool_name still resolves the names it does know" do
  relayed("ool") == ["MoveTool"] && relayed("eTool") == ["ScaleTool"]
end

puts "\n--- a real tool change still gets through ---"

["SelectionTool", "MoveTool", "RotateTool", "PushPullTool", "EraseTool"].each do |name|
  check "#{name} is relayed" do
    relayed(name) == [name]
  end
end

check "ScaleTool itself is relayed" do
  relayed("ScaleTool") == ["ScaleTool"]
end

# The one name that contains none of the navigation words but is easy to break a
# loose match on: PaintTool against /Pan/.
check "PaintTool is not mistaken for a pan" do
  relayed("PaintTool") == ["PaintTool"]
end

puts "\n--- what the overlay restores to ---"

# Overlay#start replays last_tool_name. Recording "CameraOrbitTool" there means a
# rebuilt overlay comes back with the Scale tool switched off.
check "navigation does not become the remembered tool" do
  parent = OBS.new
  parent.last_tool_name = "ScaleTool"
  ob = OBS::ScalePP2_ToolsOb.new(parent)
  NAVIGATION.each { |name| ob.onActiveToolChanged(MODEL.tools, name, 21_236) }
  parent.last_tool_name == "ScaleTool"
end

check "a real tool does become the remembered tool" do
  parent = OBS.new
  parent.last_tool_name = "ScaleTool"
  ob = OBS::ScalePP2_ToolsOb.new(parent)
  ob.onActiveToolChanged(MODEL.tools, "SelectionTool", 21_236)
  parent.last_tool_name == "SelectionTool"
end

puts "\n--- the multi-object wrapper survives navigation ---"

def wrapped(state = XYZ)
  Sketchup.write_default("htu_behavior", "state", state)
  MODEL.entities.to_a.each { |e| MODEL.entities.remove_entity(e) }
  MODEL.selection.clear
  LOCK.instance_variable_set(:@temp_group, nil)
  LOCK.instance_variable_set(:@previous_selection, [])
  objects = Array.new(2) do
    group = Sketchup::Group.new
    MODEL.entities.add_entity(group)
    group
  end
  MODEL.selection.add(*objects)
  [LOCK.wrap(MODEL), objects]
end

# The worst of the three losses: exploding here drops the handles the user is
# mid-drag on, and the scale with them.
def fire(tool_name)
  at = $SU_TIMERS.size
  observer.onActiveToolChanged(MODEL.tools, tool_name, 21_236)
  $SU_TIMERS[at..-1].to_a.each { |t| t[:proc].call }
end

NAVIGATION.each do |name|
  check "#{name} does not explode the wrapper" do
    group, = wrapped
    fire(name)
    group.valid? && LOCK.temp_group.equal?(group)
  end
end

check "leaving for a real tool still explodes it" do
  group, objects = wrapped
  fire("SelectionTool")
  !group.valid? && LOCK.temp_group.nil? && MODEL.entities.to_a == objects
end

# A whole navigation round trip, which is what actually happens: press middle
# mouse, orbit, release, and SketchUp reports ScaleTool again.
check "orbit and back leaves the wrapper exactly as it was" do
  group, = wrapped
  fire("CameraOrbitTool")
  fire("ScaleTool")
  group.valid? && LOCK.temp_group.equal?(group) && MODEL.selection.to_a == [group]
end

puts "\n--- the real Scale tool keeps its grips ---"

# Stands in for ScalePPTool so the two decisions the overlay makes -- dispatch the
# move, and take the stack -- can be read off directly. #wants_push? is fixed
# rather than derived, because what is being tested is what the overlay does with
# the answer, not how the tool arrives at it.
class ToolSpy
  attr_accessor :on_push_tool, :active
  attr_reader :moves
  def initialize(wants_push)
    @wants_push = wants_push
    @on_push_tool = false
    @active = true
    @moves = []
  end
  def tool_name; "ScaleTool"; end
  def active?; @active; end
  def wants_push?; @wants_push; end
  def onMouseMove(_flags, x, y, _view); @moves << [x, y]; end
  def draw(*); end
end

def overlay_with(spy, navigating)
  overlay = PLUG::ScalePP2Overlay.new
  overlay.enabled = true
  overlay.instance_variable_set(:@tools, [])
  overlay.register_tool(spy)
  MODEL.tools.stack.clear
  MODEL.tools.active_tool_name = navigating ? "CameraOrbitTool" : "ScaleTool"
  $SU_CALLS[:push_tool].clear
  overlay
end

# The cursor sitting still while the box slides out from under it is the whole
# problem: #own_click? goes true on its own, and taking the stack here suspends
# the real Scale tool and its grips mid-orbit.
check "the stack is not taken while the camera is being dragged" do
  spy = ToolSpy.new(true)
  overlay_with(spy, true).onMouseMove(0, 500, 400, MODEL.active_view)
  $SU_CALLS[:push_tool].empty? && !spy.on_push_tool
end

# pop_tool pops whatever is on TOP, and during a navigation that is SketchUp's own
# camera tool -- so the tool must not even be asked, let alone allowed to answer.
check "the tool is not even dispatched during a navigation" do
  spy = ToolSpy.new(false)
  overlay_with(spy, true).onMouseMove(0, 500, 400, MODEL.active_view)
  spy.moves.empty?
end

check "the position is still tracked, so the replay knows where the cursor is" do
  overlay = overlay_with(ToolSpy.new(true), true)
  overlay.onMouseMove(0, 640, 480, MODEL.active_view)
  overlay.mouse == [640, 480]
end

check "with no navigation going on the stack is taken as before" do
  spy = ToolSpy.new(true)
  overlay_with(spy, false).onMouseMove(0, 500, 400, MODEL.active_view)
  $SU_CALLS[:push_tool] == [spy] && spy.on_push_tool
end

check "and the tool is dispatched as before" do
  spy = ToolSpy.new(false)
  overlay_with(spy, false).onMouseMove(0, 500, 400, MODEL.active_view)
  spy.moves == [[500, 400]]
end

puts "\n--- and gets them back without a mouse jiggle ---"

# The pop lives in ScalePPTool#onMouseMove, so without this replay the grips stay
# suspended after an orbit until the user moves the mouse -- and a cursor left
# sitting perfectly still never gets them back at all.
check "releasing the camera replays the decision at the new camera" do
  spy = ToolSpy.new(true)
  overlay = overlay_with(spy, true)
  overlay.onMouseMove(0, 300, 200, MODEL.active_view)
  MODEL.tools.active_tool_name = "ScaleTool"
  at = $SU_TIMERS.size
  overlay.navigation_finished
  $SU_TIMERS[at..-1].to_a.each { |t| t[:proc].call }
  spy.moves == [[300, 200]] && $SU_CALLS[:push_tool] == [spy]
end

# SketchUp is still unwinding its own camera tool off the stack when the callback
# runs; a push landing in the middle of that is the damage being avoided.
check "the replay happens a tick later, never inline" do
  spy = ToolSpy.new(true)
  overlay = overlay_with(spy, true)
  overlay.onMouseMove(0, 300, 200, MODEL.active_view)
  at = $SU_TIMERS.size
  overlay.navigation_finished
  spy.moves.empty? && $SU_CALLS[:push_tool].empty? && $SU_TIMERS.size > at
end

check "a disabled overlay replays nothing" do
  spy = ToolSpy.new(true)
  overlay = overlay_with(spy, true)
  overlay.onMouseMove(0, 300, 200, MODEL.active_view)
  overlay.enabled = false
  at = $SU_TIMERS.size
  overlay.navigation_finished
  $SU_TIMERS.size == at
end

puts "\n--- the grips stay visible while the camera moves ---"

# Measured on SU 2026 from a screen capture, frame by frame, because reasoning
# about it was wrong twice:
#
#   orbit  hides the real grips  -> nothing underneath, paint a substitute
#   pan    hides them TOO        -> same, and a capture proves it: during a pan the
#                                   only thing where a grip should be is the gray
#                                   outline this plugin draws, nothing green inside
#   zoom   never changes tool    -> navigating? false, real grips show through
#
# So the fill follows navigating?, the whole set. A version that narrowed it to
# orbit -- on the report that "pan keeps its grips", which was really this plugin
# painting them -- took the grips away for every pan. These checks pin that shut.
TOOL = PLUG::ScalePPTool
FILL = TOOL::GRIP_FILL

def drawable_tool(mask = 120)
  tool = TOOL.new(nil)
  tool.instance_variable_set(:@active, true)
  tool.instance_variable_set(:@tool_state, 0)
  tool.instance_variable_set(:@bb, Geom::BoundingBox.new)
  tool.instance_variable_set(:@tr_bb, IDENTITY)
  tool.instance_variable_set(:@bb_center, Geom::Point3d.new)
  group = Sketchup::Group.new
  group.definition.behavior.no_scale_mask = mask
  MODEL.selection.clear
  MODEL.selection.add(group)
  tool
end

def grip_draw(during, holds_stack, mask = 120)
  tool = drawable_tool(mask)
  MODEL.tools.stack.clear
  MODEL.tools.push_tool(tool) if holds_stack
  MODEL.tools.active_tool_name = during
  $SU_CALLS[:draw2d].clear
  tool.draw_scale_points(MODEL.active_view)
  $SU_CALLS[:draw2d]
end

def filled(calls)
  calls.count { |mode, _pts, color| mode == GL_POLYGON && color == FILL }
end

def outlined(calls)
  calls.count { |mode, _pts, _c| mode == GL_LINE_LOOP }
end

check "an orbit fills the grips instead of leaving empty boxes" do
  filled(grip_draw("CameraOrbitTool", false)).positive?
end

# The regression this pins, reported as "pan mất highlight grip": narrowing the
# fill to orbit left a pan showing six empty gray boxes, because SketchUp had
# already taken its own grips away.
#
# CameraDollyTool is the name a pan actually arrives under -- measured, see
# NAVIGATION above -- so it is the one that has to be checked, not just the
# CameraPanTool the docs promise.
check "a pan fills them too, exactly like an orbit" do
  ["CameraDollyTool", "CameraPanTool"].all? do |name|
    filled(grip_draw(name, false)).positive?
  end
end

# Not a contradiction of "never bury a real grip": a scroll-wheel zoom is not a tool
# change at all, so navigating? is false here and the real grips show through.
check "the Zoom tools count as navigation as well" do
  ["CameraZoomTool", "CameraZoomWindowTool"].all? do |name|
    filled(grip_draw(name, false)).positive?
  end
end

# The rest of the time the real grips are underneath, and a fill buries them --
# including that same highlight.
check "standing still with the real grips underneath, no fill" do
  filled(grip_draw("ScaleTool", false)).zero?
end

check "holding the stack still fills, as it did before" do
  filled(grip_draw("ScaleTool", true)).positive?
end

# The grey outline follows the same rule as the fill: both appear exactly when
# SketchUp is not drawing the real grips, and neither appears when it is.
#
# The outline used to be drawn always, on the theory that it would sit on top of a
# real green grip and let the green show through. On a flat selection SketchUp offers
# a different set of grips than #bounds_center_lines produces, so outlines were left
# standing where there was no grip -- reported as "choosing XYZ makes the axis grips
# go inactive". See retarget_test.
check "the outline appears exactly where the real grips are missing" do
  substituting = [["CameraOrbitTool", false], ["CameraPanTool", false], ["ScaleTool", true]]
  substituting.all? { |name, stack| outlined(grip_draw(name, stack)).positive? } &&
    outlined(grip_draw("ScaleTool", false)).zero?
end

# The lock is what makes the copy faithful: it takes the corner and edge grips
# away, leaving exactly the six face grips this draws. A single-axis lock leaves
# two, and the fill has to follow that or it invents grips the real tool is not
# showing.
puts "\n--- and so does the yellow bounding box highlight ---"

# The other half of what SketchUp takes away during a navigation: the thick yellow
# box reverts to the plain blue selection colour, which reads as having left the
# Scale tool. Same set of gestures as the grip fill -- it turned out to be one loss,
# not two.
def bounds_drawn?(during, holds_stack = false)
  tool = drawable_tool
  MODEL.tools.stack.clear
  MODEL.tools.push_tool(tool) if holds_stack
  MODEL.tools.active_tool_name = during
  tool.draw_bounds?
end

check "an orbit draws the yellow box back" do
  bounds_drawn?("CameraOrbitTool")
end

# The name a pan really arrives under.
check "a pan draws it back too" do
  bounds_drawn?("CameraDollyTool") && bounds_drawn?("CameraPanTool")
end

check "standing still leaves it to SketchUp, as before" do
  !bounds_drawn?("ScaleTool")
end

check "holding the stack still draws it, as before" do
  bounds_drawn?("ScaleTool", true)
end

# One loss, one condition. They were briefly split, and splitting them is what cost
# pan its grips -- so this pins them together.
check "box and grips are decided by the same condition" do
  NAVIGATION.all? do |name|
    bounds_drawn?(name) && filled(grip_draw(name, false)).positive?
  end
end

check "a single-axis lock fills two grips, not six" do
  six = filled(grip_draw("CameraOrbitTool", false, 120))
  two = filled(grip_draw("CameraOrbitTool", false, 126))
  six.positive? && two * 3 == six
end

puts "\n--- the plugin pushing its own tool is not a departure ---"

# Measured in SketchUp with dev/htu_nav_probe.rb, which is how this was found:
#
#   tool=RubyTool         active=true   ov=4  grips=4    <- plugin holds the stack
#   tool=CameraOrbitTool  active=false  ov=10 grips=0    <- orbit: nothing drawn
#
# The overlay was still being drawn ten times a tick, so this was never a native
# wall. #active? had gone false, because pushing the tool made SketchUp report a
# change to "RubyTool" and the relay answered it with `tool.active = false`.
class OwnToolSpy < OverlaySpy
  def initialize(tool); super(); @tool = tool; end
  def tools; [@tool]; end
end

class ForeignOverlay < OverlaySpy
  def tools; []; end
end

def push_and_report(overlay_for, pushed)
  MODEL.tools.stack.clear
  MODEL.tools.push_tool(pushed)
  MODEL.tools.active_tool_name = "RubyTool"
  with_overlay(overlay_for) do |spy|
    observer.onActiveToolChanged(MODEL.tools, "RubyTool", 21_236)
    return spy.seen
  end
end

check "the plugin's own pushed tool is not relayed as a tool change" do
  tool = ToolSpy.new(false)
  push_and_report(OwnToolSpy.new(tool), tool).empty?
end

# Every extension's tool is called "RubyTool", and switching to one of those is a
# real departure -- which is why this is decided by identity, not by the name.
check "another extension's tool is still a real departure" do
  push_and_report(ForeignOverlay.new, ToolSpy.new(false)) == ["RubyTool"]
end

# The push happens whenever the cursor leaves the grip box, so this was exploding
# the wrapper in the middle of an ordinary scale.
check "the multi-object wrapper survives the plugin taking the stack" do
  group, = wrapped
  tool = ToolSpy.new(false)
  MODEL.tools.stack.clear
  MODEL.tools.push_tool(tool)
  MODEL.tools.active_tool_name = "RubyTool"
  with_overlay(OwnToolSpy.new(tool)) do
    at = $SU_TIMERS.size
    observer.onActiveToolChanged(MODEL.tools, "RubyTool", 21_236)
    $SU_TIMERS[at..-1].to_a.each { |t| t[:proc].call }
  end
  group.valid? && LOCK.temp_group.equal?(group)
end

puts "\n--- the active flag has to actually be set ---"

# #active? is `@active || on the stack`, so while the tool held the stack the
# setter saw "already true" and returned without setting the flag. The tool then
# drew only for as long as it stayed on top, and a camera tool taking that spot
# made it vanish -- grips and dimensions together.
check "setting active while on the stack really sets the flag" do
  tool = TOOL.new(nil)
  MODEL.tools.stack.clear
  MODEL.tools.push_tool(tool)
  tool.active = true
  tool.instance_variable_get(:@active) == true
end

check "so the tool survives a camera tool taking the top of the stack" do
  tool = TOOL.new(nil)
  MODEL.tools.stack.clear
  MODEL.tools.push_tool(tool)
  tool.active = true
  MODEL.tools.stack.clear   # the camera tool is native; ours is no longer on top
  tool.active?
end

# @active starts out nil, and `false == nil` is not the no-op the old comparison
# against #active? happened to make it.
check "a fresh tool is not deactivated by being told it is inactive" do
  tool = TOOL.new(nil)
  MODEL.tools.stack.clear
  $SU_CALLS[:status_text].clear
  tool.active = false
  tool.instance_variable_get(:@active).nil? && !tool.active?
end

puts "\n--- who asks for the replay ---"

class ReplaySpy < OverlaySpy
  attr_reader :replays
  def initialize; super; @replays = 0; end
  def navigation_finished; @replays += 1; end
end

check "coming back from a navigation asks for one replay" do
  with_overlay(ReplaySpy.new) do |spy|
    ob = observer
    ob.onActiveToolChanged(MODEL.tools, "CameraOrbitTool", 21_236)
    ob.onActiveToolChanged(MODEL.tools, "ScaleTool", 21_236)
    spy.replays == 1
  end
end

# An ordinary tool change is not a resume, and replaying there would push the tool
# onto a stack the user just deliberately left.
check "an ordinary tool change asks for none" do
  with_overlay(ReplaySpy.new) do |spy|
    ob = observer
    ob.onActiveToolChanged(MODEL.tools, "ScaleTool", 21_236)
    ob.onActiveToolChanged(MODEL.tools, "SelectionTool", 21_236)
    spy.replays.zero?
  end
end

# Orbit, release, orbit again: each release is its own resume.
check "each release asks again" do
  with_overlay(ReplaySpy.new) do |spy|
    ob = observer
    3.times do
      ob.onActiveToolChanged(MODEL.tools, "CameraOrbitTool", 21_236)
      ob.onActiveToolChanged(MODEL.tools, "ScaleTool", 21_236)
    end
    spy.replays == 3
  end
end

puts "\n--- the cursor, on frames the native tool owns ---"

# ScalePPTool#onSetCursor only gets asked while this tool is on top of the stack, so
# the Scale tool's arrow-with-a-grip-box came straight back wherever the native tool
# had the mouse. The way past that is the mechanism the whole plugin rests on: an
# overlay is handed mouse moves whichever tool is active, and UI.set_cursor is a
# plain global call rather than something only a callback may make.
def cursor_overlay(tool_name)
  overlay = PLUG::ScalePP2Overlay.new
  overlay.enabled = true
  overlay.dim_scale.instance_variable_set(:@active, true)
  MODEL.tools.stack.clear
  MODEL.tools.active_tool_name = tool_name
  $SU_CALLS[:set_cursor].clear
  overlay
end

check "a move relayed by the overlay overwrites the Scale cursor" do
  cursor_overlay("ScaleTool").onMouseMove(0, 500, 400, MODEL.active_view)
  $SU_CALLS[:set_cursor] == [TOOL::PLAIN_CURSOR]
end

# The dedupe in #onMouseMove exists to skip work when the pointer has not moved --
# but the native tool may still have repainted its cursor, so this one call has to
# happen ahead of it.
check "and does so even on a move the overlay otherwise skips" do
  overlay = cursor_overlay("ScaleTool")
  overlay.onMouseMove(0, 500, 400, MODEL.active_view)
  $SU_CALLS[:set_cursor].clear
  overlay.onMouseMove(0, 500, 400, MODEL.active_view)
  $SU_CALLS[:set_cursor] == [TOOL::PLAIN_CURSOR]
end

# Orbit and pan have cursors of their own that mean something, and they are not this
# plugin's to take.
check "but not while the camera is being dragged" do
  cursor_overlay("CameraOrbitTool").onMouseMove(0, 501, 401, MODEL.active_view)
  $SU_CALLS[:set_cursor].empty?
end

# Nor is the Select, Move or Rotate cursor this plugin's business.
check "nor when the Scale tool is not the one running" do
  overlay = cursor_overlay("SelectionTool")
  overlay.dim_scale.instance_variable_set(:@active, false)
  overlay.onMouseMove(0, 502, 402, MODEL.active_view)
  $SU_CALLS[:set_cursor].empty?
end

MODEL.tools.active_tool_name = nil

puts "\n--- result ---"
if $fails.zero?
  puts "PASS — orbit, pan and zoom cost nothing mid-scale"
  exit 0
else
  puts "FAIL — #{$fails} problem(s)"
  exit 1
end
