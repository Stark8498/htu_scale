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

# The two suggestions ARE the menu on a fresh install. Dropping them left
# "Open list..." and Text size, so a right-click offered no size to pick at all
# until the user had gone and saved one -- and nothing on the menu said so.
check "half and double are offered instead of an empty block" do
  empty.entries[0, 2] == ["225.0 (x0.5)", "900.0 (x2.0)"]
end

check "each one carries its factor, so which is which is readable" do
  empty.labels.count { |l| l =~ /\(x(0\.5|2\.0)\)/ } == 2
end

check "picking one resizes to that length" do
  m, = build([], length: 450.0)
  block = m.blocks["900.0 (x2.0)"]
  next false unless block

  TOOL_SPY.calls.clear
  block.call
  TOOL_SPY.calls.last == [:apply_dim_value, "lenx", 900.0]
end

check "then the same two actions" do
  empty.entries[2, 3] == [:separator, "Open list...", "Text size >"]
end

# A dimension of zero would suggest 0 and 0, and dividing by it to build the label
# raises. Degenerate bounds are real: a flat selection has one.
check "a zero-length dimension suggests nothing rather than raising" do
  m, = build([], length: 0.0)
  m.entries.first == :separator
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

puts "\n--- sizes the same component is already built at ---"

# "Referenced Dimensions", another block dropped while this file was written. It
# is the answer to "make this one the same as that one over there" without going
# to measure it: every instance of every definition sharing this one's DC name is
# walked and its length along the clicked axis offered, labelled "(in model)".
#
# Two instances of ONE definition is the whole point, so the shim had to learn
# #instances, #parent and a real InstancePath#transformation first -- with the old
# stub every instance measured the same and the block could never appear.
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

check "the other instance's length is found" do
  tool, = two_instances(2)
  tool.referenced_dims("lenx").map(&:to_f).sort == [450.0, 900.0]
end

check "the axis clicked is the axis measured" do
  tool, = two_instances(2)
  tool.referenced_dims("leny").map(&:to_f).uniq == [300.0]
end

check "an unknown axis name is not a crash" do
  tool, = two_instances(2)
  tool.referenced_dims("lenq").empty?
end

check "the block appears with its grayed heading" do
  tool, = two_instances(2)
  reset_favorites!
  m = RecordingMenu.new
  MENU.build(m, tool, MODEL.selection[0], "lenx", 450.0)
  at = m.entries.index("Referenced Dimensions")
  at && m.validations["Referenced Dimensions"].call == MF_GRAYED &&
    m.entries[at + 1] == "900.0 (in model)"
end

# Offering the size it already is would be a menu entry that does nothing.
check "the current length is not offered back" do
  tool, = two_instances(2)
  reset_favorites!
  m = RecordingMenu.new
  MENU.build(m, tool, MODEL.selection[0], "lenx", 450.0)
  m.labels.none? { |l| l.start_with?("450") && l.include?("in model") }
end

# Nor is one that is already in the saved list right above it.
#
# Saved by taking the length back off referenced_dims rather than by parsing
# "900": DimFavorites.parse reads a bare number in MODEL units, so "900" comes
# back as 900 mm = 35.4", which could never have matched the 900" the geometry is.
# The first version of this check tested that unit slip and not the dedup.
check "a size already saved is not listed twice" do
  tool, here = two_instances(2)
  reset_favorites!
  other = tool.referenced_dims("lenx").find { |value| value.to_f == 900.0 }
  FAV.add(here, "lenx", [other])
  m = RecordingMenu.new
  MENU.build(m, tool, here, "lenx", 450.0)
  m.labels.none? { |l| l.include?("in model") }
end

check "one instance on its own gets no block at all" do
  tool, = two_instances(1)
  reset_favorites!
  m = RecordingMenu.new
  MENU.build(m, tool, MODEL.selection[0], "lenx", 450.0)
  !m.labels.include?("Referenced Dimensions")
end

puts "\n--- result ---"
if $fails.zero?
  puts "PASS — context menu matches the agreed structure"
  exit 0
else
  puts "FAIL — #{$fails} problem(s)"
  exit 1
end
