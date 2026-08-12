# frozen_string_literal: true

# The Add window stays open while values are entered and shows the saved list
# underneath. It talks to the page only through render(...), so that call is
# what the behaviour is read from here: what the list holds, what message is
# shown, and that the window is never rebuilt between entries.

require_relative "su_shim"
require File.expand_path("../htu_scaleplus.rb", __dir__)
$SU_CALLS[:register_extension].first.load_extension

PLUG = TRINH_VAN_PHUC::HTU_ScalePlus
FAV = PLUG::DimFavorites
DLG = PLUG::DimAddDialog

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

# The saved list is a machine-wide preference, so it carries between checks
# unless it is put back to "fresh install" first.
def reset_favorites!
  PLUG.settings = PLUG::Settings.new("HTU ScalePlus")
  Sketchup.defaults.delete(["HTU ScalePlus", FAV::SHARED_KEY.to_s])
  FAV::AXES.each { |axis| Sketchup.defaults.delete(["HTU ScalePlus", FAV.attribute(axis)]) }
end

# A fresh component with the window open on its X axis.
def open_on(values = [])
  DLG.close
  reset_favorites!
  group = Sketchup::Group.new
  unless values.empty?
    good, = FAV.parse(values.join(","))
    FAV.add(group, "lenx", good)
  end
  dialog = DLG.show(group, "lenx")
  [dialog, group]
end

def fire(dialog, name, *args)
  dialog.callbacks.fetch(name).call(nil, *args)
end

# The last render(...) payload, parsed back out of the pushed script.
def rendered(dialog)
  script = dialog.scripts.reverse.find { |s| s.start_with?("render(") }
  return nil unless script

  JSON.parse(script[7..-2])
end

puts "--- opening ---"
dialog, group = open_on(%w[45 200])

check "the window is up" do
  dialog.visible?
end

check "the saved values are in the list straight away" do
  rendered(dialog)["values"].size == 2
end

# One list serves all three axes, so a heading naming the one that was
# right-clicked would promise a separation that is not there.
check "the heading does not claim the list belongs to an axis" do
  heading = rendered(dialog)["heading"].to_s
  !heading.empty? && !heading.match?(/lenx|Length X/i)
end

check "the page is served inline, not from the Vue manager's assets" do
  dialog.html.include?("sketchup.add") && $SU_CALLS[:dialog_file].empty?
end

check "the page wires up every callback the Ruby side registers" do
  dialog.callbacks.keys.reject { |name| name == "ready" }.all? do |name|
    dialog.html.include?("sketchup.#{name}")
  end
end

puts "\n--- adding without the window going away ---"

check "one entry adds and the list grows in place" do
  d, g = open_on(%w[45])
  before = d.object_id
  fire(d, "add", "200")
  FAV.list(g, "lenx").size == 2 && rendered(d)["values"].size == 2 &&
    d.visible? && DLG.dialog.object_id == before
end

check "several entries in a row reuse the same window" do
  d, g = open_on
  ids = []
  %w[45 200 400].each do |v|
    fire(d, "add", v)
    ids << DLG.dialog.object_id
  end
  FAV.list(g, "lenx").size == 3 && ids.uniq.size == 1 && d.visible?
end

check "a comma separated entry still adds every value at once" do
  d, g = open_on
  fire(d, "add", "45, 200, 400")
  FAV.list(g, "lenx").size == 3 && rendered(d)["message"].include?("3")
end

check "adding a value already saved does not duplicate it" do
  d, g = open_on(%w[45 200])
  fire(d, "add", "200")
  FAV.list(g, "lenx").size == 2
end

puts "\n--- entries that cannot be read ---"

check "one bad value rejects the whole entry and names it" do
  d, g = open_on
  fire(d, "add", "45, abc, 400")
  FAV.list(g, "lenx").empty? && rendered(d)["message"].include?("abc")
end

check "the window stays open after a rejection" do
  d, = open_on
  fire(d, "add", "abc")
  d.visible?
end

check "a blank entry is a no-op, not an error" do
  d, g = open_on(%w[45])
  fire(d, "add", "   ")
  FAV.list(g, "lenx").size == 1 && rendered(d)["message"].empty?
end

puts "\n--- removing from the list ---"

check "the x on a row drops that value" do
  d, g = open_on(%w[45 200 400])
  target = rendered(d)["values"][1]
  fire(d, "remove", target)
  FAV.list(g, "lenx").size == 2 && !rendered(d)["values"].include?(target)
end

check "removing something already gone is harmless" do
  d, g = open_on(%w[45])
  fire(d, "remove", "999mm")
  FAV.list(g, "lenx").size == 1
end

# Delete all moved here from the Del submenu, which no longer exists.
check "Delete all empties the list once confirmed" do
  d, g = open_on(%w[45 200 400])
  $SU_ANSWER = IDYES
  fire(d, "removeAll")
  FAV.list(g, "lenx").empty? && rendered(d)["values"].empty?
end

# The list is a preference, not model data, so Ctrl+Z cannot bring it back --
# which is exactly why this one asks first.
check "it asks before wiping, and says undo will not help" do
  d, = open_on(%w[45 200 400])
  $SU_CALLS[:messagebox].clear
  $SU_ANSWER = IDYES
  fire(d, "removeAll")
  $SU_CALLS[:messagebox].last.to_s.include?("3") &&
    $SU_CALLS[:messagebox].last.to_s.downcase.include?("undone")
end

check "answering no leaves the list alone" do
  d, g = open_on(%w[45 200 400])
  $SU_ANSWER = IDNO
  fire(d, "removeAll")
  $SU_ANSWER = IDYES
  FAV.list(g, "lenx").size == 3
end

check "an already empty list does not put a confirmation up at all" do
  d, = open_on
  $SU_CALLS[:messagebox].clear
  fire(d, "removeAll")
  $SU_CALLS[:messagebox].empty?
end

puts "\n--- retargeting and closing ---"

check "right-clicking another axis retargets rather than stacking a window" do
  d, g = open_on(%w[45 200])
  same = DLG.show(g, "lenz")
  same.object_id == d.object_id && DLG.axis == "lenz" &&
    rendered(d)["values"].size == 2
end

check "Close closes it" do
  d, = open_on
  fire(d, "closeDialog")
  !d.visible?
end

check "a closed window is not written to" do
  d, = open_on(%w[45])
  fire(d, "closeDialog")
  count = d.scripts.size
  DLG.send(:refresh, "ignored")
  d.scripts.size == count
end

puts "\n--- the component disappears underneath it ---"

# The window is modeless, so the component it was opened from can be deleted or
# undone away while it sits there. That used to matter, because the list lived
# on that component; now it is a preference, and the window carries on.
check "the list keeps working after the component is gone" do
  d, g = open_on(%w[45])
  g.define_singleton_method(:valid?) { false }
  fire(d, "add", "200")
  rendered(d)["values"].size == 2 && !rendered(d)["message"].include?("gone")
end

puts "\n--- result ---"
if $fails.zero?
  puts "PASS — one window, list visible, never rebuilt between entries"
  exit 0
else
  puts "FAIL — #{$fails} problem(s)"
  exit 1
end
