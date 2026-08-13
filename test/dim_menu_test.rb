# frozen_string_literal: true

# The dimension context menu is the deliverable here, so its shape is pinned to
# the agreed mockup:
#
#   45 mm / 200 mm / 400 mm
#   ---------
#   Referenced Dimensions    (grayed, only when the model has other sizes)
#   900 mm (in model)
#   ---------
#   Open list...
#   Text size  >
#
# With nothing saved and nothing referenced, only the last two -- and no divider
# above them, since there is no block left for it to divide.
#
# DimMenu is handed a menu object and only calls add_item / add_submenu /
# add_separator / set_validation_proc on it, so a recorder stands in for
# Sketchup::Menu and the whole structure can be asserted without SketchUp.

require_relative "su_shim"
require File.expand_path("../htu_scaleplus.rb", __dir__)
$SU_CALLS[:register_extension].first.load_extension

PLUG = TRINH_VAN_PHUC::HTU_ScalePlus
FAV = PLUG::DimFavorites
MENU = PLUG::DimMenu

class RecordingMenu
  attr_reader :entries, :submenus, :blocks, :validations

  def initialize
    @entries = []
    @submenus = {}
    @blocks = {}
    @validations = {}
  end

  def add_item(label, &block)
    @entries << label
    @blocks[label] = block
    label
  end

  def add_separator
    @entries << :separator
    true
  end

  def add_submenu(name)
    @entries << "#{name} >"
    @submenus[name] = RecordingMenu.new
  end

  def set_validation_proc(item, &block)
    @validations[item] = block
    block
  end

  def labels
    @entries.reject { |e| e == :separator }
  end
end

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

# Stands in for ScalePPTool: the menu only ever calls back into it, so what
# matters is that it is called with the right arguments.
class ToolSpy
  attr_reader :calls

  def initialize
    @calls = []
  end

  def method_missing(name, *args)
    @calls << [name, *args]
    nil
  end

  def respond_to_missing?(*)
    true
  end
end

TOOL_SPY = ToolSpy.new

# The saved list is a machine-wide preference, so it carries between checks
# unless it is put back to "fresh install" first.
def reset_favorites!
  PLUG.settings = PLUG::Settings.new("HTU ScalePlus")
  Sketchup.defaults.delete(["HTU ScalePlus", FAV::SHARED_KEY.to_s])
  FAV::AXES.each { |axis| Sketchup.defaults.delete(["HTU ScalePlus", FAV.attribute(axis)]) }
end

def build(values, length: 1.0)
  reset_favorites!
  group = Sketchup::Group.new
  unless values.empty?
    good, = FAV.parse(values.join(","))
    FAV.add(group, "lenx", good)
  end
  menu = RecordingMenu.new
  MENU.build(menu, TOOL_SPY, group, "lenx", length)
  [menu, group]
end

puts "--- populated list ---"
menu, group = build(%w[45 200 400])

check "the saved sizes are the top of the menu, with no label over them" do
  menu.entries[0, 3].all? { |e| e.is_a?(String) } &&
    !menu.labels.include?("Favorite Dimensions")
end

check "a separator divides the sizes from the actions" do
  menu.entries[3] == :separator
end

check "then Open list..., Text size >" do
  menu.entries[4, 2] == ["Open list...", "Text size >"]
end

check "nothing else is on the menu" do
  menu.entries.size == 6
end

# Removed on request, 2026-08-13, and pinned so it cannot drift back in: it opened
# the old Vue dimension manager, and "Open list..." right above it does that job in
# a window built for it. Consequence worth knowing rather than hiding: DimsUI now
# has no entry point at all, so those 11 files ship unreachable and observer.rb's
# refresh calls find no dialog to refresh.
check "Show Manager is not offered -- Open list... is the one way in" do
  !menu.labels.include?("Show Manager") && menu.labels.include?("Open list...")
end

check "every size carries a validation proc for the checkmark" do
  menu.entries[0, 3].all? { |label| menu.validations.key?(label) }
end

# The only check that clicking a size does anything used to be the one on the
# half/double suggestion, which is gone -- so deleting it would have taken the
# whole apply path with it. Moved onto a saved size, which is the path that
# matters anyway.
check "picking a saved size resizes to it" do
  m, = build(%w[45 200 400])
  label = m.entries[1]
  block = m.blocks[label]
  next false unless block

  TOOL_SPY.calls.clear
  block.call
  TOOL_SPY.calls.last == [:apply_dim_value, "lenx", FAV.list(nil, "lenx")[1]]
end

check "the size matching the current length is checked" do
  current = FAV.list(group, "lenx")[1]
  m = RecordingMenu.new
  MENU.build(m, nil, group, "lenx", current)
  checked = m.entries[0, 3].select do |label|
    proc = m.validations[label]
    proc && proc.call == MF_CHECKED
  end
  checked.size == 1
end

puts "\n--- one line, not three ---"

# Add... and the Del submenu are gone. A native menu closes on the first pick,
# so every value added or deleted cost a fresh trip through it; the window does
# all three jobs and stays open.
check "no Add..., no Del submenu" do
  !menu.labels.include?("Add...") && !menu.submenus.key?("Del") &&
    menu.labels.none? { |l| l.start_with?("Del") }
end

check "Open list... opens the window on the right object and axis" do
  m, g = build(%w[45 200 400])
  block = m.blocks["Open list..."]
  next false unless block

  PLUG::DimAddDialog.close
  before = $SU_TIMERS.size
  block.call
  $SU_TIMERS[before..-1].to_a.each { |t| t[:proc].call }
  dialog = PLUG::DimAddDialog.dialog
  dialog.visible? && PLUG::DimAddDialog.object.equal?(g) && PLUG::DimAddDialog.axis == "lenx"
end

check "it is offered with an empty list too -- that is how the first value gets in" do
  m, = build([])
  m.labels.include?("Open list...")
end

puts "\n--- Text size submenu ---"

check "offers Small, Medium, Large" do
  menu.submenus["Text size"].labels == %w[Small Medium Large]
end

check "the active size is checked" do
  sub = menu.submenus["Text size"]
  sub.blocks["Large"].call
  sub.validations["Large"].call == MF_CHECKED && sub.validations["Small"].call == MF_ENABLED
end

puts "\n--- empty list: a fresh install, which is what everyone sees first ---"
empty, = build([], length: 450.0)

# The half and double suggestions -- "225 (x0.5)", "900 (x2.0)" -- were removed on
# request, 2026-08-13, and this is the one removal with a price attached: they were
# the ONLY thing the menu offered before anything was saved, so a first right-click
# now has no size on it. That was put to the user and chosen with the cost stated.
check "no size is offered until one is saved" do
  empty.labels.none? { |l| l =~ /\(x[\d.]+\)/ }
end

check "just the way to add one, and Text size" do
  empty.entries == ["Open list...", "Text size >"]
end

# A separator divides. With no block above it there is nothing to divide, and a
# menu whose first row is a horizontal rule looks like an item that failed to draw.
check "and no divider hanging at the top with nothing above it" do
  empty.entries.first != :separator
end

# The label used to be built by dividing by the length, so zero raised. Nothing
# divides by it any more, but degenerate bounds are real -- a flat selection has
# one -- so the path stays covered.
check "a zero-length dimension is not a crash" do
  m, = build([], length: 0.0)
  m.entries == ["Open list...", "Text size >"]
end

# The callback runs through defer, which touches IS_WIN and UI.start_timer, so a
# NameError on that path fails the build rather than waiting for a user to click.
check "no modal box is put up on the way to the window" do
  block = empty.blocks["Open list..."]
  next false unless block

  PLUG::DimAddDialog.close
  $SU_CALLS[:messagebox].clear
  before = $SU_TIMERS.size
  block.call
  $SU_TIMERS[before..-1].to_a.each { |t| t[:proc].call }
  $SU_CALLS[:messagebox].empty? && PLUG::DimAddDialog.dialog.visible?
end

puts "\n--- no single object selected ---"
none = RecordingMenu.new
MENU.build(none, nil, nil, "lenx", 1.0)

check "only Text size, since there is nothing to apply a size to" do
  none.entries == ["Text size >"]
end

puts "\n--- Referenced Dimensions, and why it is not here ---"

# It answered "make this one the same as that one over there" without going to
# measure it: every instance of every definition sharing this one's DC name walked,
# and its length along the clicked axis offered, labelled "(in model)".
#
# Removed on request, 2026-08-13, with ScalePPTool#referenced_dims and
# #same_dc_definition. It read well and behaved badly: the sizes it found were
# whatever the neighbouring instances had been dragged to, so the block filled with
# values like "~ 592" -- the tilde being SketchUp saying the number does not round
# cleanly at the model's precision. Nobody picks 592 on purpose, and the saved list
# is the curated answer to the same question.
#
# The fixture stays, because the checks below are only worth anything if they are
# run against the exact model that used to produce the block: two instances of ONE
# definition at two different sizes. Nothing appearing on an empty model would prove
# nothing. This is also why the shim learned #instances, #parent and a real
# InstancePath#transformation -- kept, since a more faithful shim is not a cost.
MODEL = Sketchup.active_model

def two_instances(second_scale)
  MODEL.entities.to_a.each { |e| MODEL.entities.remove_entity(e) }
  definition = Sketchup::ComponentDefinition.new
  definition.bounds.add(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(450, 300, 200))
  here = Sketchup::ComponentInstance.new
  here.definition = definition
  there = Sketchup::ComponentInstance.new
  there.definition = definition
  there.transformation = Geom::Transformation.scaling(second_scale, 1, 1)
  MODEL.entities.add_entity(here)
  MODEL.entities.add_entity(there)
  MODEL.selection.clear
  MODEL.selection.add(here)
  [PLUG::ScalePPTool.new(nil), here]
end

# The fixture is doing real work, so it gets its own check: if two_instances stopped
# building a second instance at a second size, every check below would pass on an
# empty model and mean nothing at all.
check "the fixture really does build two instances at two sizes" do
  _, here = two_instances(2)
  others = here.definition.instances
  others.size == 2 &&
    others.map { |i| i.transformation.xaxis.length.round(4) }.sort == [1.0, 2.0]
end

check "the block does not appear, on the model that used to produce it" do
  tool, = two_instances(2)
  reset_favorites!
  m = RecordingMenu.new
  MENU.build(m, tool, MODEL.selection[0], "lenx", 450.0)
  m.entries == ["Open list...", "Text size >"]
end

check "no size is offered from the geometry, on any axis" do
  tool, = two_instances(2)
  reset_favorites!
  ["lenx", "leny", "lenz"].all? do |axis|
    m = RecordingMenu.new
    MENU.build(m, tool, MODEL.selection[0], axis, 450.0)
    m.labels.none? { |l| l.include?("in model") } &&
      !m.labels.include?("Referenced Dimensions")
  end
end

# And with sizes saved, the menu is the saved block and nothing more -- no second
# list grafted underneath it.
check "with sizes saved, only the saved ones are listed" do
  tool, here = two_instances(2)
  reset_favorites!
  good, = FAV.parse("45")
  FAV.add(here, "lenx", good)
  m = RecordingMenu.new
  MENU.build(m, tool, here, "lenx", 450.0)
  m.entries.size == 4 && m.entries[1] == :separator &&
    m.labels.none? { |l| l.include?("in model") }
end

# The machinery, not just the menu. A block that cannot be reached but whose code is
# still there is one call away from coming back, and #add_heading only existed to
# label it.
check "referenced_dims and same_dc_definition are gone from the tool" do
  tool, = two_instances(2)
  !tool.respond_to?(:referenced_dims) && !tool.respond_to?(:same_dc_definition)
end

check "and the menu has no code left to build the block with" do
  !MENU.respond_to?(:add_referenced_items) && !MENU.respond_to?(:add_heading)
end

puts "\n--- result ---"
if $fails.zero?
  puts "PASS — context menu matches the agreed structure"
  exit 0
else
  puts "FAIL — #{$fails} problem(s)"
  exit 1
end
