# frozen_string_literal: true

# Two things the user sets and expects to find again after quitting SketchUp:
# the dimension text size, and the list of saved sizes. Both are preferences, and
# whether a preference survives loading can only be judged by controlling what is
# stored *before* the plugin loads. The loader runs once per process, so each
# case gets its own subprocess -- which is also the closest thing here to
# actually restarting SketchUp.

require "rbconfig"

CASES = {
  # stored value (nil = nothing stored yet) => expected settings value after load
  "fresh" => [nil, 0],   # DIM_SMALL
  "large" => [2, 2],     # DIM_LARGE chosen in a previous session
  "medium" => [1, 1],
}.freeze

# Same shape for the saved-size list: what a previous session left in
# preferences, and how many values should come back.
DIM_CASES = {
  "dims-fresh" => [nil, 0],
  "dims-kept" => ["1.7716535433070866,7.874015748031496,15.748031496062993", 3],
  "dims-emptied" => ["", 0],
}.freeze

if ARGV.empty?
  fails = 0

  run = lambda do |name|
    out = `"#{RbConfig.ruby}" "#{__FILE__}" #{name} 2>&1`.strip
    ok = $?.success?
    fails += 1 unless ok
    puts format("  %-56s %s", out.empty? ? name : out, ok ? "OK" : "FAIL")
  end

  puts "--- text size across sessions ---"
  CASES.each_key(&run)

  puts "\n--- saved size list across sessions ---"
  DIM_CASES.each_key(&run)

  puts "\n--- result ---"
  if fails.zero?
    puts "PASS — text size and the saved list both survive a restart"
    exit 0
  else
    puts "FAIL — #{fails} problem(s)"
    exit 1
  end
end

# ---------------------------------------------------------------- child process
name = ARGV[0]
dims = DIM_CASES.key?(name)
stored, expected = (dims ? DIM_CASES : CASES).fetch(name)

require_relative "su_shim"
key = dims ? "dims" : "dim_text_size"
Sketchup.write_default("HTU ScalePlus", key, stored) unless stored.nil?

require File.expand_path("../htu_scaleplus.rb", __dir__)
$SU_CALLS[:register_extension].first.load_extension

PLUG = TRINH_VAN_PHUC::HTU_ScalePlus

if dims
  # nil object: nothing is selected yet at startup, and the list must not need
  # one to be readable.
  actual = PLUG::DimFavorites.list(nil, "lenx").size
  label = stored.nil? ? "nothing stored -> empty list" : "stored #{stored.split(',').size} value(s) -> kept"
else
  actual = PLUG.settings[:dim_text_size]
  label = stored.nil? ? "nothing stored -> default" : "stored #{stored} -> kept"
end

if actual == expected
  puts "#{label} (#{actual})"
  exit 0
else
  puts "#{label}: expected #{expected}, got #{actual.inspect}"
  exit 1
end
