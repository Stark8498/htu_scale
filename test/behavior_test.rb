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

puts "\n--- making the new mask actually show up ---"

# The bug this section exists for: the first press of a behaviour button did nothing
# visible, and pressing a second button and coming back looked like the fix.
#
# SketchUp's Scale tool does not re-read no_scale_mask while it stays the active
# tool, and send_action("selectScaleTool:") on the tool already running is a no-op --
# so the mask was written and never looked at. The second press only appeared to work
# because it landed while another tool held the stack, which made the re-pick a real
# tool change. Out through Select and back is a real change every time.
check "a button press leaves the Scale tool and comes back, not just send_action" do
  self.stored = ALL
  select(component(ALL))
  $SU_CALLS[:select_tool].clear
  $SU_CALLS[:send_action].clear
  PLUG.set_behavior(XYZ)
  $SU_CALLS[:select_tool].include?(nil) &&
    $SU_CALLS[:send_action].include?("selectScaleTool:")
end

check "and the mask is on the component before the tool is asked to look" do
  self.stored = ALL
  group = component(ALL)
  select(group)
  order = []
  # Held and put back, not removed: `def self.repick_scale_tool` lives on the same
  # singleton class, so remove_method would delete the real one and every check after
  # this would fail on a method that no longer exists.
  original = PLUG.method(:repick_scale_tool)
  PLUG.define_singleton_method(:repick_scale_tool) do
    order << [:repick, mask_of(group)]
    true
  end
  PLUG.set_behavior(XYZ)
  PLUG.define_singleton_method(:repick_scale_tool, original)
  order == [[:repick, XYZ]]
end

# The trip through Select is a tool change as far as the observer can tell, and
# GroupLock unwraps on a tool change. Unwrapping here would explode the wrapper the
# user is still scaling -- and cost two undo steps for one button press.
#
# Driven through GroupLock.tool_changed by hand rather than through set_behavior: the
# shim's #select_tool does not call the observers, so a check written the obvious way
# never reaches the guard at all. Mutation test caught that -- removing the guard left
# every check green.
def wrapped_pair
  a = component(ALL)
  b = component(ALL)
  MODEL.entities.add_entity(a)
  MODEL.entities.add_entity(b)
  select(a, b)
  PLUG::GroupLock.wrap(MODEL)
end

check "a marked round trip does not explode a live wrapper" do
  self.stored = XYZ
  wrapper = wrapped_pair
  $SU_CALLS[:explode].clear
  at = $SU_TIMERS.size
  PLUG::GroupLock.suspend { PLUG::GroupLock.tool_changed("SelectionTool") }
  $SU_TIMERS[at..-1].to_a.each { |t| t[:proc].call }
  ok = $SU_CALLS[:explode].empty? && PLUG::GroupLock.temp_group.equal?(wrapper)
  PLUG::GroupLock.unwrap(MODEL)
  ok
end

# And the marking is done by the one method that makes the round trip, so the two
# halves cannot drift apart.
check "and repick_scale_tool is what marks it" do
  seen = nil
  original = MODEL.method(:select_tool)
  MODEL.define_singleton_method(:select_tool) do |tool|
    seen = PLUG::GroupLock.suspended?
    original.call(tool)
  end
  PLUG.repick_scale_tool
  MODEL.define_singleton_method(:select_tool, original)
  seen == true
end

# The mark must not outlive the trip, or the next real departure keeps the wrapper.
check "and the mark is gone once the trip is over" do
  PLUG.repick_scale_tool
  !PLUG::GroupLock.suspended?
end

# Only the leaving half is excused. A real departure still has to unwrap, or a
# scratch group is left in the user's model.
check "but a real tool change still unwraps" do
  self.stored = XYZ
  a = component(ALL)
  b = component(ALL)
  MODEL.entities.add_entity(a)
  MODEL.entities.add_entity(b)
  select(a, b)
  PLUG::GroupLock.wrap(MODEL)
  at = $SU_TIMERS.size
  PLUG::GroupLock.tool_changed("SelectionTool")
  $SU_TIMERS[at..-1].to_a.each { |t| t[:proc].call }
  PLUG::GroupLock.temp_group.nil?
end

puts "\n--- the buttons themselves ---"

# cmds also carries the dimension toggle, which has nothing to do with scale
# handles and is checked on its own rules.
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

puts "\n--- after a scale drag ---"

# The report this section exists for: pick XYZ, the six grips are right; drag one grip,
# let go, and all twenty-six are back while the toolbar button still reads XYZ.
#
# #apply_behavior only ever ran on a selection CHANGE, and letting go of a grip is not
# one -- the same object stays selected, so nothing ever looked at the mask again.
def tools_observer
  PLUG::ScalePP2Observer::ScalePP2_ToolsOb.new(PLUG::ScalePP2Observer.new)
end

# One drag, through the observer SketchUp actually calls: state 1 when the grip is
# grabbed, 0 when it is let go. The same observer for both halves, because the 1 is
# what arms the 0 -- a fresh one for the release would see a release out of nowhere,
# which is the case the next checks pin as a no-op.
def drag(observer = tools_observer)
  observer.onToolStateChanged(MODEL.tools, "ScaleTool", 21_236, 1)
  at = $SU_TIMERS.size
  observer.onToolStateChanged(MODEL.tools, "ScaleTool", 21_236, 0)
  fired = $SU_TIMERS[at..-1].to_a
  fired.each { |t| t[:proc].call }
  fired
end

# This is the case that was MEASURED, in SketchUp 2026 with dev/htu_mask_probe.rb: on a
# single ComponentInstance the mask reads 120 before the release and 0 after it, with
# the definition's object_id unchanged. SketchUp clears the mask on the definition it
# was set on.
check "a mask lost during the drag is put back on release" do
  self.stored = XYZ
  group = component(XYZ)
  select(group)
  group.definition.behavior.no_scale_mask = ALL   # what the drag left behind
  drag
  mask_of(group) == XYZ
end

# Not measured -- kept because the repair costs nothing extra to make it hold, and one
# probe reading on one SketchUp version on one kind of object does not rule it out. If
# a scale ever hands the object a fresh definition instead of clearing the old one
# (make_unique does exactly that, and this comment once claimed it was the cause), the
# mask was never cleared and the object is simply holding something else now. The
# repair reads `object.definition` fresh, so it cannot tell the two apart -- which is
# what this check is for.
check "and a definition swapped out mid-drag would be repaired too" do
  self.stored = XYZ
  group = component(XYZ)
  select(group)
  group.definition = Sketchup::ComponentDefinition.new   # what make_unique leaves
  lost = mask_of(group)
  drag
  lost == ALL && mask_of(group) == XYZ
end

# Writing the mask is only half the job. SketchUp's Scale tool does not re-read
# no_scale_mask while it stays the active tool -- the same wall #set_behavior hit, and
# the reason a bare send_action is not enough.
check "and the Scale tool is sent out and back so it rereads the mask" do
  self.stored = XYZ
  group = component(ALL)
  select(group)
  $SU_CALLS[:select_tool].clear
  $SU_CALLS[:send_action].clear
  drag
  $SU_CALLS[:select_tool].include?(nil) &&
    $SU_CALLS[:send_action].include?("selectScaleTool:")
end

# Positive control, and the reason the repair is conditional. Every check above passes
# just as well if this fires on every release -- and a tool re-pick after every single
# drag would be felt by the user. It has to be free when nothing drifted.
check "a drag that lost nothing costs no re-pick and no operation" do
  self.stored = XYZ
  select(component(XYZ))
  $SU_CALLS[:select_tool].clear
  $SU_CALLS[:send_action].clear
  $SU_CALLS[:start_operation].clear
  drag
  $SU_CALLS[:select_tool].empty? && $SU_CALLS[:send_action].empty? &&
    $SU_CALLS[:start_operation].empty?
end

# SketchUp reports state 0 for the Scale tool merely becoming active as well. Repairing
# there would mean a re-pick on every activation -- and the re-pick arrives here as
# another state 0, which is a loop that never settles.
check "a release with no drag before it does nothing at all" do
  self.stored = XYZ
  group = component(ALL)
  select(group)
  observer = tools_observer
  at = $SU_TIMERS.size
  observer.onToolStateChanged(MODEL.tools, "ScaleTool", 21_236, 0)
  $SU_TIMERS[at..-1].to_a.each { |t| t[:proc].call }
  mask_of(group) == ALL
end

# The re-pick is itself announced as another state 0, so the repair has to settle: a
# second pass must find nothing left to do rather than buy a second re-pick. Two
# releases here, not because SketchUp sends two, but because that is what the re-pick
# coming back looks like from in here.
check "the repair settles -- a second release buys no second re-pick" do
  self.stored = XYZ
  group = component(ALL)
  select(group)
  observer = tools_observer
  observer.onToolStateChanged(MODEL.tools, "ScaleTool", 21_236, 1)
  $SU_CALLS[:send_action].clear
  2.times do
    at = $SU_TIMERS.size
    observer.onToolStateChanged(MODEL.tools, "ScaleTool", 21_236, 0)
    $SU_TIMERS[at..-1].to_a.each { |t| t[:proc].call }
  end
  mask_of(group) == XYZ &&
    $SU_CALLS[:send_action].count("selectScaleTool:") == 1
end

# And the arming has to be cleared by the release it belongs to. Left set, every later
# state 0 -- the Scale tool merely becoming active is one -- goes looking for something
# to repair. The check above cannot see that: by then the mask is already right, so a
# second repair is free and leaves no trace. This one makes the mask drift again with
# no drag to explain it, which is the case that must be left alone.
check "and the arming does not survive the drag it belongs to" do
  self.stored = XYZ
  group = component(ALL)
  select(group)
  observer = tools_observer
  drag(observer)
  group.definition.behavior.no_scale_mask = ALL
  at = $SU_TIMERS.size
  observer.onToolStateChanged(MODEL.tools, "ScaleTool", 21_236, 0)
  $SU_TIMERS[at..-1].to_a.each { |t| t[:proc].call }
  mask_of(group) == ALL
end

# Same rule as everywhere else the model gets edited from an observer callback, and it
# matters more here than most: this one lands immediately after the Scale tool's own
# operation commits.
check "nothing is repaired inline, before the tick" do
  self.stored = XYZ
  group = component(ALL)
  select(group)
  observer = tools_observer
  observer.onToolStateChanged(MODEL.tools, "ScaleTool", 21_236, 1)
  at = $SU_TIMERS.size
  observer.onToolStateChanged(MODEL.tools, "ScaleTool", 21_236, 0)
  mask_of(group) == ALL && $SU_TIMERS.size > at
end

# A selection of several objects has no definition of its own to carry a mask, so for
# it the repair is the wrapper, not the write: masks written onto the objects leave the
# union cage ungoverned, which is the whole reason GroupLock exists. A wrapper can go
# missing mid-drag -- an undo past the wrap puts the objects back loose.
check "a multi-object selection is re-wrapped, not written to one by one" do
  self.stored = XYZ
  a = component(ALL)
  b = component(ALL)
  MODEL.entities.add_entity(a)
  MODEL.entities.add_entity(b)
  select(a, b)
  drag
  wrapper = PLUG::GroupLock.temp_group
  ok = !wrapper.nil? && mask_of(wrapper) == XYZ && MODEL.selection.to_a == [wrapper]
  PLUG::GroupLock.unwrap(MODEL)
  ok
end

puts "\n--- result ---"
if $fails.zero?
  puts "PASS — the scale mode is remembered and follows the selection"
  exit 0
else
  puts "FAIL — #{$fails} problem(s)"
  exit 1
end
