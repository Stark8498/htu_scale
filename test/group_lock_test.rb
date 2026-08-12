# frozen_string_literal: true

# The axis lock, for a selection of more than one object.
#
# no_scale_mask belongs to a definition, so it can only speak for one object.
# Select two and SketchUp scales the union of their bounding boxes -- a cage no
# definition owns, so every handle comes back and the mode the user picked looks
# broken. GroupLock wraps that selection in a group, puts the remembered mask on
# the group, and takes the group out again on the way out of the Scale tool.
#
# What is being guarded here is mostly the taking-out. A wrapper group is scratch
# that lives in the user's model, so every path that can leave one behind is a
# path that can corrupt their file.

require_relative "su_shim"
require File.expand_path("../htu_scaleplus.rb", __dir__)
$SU_CALLS[:register_extension].first.load_extension

PLUG = TRINH_VAN_PHUC::HTU_ScalePlus
LOCK = PLUG::GroupLock
MODEL = Sketchup.active_model

ALL = 0
XYZ = 120
X_ONLY = 126

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

def stored=(state)
  Sketchup.write_default("htu_behavior", "state", state)
end

# Every test starts from a model with nothing in it and nothing wrapped, because
# a wrapper leaking from the previous test is exactly the bug being hunted.
def reset!(state = XYZ)
  self.stored = state
  MODEL.entities.to_a.each { |e| MODEL.entities.remove_entity(e) }
  MODEL.selection.clear
  LOCK.instance_variable_set(:@temp_group, nil)
  LOCK.instance_variable_set(:@previous_selection, [])
  $SU_CALLS[:start_operation].clear
  $SU_CALLS[:send_action].clear
  $SU_CALLS[:add_group].clear
  $SU_CALLS[:explode].clear
end

# Groups placed in the model the way SketchUp would have them: in the active
# context, and therefore reachable by the sweep.
def place(n = 2, mask = ALL)
  Array.new(n) do
    group = Sketchup::Group.new
    group.definition.behavior.no_scale_mask = mask
    MODEL.entities.add_entity(group)
    group
  end
end

def select(*objects)
  MODEL.selection.clear
  MODEL.selection.add(*objects) unless objects.empty?
  MODEL.selection
end

def wrappers
  MODEL.entities.select { |e| LOCK.temp?(e) }
end

def mask_of(object)
  object.definition.behavior.no_scale_mask?
end

puts "--- when the selection gets wrapped ---"

check "two locked objects are wrapped in one group" do
  reset!(XYZ)
  select(*place(2))
  group = LOCK.wrap(MODEL)
  group && wrappers == [group] && MODEL.selection.to_a == [group]
end

check "the wrapper carries the remembered mask, not a hardcoded one" do
  reset!(X_ONLY)
  select(*place(2))
  mask_of(LOCK.wrap(MODEL)) == X_ONLY
end

check "the objects move into the wrapper, they are not copied" do
  reset!(XYZ)
  objects = place(2)
  select(*objects)
  group = LOCK.wrap(MODEL)
  group.entities.to_a == objects && MODEL.entities.to_a == [group]
end

check "the wrapper is stamped, so a stray one can be found later" do
  reset!(XYZ)
  select(*place(2))
  LOCK.wrap(MODEL).get_attribute(LOCK::TEMP_DICT, LOCK::TEMP_KEY) == true
end

check "one operation for the wrap, not one per object" do
  reset!(XYZ)
  select(*place(3))
  LOCK.wrap(MODEL)
  $SU_CALLS[:start_operation].size == 1
end

# main.rb#set_behavior already re-picks the tool for the same reason: SketchUp's
# Scale tool read its handles off the old selection and will not necessarily
# notice this one.
check "the Scale tool is re-picked so it rereads the new selection" do
  reset!(XYZ)
  select(*place(2))
  LOCK.wrap(MODEL)
  $SU_CALLS[:send_action].include?("selectScaleTool:")
end

puts "\n--- when it must keep its hands off ---"

# The whole point of the wrapper is to carry a mask. With no lock on there is
# nothing to carry, and grouping the user's objects would be pure damage.
check "no lock on means no wrapper" do
  reset!(ALL)
  select(*place(2))
  LOCK.wrap(MODEL).nil? && wrappers.empty?
end

# One object already resolves to a definition of its own, so the mask on it
# already governs the handles. Wrapping would be work for nothing.
check "a single object is left alone" do
  reset!(XYZ)
  select(*place(1))
  LOCK.wrap(MODEL).nil? && wrappers.empty?
end

check "an empty selection is left alone" do
  reset!(XYZ)
  select
  LOCK.wrap(MODEL).nil? && wrappers.empty?
end

# Faces and edges cannot be pulled out of their context and pushed back: edges
# reweld against whatever they now touch, and the user gets a different model
# than the one they scaled. Mixed selections keep all 27 handles instead.
check "raw geometry in the selection blocks the wrap entirely" do
  reset!(XYZ)
  objects = place(2)
  face = Sketchup::Face.new
  MODEL.entities.add_entity(face)
  select(*objects, face)
  LOCK.wrap(MODEL).nil? && wrappers.empty? && MODEL.entities.include?(face)
end

# The re-pick above fires onActiveToolChanged, which comes straight back into
# wrap. Without the guard this is an endless loop that groups the model into a
# stack of wrappers.
check "wrapping twice does not nest a second wrapper" do
  reset!(XYZ)
  select(*place(2))
  first = LOCK.wrap(MODEL)
  second = LOCK.wrap(MODEL)
  second.nil? && wrappers == [first]
end

puts "\n--- when it comes back out ---"

check "leaving Scale explodes the wrapper" do
  reset!(XYZ)
  objects = place(2)
  select(*objects)
  LOCK.wrap(MODEL)
  LOCK.unwrap(MODEL)
  wrappers.empty? && MODEL.entities.to_a == objects
end

check "the original selection is handed back to the user" do
  reset!(XYZ)
  objects = place(2)
  select(*objects)
  LOCK.wrap(MODEL)
  LOCK.unwrap(MODEL)
  MODEL.selection.to_a == objects
end

# The mask was on the wrapper, and the wrapper is gone. Each object has to end
# up carrying it itself, or the next scale of one of them is unlocked.
check "the mask lands on each object once the wrapper is gone" do
  reset!(X_ONLY)
  objects = place(2)
  select(*objects)
  LOCK.wrap(MODEL)
  LOCK.unwrap(MODEL)
  objects.all? { |o| mask_of(o) == X_ONLY }
end

check "unwrapping with nothing wrapped is a quiet no-op" do
  reset!(XYZ)
  place(2)
  LOCK.unwrap(MODEL).nil? && $SU_CALLS[:start_operation].empty?
end

check "unwrapping twice does not explode anything a second time" do
  reset!(XYZ)
  select(*place(2))
  LOCK.wrap(MODEL)
  LOCK.unwrap(MODEL)
  LOCK.unwrap(MODEL)
  $SU_CALLS[:explode].size == 1
end

puts "\n--- strays ---"

# Undo is why the stamp exists. The wrap is its own undo step, so undoing past
# the scale can put the wrapper back with nothing left holding a reference to it.
# The next wrap has to find it, or the model accumulates them.
check "a stray wrapper from a forgotten session is swept on the next wrap" do
  reset!(XYZ)
  stray = LOCK.wrap(MODEL) if select(*place(2))
  LOCK.instance_variable_set(:@temp_group, nil)   # what an undo leaves behind
  LOCK.instance_variable_set(:@previous_selection, [])
  select(*place(2))
  LOCK.wrap(MODEL)
  !stray.valid? && wrappers.size == 1
end

# The live wrapper carries the same stamp and sits in the same context as a
# stray, so only identity tells them apart. Sweeping it away would delete the
# group the user is dragging handles on and leave the selection holding a corpse.
check "the sweep never touches the wrapper that is currently live" do
  reset!(XYZ)
  select(*place(2))
  group = LOCK.wrap(MODEL)
  LOCK.sweep(MODEL)
  group.valid? && wrappers == [group] && MODEL.selection.to_a == [group]
end

check "the sweep leaves ordinary groups completely alone" do
  reset!(XYZ)
  objects = place(3)
  LOCK.sweep(MODEL)
  MODEL.entities.to_a == objects && objects.all?(&:valid?)
end

check "a sweep with nothing to sweep opens no operation" do
  reset!(XYZ)
  place(2)
  LOCK.sweep(MODEL).zero? && $SU_CALLS[:start_operation].empty?
end

puts "\n--- through the observers ---"

def tools_observer
  PLUG::ScalePP2Observer::ScalePP2_ToolsOb.new(PLUG::ScalePP2Observer.new)
end

def fire_tool(name)
  at = $SU_TIMERS.size
  tools_observer.onActiveToolChanged(MODEL.tools, name, 21_236)
  fired = $SU_TIMERS[at..-1].to_a
  fired.each { |t| t[:proc].call }
  fired
end

check "picking the Scale tool wraps, one tick later" do
  reset!(XYZ)
  select(*place(2))
  fired = fire_tool("ScaleTool")
  !fired.empty? && wrappers.size == 1
end

# Same rule as apply_behavior: this edits the model, and an edit made inside an
# observer callback can land in the middle of the operation that caused it.
check "nothing is wrapped inline, before that tick" do
  reset!(XYZ)
  select(*place(2))
  at = $SU_TIMERS.size
  tools_observer.onActiveToolChanged(MODEL.tools, "ScaleTool", 21_236)
  wrappers.empty? && $SU_TIMERS.size > at
end

check "picking any other tool unwraps" do
  reset!(XYZ)
  objects = place(2)
  select(*objects)
  LOCK.wrap(MODEL)
  fire_tool("SelectionTool")
  wrappers.empty? && MODEL.entities.to_a == objects
end

# A middle-mouse orbit in the middle of a scale is a tool change like any other.
# Unwrapping there would drop the handles the user is dragging.
check "a middle-mouse orbit mid-scale does not unwrap" do
  reset!(XYZ)
  select(*place(2))
  group = LOCK.wrap(MODEL)
  fire_tool("CameraOrbitTool")
  wrappers == [group] && group.valid?
end

# The one cleanup that is not a tool change, and the one that protects the file.
check "saving unwraps first, so no .skp is ever written with one inside" do
  reset!(XYZ)
  objects = place(2)
  select(*objects)
  LOCK.wrap(MODEL)
  PLUG::ScalePP2Observer::ScalePPModelOb.new.onPreSaveModel(MODEL)
  wrappers.empty? && MODEL.entities.to_a == objects
end

check "the model observer is actually attached to the model" do
  $SU_CALLS[:model_observer].clear
  PLUG::ScalePP2Observer.new
  $SU_CALLS[:model_observer].any? { |o| o.is_a?(PLUG::ScalePP2Observer::ScalePPModelOb) }
end

puts "\n--- result ---"
if $fails.zero?
  puts "PASS — a multi-object selection scales locked, and the wrapper never survives"
  exit 0
else
  puts "FAIL — #{$fails} problem(s)"
  exit 1
end
