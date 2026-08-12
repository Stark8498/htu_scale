# frozen_string_literal: true

# The six toolbar buttons pick which scale handles SketchUp shows. The choice is
# a machine-wide preference and gets put on whatever is selected next, so it
# outlives the component, the file and the SketchUp session -- which is the whole
# point: a new file should open in the mode last chosen, not back on all handles.

require_relative "su_shim"
require File.expand_path("../htu_scaleplus.rb", __dir__)
$SU_CALLS[:register_extension].first.load_extension

PLUG = TRINH_VAN_PHUC::HTU_ScalePlus
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

def select(*objects)
  MODEL.selection.clear
  MODEL.selection.add(*objects) unless objects.empty?
  MODEL.selection
end

def component(mask = ALL)
  group = Sketchup::Group.new
  group.definition.behavior.no_scale_mask = mask
  group
end

def mask_of(object)
  object.definition.behavior.no_scale_mask?
end

puts "--- the remembered mode ---"

check "nothing chosen yet means all handles" do
  Sketchup.defaults.delete(["htu_behavior", "state"])
  PLUG.behavior_state == ALL
end

check "a button press is remembered" do
  self.stored = XYZ
  PLUG.behavior_state == XYZ
end

check "pressing the button that is already on turns it off" do
  self.stored = XYZ
  group = component(XYZ)
  select(group)
  PLUG.set_behavior(XYZ)
  PLUG.behavior_state == ALL && mask_of(group) == ALL
end

check "pressing a different button switches mode rather than turning off" do
  self.stored = XYZ
  group = component(XYZ)
  select(group)
  PLUG.set_behavior(X_ONLY)
  PLUG.behavior_state == X_ONLY && mask_of(group) == X_ONLY
end

check "the mode can be set with nothing selected at all" do
  self.stored = ALL
  select
  PLUG.set_behavior(XYZ)
  PLUG.behavior_state == XYZ
end

check "and with several things selected" do
  self.stored = ALL
  a = component(ALL)
  b = component(ALL)
  select(a, b)
  PLUG.set_behavior(XYZ)
  PLUG.behavior_state == XYZ && mask_of(a) == XYZ && mask_of(b) == XYZ
end

puts "\n--- the buttons themselves ---"

# cmds also carries the show-dimensions toggle, which has nothing to do with
# scale handles and is checked on its own rule.
def scale_cmds
  PLUG.cmds.reject { |cmd, _| cmd.equal?(PLUG.cmd_dim) }
end

# They used to gray out unless exactly one component was selected, which was the
# right question while the mask belonged to a component and the wrong one now.
check "never grayed, whatever is or is not selected" do
  select
  states = PLUG.cmds.keys.map { |cmd| cmd.get_validation_proc.call }
  states.none? { |s| s == MF_GRAYED }
end

check "the tick follows the remembered mode" do
  self.stored = XYZ
  select
  checked = scale_cmds.select { |cmd, _| cmd.get_validation_proc.call == MF_CHECKED }
  checked.size == 1 && checked.values.first == XYZ
end

check "the tick ignores what the selected component happens to hold" do
  self.stored = XYZ
  select(component(X_ONLY))
  checked = scale_cmds.select { |cmd, _| cmd.get_validation_proc.call == MF_CHECKED }
  checked.values == [XYZ]
end

puts "\n--- applied to whatever is selected next ---"

check "a component picked up in the locked mode gets locked" do
  self.stored = XYZ
  group = component(ALL)
  PLUG.apply_behavior(select(group))
  mask_of(group) == XYZ
end

check "turning the lock off frees the next component too" do
  self.stored = ALL
  group = component(XYZ)
  PLUG.apply_behavior(select(group))
  mask_of(group) == ALL
end

check "every component in a multiple selection, not just the first" do
  self.stored = XYZ
  a = component(ALL)
  b = component(ALL)
  PLUG.apply_behavior(select(a, b))
  mask_of(a) == XYZ && mask_of(b) == XYZ
end

check "raw geometry in the selection is skipped, not crashed on" do
  self.stored = XYZ
  group = component(ALL)
  PLUG.apply_behavior(select(group, Sketchup::Face.new))
  mask_of(group) == XYZ
end

# This runs on every single selection change, so a write that is not needed
# would dirty the file and push an undo step each time the user clicked
# something -- for no visible change at all.
check "a component already in the right mode is not written to" do
  self.stored = XYZ
  group = component(XYZ)
  $SU_CALLS[:start_operation].clear
  changed = PLUG.apply_behavior(select(group))
  changed.zero? && $SU_CALLS[:start_operation].empty?
end

check "one operation for the whole selection, not one per component" do
  self.stored = XYZ
  objects = Array.new(3) { component(ALL) }
  $SU_CALLS[:start_operation].clear
  PLUG.apply_behavior(select(*objects))
  $SU_CALLS[:start_operation].size == 1
end

check "an empty selection is a no-op" do
  self.stored = XYZ
  $SU_CALLS[:start_operation].clear
  PLUG.apply_behavior(select) && $SU_CALLS[:start_operation].empty?
end

puts "\n--- through the selection observer ---"

# Deferred by a tick, because this edits the model and SketchUp makes no promise
# about edits made from inside an observer callback.
check "a selection change schedules the mode to be applied" do
  self.stored = XYZ
  group = component(ALL)
  observer = PLUG::ScalePP2Observer.new
  at = $SU_TIMERS.size
  observer.selection_changed(select(group))
  fired = $SU_TIMERS[at..-1].to_a
  fired.each { |t| t[:proc].call }
  !fired.empty? && mask_of(group) == XYZ
end

check "nothing is applied inline, before that tick" do
  self.stored = XYZ
  group = component(ALL)
  observer = PLUG::ScalePP2Observer.new
  observer.selection_changed(select(group))
  mask_of(group) == ALL
end

puts "\n--- result ---"
if $fails.zero?
  puts "PASS — the scale mode is remembered and follows the selection"
  exit 0
else
  puts "FAIL — #{$fails} problem(s)"
  exit 1
end
