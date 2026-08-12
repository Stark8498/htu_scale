# frozen_string_literal: true

# DimFavorites is the single owner of the saved-size list. Its parsing rules are
# pure logic, so they can be pinned down here rather than discovered in SketchUp.

require_relative "su_shim"
require File.expand_path("../htu_scaleplus.rb", __dir__)
$SU_CALLS[:register_extension].first.load_extension

FAV = TRINH_VAN_PHUC::HTU_ScalePlus::DimFavorites

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

puts "--- parse ---"

check "\"45, 200, 400\" -> 3 values, nothing rejected" do
  good, bad = FAV.parse("45, 200, 400")
  good.size == 3 && bad.empty?
end

check "values come back sorted" do
  good, = FAV.parse("400, 45, 200")
  good == good.sort
end

check "newline and semicolon separate too" do
  good, bad = FAV.parse("45\n200;400")
  good.size == 3 && bad.empty?
end

check "surrounding whitespace is ignored" do
  good, bad = FAV.parse("  45 ,  200  ")
  good.size == 2 && bad.empty?
end

check "empty entries are skipped, not rejected" do
  good, bad = FAV.parse("45,,200,")
  good.size == 2 && bad.empty?
end

check "unreadable entry is reported verbatim" do
  _, bad = FAV.parse("45, abc, 400")
  bad == ["abc"]
end

check "zero and negatives are rejected, not silently dropped" do
  _, bad = FAV.parse("0, -5, 45")
  bad == ["0", "-5"]
end

check "empty input yields nothing at all" do
  good, bad = FAV.parse("   ")
  good.empty? && bad.empty?
end

check "duplicates in one entry collapse" do
  good, = FAV.parse("45, 45, 45")
  good.size == 1
end

puts "\n--- storage round trip ---"

PLUG = TRINH_VAN_PHUC::HTU_ScalePlus

# Back to "never written", the state a fresh install is in -- the shared list
# and the per-axis keys it replaced, since a leftover of either would be
# imported.
def reset!
  PLUG.settings = TRINH_VAN_PHUC::HTU_ScalePlus::Settings.new("HTU ScalePlus")
  Sketchup.defaults.delete(["HTU ScalePlus", FAV::SHARED_KEY.to_s])
  FAV::AXES.each { |axis| Sketchup.defaults.delete(["HTU ScalePlus", FAV.attribute(axis)]) }
end

def fresh_group
  reset!
  Sketchup::Group.new
end

check "list is empty on a fresh install" do
  FAV.list(fresh_group, "lenx").empty?
end

check "add then list returns what went in" do
  group = fresh_group
  good, = FAV.parse("45, 200")
  FAV.add(group, "lenx", good)
  FAV.list(group, "lenx").size == 2
end

check "adding the same value twice does not duplicate it" do
  group = fresh_group
  good, = FAV.parse("45")
  FAV.add(group, "lenx", good)
  FAV.add(group, "lenx", good)
  FAV.list(group, "lenx").size == 1
end

check "one list, so a size added on X is there on Y and Z" do
  group = fresh_group
  good, = FAV.parse("45, 200")
  FAV.add(group, "lenx", good)
  FAV.list(group, "leny").size == 2 && FAV.list(group, "lenz").size == 2
end

check "and removing it on Z takes it off X too" do
  group = fresh_group
  good, = FAV.parse("45, 200")
  FAV.add(group, "lenx", good)
  FAV.remove(group, "lenz", FAV.list(group, "lenz").first)
  FAV.list(group, "lenx").size == 1
end

check "remove takes out exactly one value" do
  group = fresh_group
  good, = FAV.parse("45, 200, 400")
  FAV.add(group, "lenx", good)
  FAV.remove(group, "lenx", FAV.list(group, "lenx")[1])
  FAV.list(group, "lenx").size == 2
end

check "clear empties the list" do
  group = fresh_group
  good, = FAV.parse("45, 200")
  FAV.add(group, "lenx", good)
  FAV.clear(group, "lenx")
  FAV.list(group, "lenx").empty?
end

check "an unknown axis is refused rather than written" do
  group = fresh_group
  good, = FAV.parse("45")
  FAV.write(group, "lenq", good)
  FAV.list(group, "lenq").empty?
end

puts "\n--- one list, shared by everything ---"

check "a value added on one object shows on another" do
  a = fresh_group
  b = Sketchup::Group.new
  good, = FAV.parse("45, 200")
  FAV.add(a, "lenx", good)
  FAV.list(b, "lenx").size == 2
end

check "it goes to preferences, which is what outlives the session" do
  group = fresh_group
  good, = FAV.parse("45, 200")
  FAV.add(group, "lenx", good)
  Sketchup.read_default("HTU ScalePlus", "dims", nil).to_s.split(",").size == 2
end

check "under one key, not one per axis" do
  group = fresh_group
  FAV.add(group, "leny", FAV.parse("45").first)
  FAV::AXES.all? { |axis| Sketchup.read_default("HTU ScalePlus", FAV.attribute(axis), nil).nil? }
end

check "stored as inches, so the list survives a change of model units" do
  group = fresh_group
  FAV.add(group, "lenx", ["25.4".to_l]) # 25.4mm is 1 inch
  stored = Sketchup.read_default("HTU ScalePlus", "dims", nil).to_s.split(",").map(&:to_f)
  stored.size == 1 && (stored.first - 1.0).abs < 1e-9
end

puts "\n--- lists already saved inside old models ---"

def legacy_group(values)
  reset!
  group = Sketchup::Group.new
  group.definition.set_attribute(PLUG, "lenx_dims", values.map(&:to_l))
  group
end

check "a model's own list is carried across on first use" do
  group = legacy_group(%w[45 200 400])
  FAV.list(group, "lenx").size == 3
end

check "and it lands in preferences, so it is there next session" do
  group = legacy_group(%w[45 200])
  FAV.list(group, "lenx")
  Sketchup.read_default("HTU ScalePlus", "dims", nil).to_s.split(",").size == 2
end

# A model that predates the shared list could have a different set saved on
# each axis. Losing two thirds of them would be a poor way to introduce the
# change, so all three are merged.
check "a list saved on every axis is merged, not read off X alone" do
  reset!
  group = Sketchup::Group.new
  { "lenx" => %w[45], "leny" => %w[200], "lenz" => %w[400] }.each do |axis, values|
    group.definition.set_attribute(PLUG, FAV.attribute(axis), values.map(&:to_l))
  end
  FAV.list(group, "lenx").size == 3
end

# The per-axis preference is where this session's own lists went before the
# change, so it is the one most likely to hold something the user cares about.
check "the per-axis preferences this replaced are picked up too" do
  reset!
  Sketchup.write_default("HTU ScalePlus", "leny_dims", "1.0,2.0")
  FAV.list(nil, "lenx").size == 2
end

# Otherwise deleting a size would be undone by the next old component the user
# happens to right-click.
check "emptying the list on purpose is not undone by the import" do
  group = legacy_group(%w[45 200])
  FAV.list(group, "lenx")
  FAV.clear(group, "lenx")
  FAV.list(group, "lenx").empty?
end

check "the import is skipped once a list of the user's own exists" do
  group = legacy_group(%w[45 200 400])
  FAV.write(group, "lenx", FAV.parse("999").first)
  FAV.list(group, "lenx").size == 1
end

puts "\n--- result ---"
if $fails.zero?
  puts "PASS — parse rules and storage round trip hold"
  exit 0
else
  puts "FAIL — #{$fails} problem(s)"
  exit 1
end
