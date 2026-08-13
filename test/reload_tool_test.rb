# frozen_string_literal: true

# dev/htu_scaleplus_reload.rb is not shipped, but it decides which files reach
# SketchUp's memory during every test round, and when it is wrong it is wrong in
# silence: it prints "reloaded" and a column of MD5s for the files it did load,
# and says nothing about the one it skipped.
#
# That happened. group_lock.rb was added to the plugin and never added to the
# reloader's hand-kept list, so GroupLock stayed at the version SketchUp loaded at
# boot for a whole day of edits. PLUGIN.repick_scale_tool died on the missing
# GroupLock.suspend, its rescue swallowed it, the axis lock silently stopped taking
# effect, and the hunt went into the plugin -- where nothing was wrong.
#
# So the list is now read out of loader.rb. These checks pin that, and pin the
# fallback list too: a fallback that has gone stale brings the whole bug back.

RELOADER = File.expand_path("../dev/htu_scaleplus_reload.rb", __dir__)
LOADER   = File.expand_path("../htu_scaleplus/loader.rb", __dir__)
PLUGIN_DIR = File.expand_path("../htu_scaleplus", __dir__)

$fails = 0

def check(label)
  ok = yield
  puts format("  %-58s %s", label, ok ? "OK" : "FAIL")
  $fails += 1 unless ok
rescue Exception => e
  puts format("  %-58s RAISED %s: %s", label, e.class, e.message)
  puts "    #{e.backtrace.first}"
  $fails += 1
end

# What loader.rb actually requires, parsed here independently of the reloader's own
# regex. Two readings that agree mean something; one reading compared with itself
# would pass however wrong it is.
REQUIRED = File.readlines(LOADER).reject { |l| l.strip.start_with?("#") }.map do |line|
  line[/Sketchup\.require\s*\(?\s*"\#\{PATH\}\/(\w+)"/, 1]
end.compact.freeze

# Quiet the banner it prints on load.
require "stringio"

def quietly
  $stdout = StringIO.new
  yield
ensure
  $stdout = STDOUT
end

quietly { load RELOADER }

R = HTU_ScalePlusReload

puts "--- the fixture is real ---"

check "loader.rb requires a list of sub-files at all" do
  REQUIRED.length >= 10
end

check "and group_lock is one of them, the file that started this" do
  REQUIRED.include?("group_lock")
end

puts "\n--- the load list comes from loader.rb, not from memory ---"

derived = R.sub_files(PLUGIN_DIR)

check "every file loader.rb requires is in the list" do
  (REQUIRED - derived).empty?
end

check "nothing extra is loaded that the plugin does not require" do
  (derived - REQUIRED - ["loader"]).empty?
end

check "group_lock is there -- the regression itself" do
  derived.include?("group_lock")
end

check "loader.rb is last, it carries the settings defaults" do
  derived.last == "loader"
end

check "and every name in the list is a file that exists" do
  derived.all? { |name| File.exist?(File.join(PLUGIN_DIR, "#{name}.rb")) }
end

# The point of reading loader.rb is to pick up a file added since the last install.
# Proven with a require line that exists nowhere in this repo, so a list built from
# anything but the text of that loader.rb cannot contain it.
puts "\n--- a file added today is picked up, not silently skipped ---"

require "tmpdir"

def with_source_root(dir)
  old = R::SOURCE_ROOT
  R.send(:remove_const, :SOURCE_ROOT)
  R.const_set(:SOURCE_ROOT, dir)
  yield
ensure
  R.send(:remove_const, :SOURCE_ROOT)
  R.const_set(:SOURCE_ROOT, old)
end

def fake_loader(body)
  Dir.mktmpdir("htu_reload_test") do |dir|
    File.write(File.join(dir, "loader.rb"), body)
    with_source_root(dir) { yield R.sub_files(dir) }
  end
end

SYNTHETIC = <<~RUBY
  Sketchup.require "\#{PATH}/utils"
  Sketchup.require "\#{PATH}/brand_new_file"
  Sketchup.require "\#{PATH}/overlay"
RUBY

check "a brand new require line reaches the load list" do
  fake_loader(SYNTHETIC) { |names| names.include?("brand_new_file") }
end

check "in the order loader.rb gives, which is the order it must load in" do
  fake_loader(SYNTHETIC) { |names| names == %w[utils brand_new_file overlay loader] }
end

check "a commented-out require is not loaded" do
  body = "# Sketchup.require \"\#{PATH}/retired\"\nSketchup.require \"\#{PATH}/utils\"\n"
  fake_loader(body) { |names| !names.include?("retired") }
end

check "nested requires under a subfolder are not mistaken for sub-files" do
  body = "Sketchup.require(\"\#{PATH}/radial_menu/constants\")\nSketchup.require \"\#{PATH}/utils\"\n"
  fake_loader(body) { |names| names == %w[utils loader] }
end

check "an unreadable loader.rb falls back rather than loading nothing" do
  Dir.mktmpdir("htu_reload_empty") do |dir|
    with_source_root(nil) { R.sub_files(dir).equal?(R::FALLBACK_FILES) }
  end
end

# #run reports "KHONG doc duoc, dung FALLBACK_FILES" -- the scariest thing this tool can
# say, because it means the file ORDER may be wrong. It was saying it on every run: the
# parse currently yields exactly the same twelve names as the fallback, so a == told them
# apart wrongly. Identity is what separates "parsed" from "gave up", and the two checks
# above rely on it, so this pins that they CAN be told apart at all.
check "a successful parse is a different object from the fallback" do
  body = R::FALLBACK_FILES.reject { |n| n == "loader" }
                          .map { |n| "Sketchup.require \"\#{PATH}/#{n}\"\n" }.join
  fake_loader(body) do |names|
    names == R::FALLBACK_FILES && !names.equal?(R::FALLBACK_FILES)
  end
end

# The fallback is only reached when loader.rb cannot be read, which is exactly the
# moment nobody is watching. It has to be right on its own.
puts "\n--- the fallback list is not allowed to go stale either ---"

check "the fallback covers every file loader.rb requires" do
  (REQUIRED - R::FALLBACK_FILES).empty?
end

check "and carries nothing the plugin has stopped requiring" do
  (R::FALLBACK_FILES - REQUIRED - ["loader"]).empty?
end

puts "\n--- the reloader replaces itself ---"

# Syncing the plugin but not the reloader is how the hand-kept list survived being
# wrong: every run copied the edited plugin files faithfully and left the one file
# that decides WHICH files those are untouched.
check "it knows where its own source lives" do
  R::SELF_SOURCE && File.exist?(R::SELF_SOURCE)
end

check "a copy running from elsewhere is replaced from the repo" do
  # Loaded from a temp dir, __FILE__ inside the module points there, which is what
  # the installed copy in the Plugins folder looks like. Asking the repo copy to
  # sync itself proves nothing: both guards refuse before any logic runs.
  Dir.mktmpdir("htu_reload_self") do |dir|
    stale = File.join(dir, "htu_scaleplus_reload.rb")
    # binwrite, not write: on Windows a text-mode write turns every LF into CRLF, so
    # a byte-for-byte copy comes out 235 bytes longer and the MD5s never match.
    # FileUtils.cp is binary, and this has to compare against what cp would produce.
    File.binwrite(stale, File.binread(RELOADER) + "\n# stale\n")
    quietly { load stale }
    begin
      R.sync_self && File.binread(stale) == File.binread(RELOADER)
    ensure
      quietly { load RELOADER }
    end
  end
end

check "and left alone once it matches, so the run does not bounce" do
  Dir.mktmpdir("htu_reload_same") do |dir|
    same = File.join(dir, "htu_scaleplus_reload.rb")
    File.binwrite(same, File.binread(RELOADER))
    quietly { load same }
    begin
      R.sync_self == false
    ensure
      quietly { load RELOADER }
    end
  end
end

check "run takes the re-entry guard, so self-sync cannot loop" do
  R.method(:run).arity == -1
end

check "sync is handed the list rather than reading a constant" do
  R.method(:sync).arity == 2
end

puts "\n--- result ---"
if $fails.zero?
  puts "PASS — the reloader loads what the plugin requires, including new files"
  exit 0
else
  puts "FAIL — #{$fails} problem(s)"
  exit 1
end
