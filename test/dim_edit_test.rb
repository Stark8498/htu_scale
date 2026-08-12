# frozen_string_literal: true

# Clicking a dimension turns it into a text field: the number shows selected,
# and typing replaces it. The drawing half needs a real viewport, but the state
# machine behind it does not -- and that is where the behaviour lives, so it is
# pinned here.
#
# The echo is a preview only. onUserText applies the VCB's own text, so these
# checks also cover the rule that an unmirrorable key gives up on the preview
# instead of showing something that does not match what will be applied.

require_relative "su_shim"
require File.expand_path("../htu_scaleplus.rb", __dir__)
$SU_CALLS[:register_extension].first.load_extension

TOOL = TRINH_VAN_PHUC::HTU_ScalePlus::ScalePPTool
VIEW = Sketchup.active_model.active_view

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

# A tool with an axis already locked, i.e. straight after the click.
def locked
  tool = TOOL.new(nil)
  tool.lock_axis("lenx")
  tool
end

def type(tool, *keys)
  keys.each { |k| tool.onKeyDown(k, 1, 0, VIEW) }
  tool
end

DIGITS = { "0" => 48, "1" => 49, "2" => 50, "4" => 52, "5" => 53, "8" => 56 }.freeze
BACKSPACE = 8
NUMPAD_7 = 103
PERIOD = 190
LETTER_M = 77
ENTER = 13
SHIFT = 16
F5 = 116
DELETE = 46

puts "--- straight after the click ---"

check "the axis is locked" do
  locked.locked_axis == "lenx"
end

check "nothing typed yet, so the number draws selected" do
  locked.edit_buffer.nil?
end

check "the VCB is primed with a label and a prompt" do
  locked
  $SU_CALLS[:status_text].last(3).map(&:first).any? { |t| t.to_s.include?("Type a length") }
end

puts "\n--- typing replaces the selection ---"

check "the first keystroke ends the selected state" do
  t = type(locked, DIGITS["4"])
  t.edit_buffer == "4"
end

check "digits accumulate in order" do
  type(locked, DIGITS["4"], DIGITS["5"], DIGITS["0"]).edit_buffer == "450"
end

check "numpad digits count the same as the top row" do
  type(locked, NUMPAD_7, DIGITS["5"]).edit_buffer == "75"
end

check "a decimal point is accepted" do
  type(locked, DIGITS["1"], PERIOD, DIGITS["5"]).edit_buffer == "1.5"
end

check "letters are accepted so a unit suffix mirrors too" do
  type(locked, DIGITS["8"], LETTER_M, LETTER_M).edit_buffer == "8mm"
end

puts "\n--- editing what was typed ---"

check "backspace removes the last character" do
  type(locked, DIGITS["4"], DIGITS["5"], BACKSPACE).edit_buffer == "4"
end

check "backspacing everything leaves an empty field, not the old number" do
  t = type(locked, DIGITS["4"], BACKSPACE)
  t.edit_buffer == "" && !t.edit_buffer.nil?
end

check "backspace on an empty field does not underflow" do
  type(locked, BACKSPACE, BACKSPACE).edit_buffer == ""
end

check "Delete clears the whole field" do
  type(locked, DIGITS["4"], DIGITS["5"], DELETE).edit_buffer == ""
end

puts "\n--- keys that are not the buffer's business ---"

check "Enter, Shift and F5 leave the echo alone" do
  t = type(locked, DIGITS["4"], SHIFT, ENTER, F5)
  t.edit_echo && t.edit_buffer == "4"
end

check "an unmirrorable key gives up the preview rather than guessing" do
  t = type(locked, DIGITS["4"], 219) # VK_OEM_4, layout dependent
  !t.edit_echo
end

check "once given up it stays given up for the rest of the entry" do
  t = type(locked, 219, DIGITS["4"], DIGITS["5"])
  !t.edit_echo && t.edit_buffer.nil?
end

check "the next click starts a fresh, mirrorable entry" do
  t = type(locked, 219)
  t.lock_axis("leny")
  t.edit_echo && t.edit_buffer.nil?
end

puts "\n--- leaving the field ---"

check "unlocking clears what was typed" do
  t = type(locked, DIGITS["4"])
  t.unlock_axis
  t.locked_axis.nil? && t.edit_buffer.nil?
end

check "keystrokes are ignored when no axis is locked" do
  t = TOOL.new(nil)
  type(t, DIGITS["4"])
  t.edit_buffer.nil?
end

check "an unreadable VCB entry re-selects instead of dropping the lock" do
  t = type(locked, DIGITS["4"])
  t.onUserText("nonsense", VIEW)
  t.locked_axis == "lenx" && t.edit_buffer.nil?
end

puts "\n--- result ---"
if $fails.zero?
  puts "PASS — click selects the number, typing replaces it, the preview never lies"
  exit 0
else
  puts "FAIL — #{$fails} problem(s)"
  exit 1
end
