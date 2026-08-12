# frozen_string_literal: true

# The dimension context menu is the deliverable here, so its shape is pinned to
# the agreed mockup:
#
#   45 mm / 200 mm / 400 mm
#   ---------
#   Add...
#   Del        >
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

check "three saved sizes come first" do
  menu.entries[0, 3].all? { |e| e.is_a?(String) } && menu.entries[0, 3].size == 3
end

check "a separator divides the sizes from the actions" do
  menu.entries[3] == :separator
end

check "then Open list... and Text size >, nothing between" do
  menu.entries[4, 2] == ["Open list...", "Text size >"]
end

check "nothing else is on the menu" do
  menu.entries.size == 6
end

check "Show Manager is gone" do
  !menu.labels.include?("Show Manager")
end

check "Referenced Dimensions is gone" do
  menu.labels.none? { |l| l.include?("Referenced") || l.include?("Favorite") }
end

check "every size carries a validation proc for the checkmark" do
  menu.entries[0, 3].all? { |label| menu.validations.key?(label) }
end

check "the size matching the current length is checked" do
  current = FAV.list(group, "lenx")[1]
  m = RecordingMenu.new
  MENU.build(m, nil, group, "lenx", current)
  checked = m.entries[0, 3].select { |label| m.validations[label].call == MF_CHECKED }
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
  PLUG::DimAddDialog.close
  before = $SU_TIMERS.size
  m.blocks["Open list..."].call
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

puts "\n--- empty list ---"
empty, = build([])

check "no size entries and no separator, just the two lines" do
  empty.entries == ["Open list...", "Text size >"]
end

# The callback runs through defer, which touches IS_WIN and UI.start_timer, so a
# NameError on that path fails the build rather than waiting for a user to click.
check "no modal box is put up on the way to the window" do
  PLUG::DimAddDialog.close
  $SU_CALLS[:messagebox].clear
  before = $SU_TIMERS.size
  empty.blocks["Open list..."].call
  $SU_TIMERS[before..-1].to_a.each { |t| t[:proc].call }
  $SU_CALLS[:messagebox].empty? && PLUG::DimAddDialog.dialog.visible?
end

puts "\n--- no single object selected ---"
none = RecordingMenu.new
MENU.build(none, nil, nil, "lenx", 1.0)

check "only Text size, since there is nothing to apply a size to" do
  none.entries == ["Text size >"]
end

puts "\n--- result ---"
if $fails.zero?
  puts "PASS — context menu matches the agreed structure"
  exit 0
else
  puts "FAIL — #{$fails} problem(s)"
  exit 1
end
