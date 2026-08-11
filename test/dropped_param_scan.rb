# frozen_string_literal: true

# Static scan for the decompiler's "dropped optional parameter" bug.
#
# Symptom: a method body references a bare identifier (Ripper :vcall — an
# identifier used with no receiver and no args) that is neither a parameter, nor
# a local assigned in the body, nor a method defined anywhere in the plugin, nor
# a known Ruby/SketchUp method. That identifier was almost certainly a method
# parameter that the AST capture lost.
#
# This is how radial_menu/shape_geom.rb#rectangle_points was caught.

require "ripper"
require "set"

ROOT = File.expand_path("../htu_scaleplus", __dir__)
FILES = Dir.glob(File.join(ROOT, "**", "*.rb")).sort

# ---------------------------------------------------------------- pass 1: names
# Every method name defined anywhere in the plugin, plus every constant.
defined_methods = Set.new
defined_consts  = Set.new

def walk(node, &blk)
  return unless node.is_a?(Array)

  blk.call(node)
  node.each { |c| walk(c, &blk) if c.is_a?(Array) }
end

FILES.each do |f|
  sexp = Ripper.sexp(File.read(f))
  next unless sexp

  walk(sexp) do |n|
    case n[0]
    when :def
      defined_methods << n[1][1] if n[1].is_a?(Array) && n[1][1].is_a?(String)
    when :defs
      defined_methods << n[3][1] if n[3].is_a?(Array) && n[3][1].is_a?(String)
    when :command, :method_add_arg
      # attr_accessor :foo, :bar  /  attr_accessor(:foo, :bar)
      #
      # `attr_accessor :foo` parses as [:command, ident, args]; the parenthesised
      # form parses as [:method_add_arg, [:fcall, ident], [:arg_paren, args]] —
      # so the symbols hang off the OUTER node, not off the fcall. Matching
      # :fcall alone silently missed every parenthesised attr_ declaration.
      head = n[1]
      head = head[1] if head.is_a?(Array) && head[0] == :fcall
      if head.is_a?(Array) && head[1].is_a?(String) && head[1].start_with?("attr_")
        walk(n) do |m|
          next unless m[0] == :symbol && m[1].is_a?(Array) && m[1][1].is_a?(String)

          defined_methods << m[1][1]
          defined_methods << "#{m[1][1]}="
        end
      end
    when :const_path_ref, :var_ref, :const_ref
      defined_consts << n[1][1] if n[1].is_a?(Array) && n[1][0] == :@const
    end

    # alias_method(:new_name, :old) / alias new_name old — both create a callable.
    if n[0] == :alias
      walk(n) { |m| defined_methods << m[1][1] if m[0] == :@ident && m[1].is_a?(String) }
    end
    head = n[1]
    head = head[1] if head.is_a?(Array) && head[0] == :fcall
    if head.is_a?(Array) && head[1] == "alias_method"
      walk(n) do |m|
        defined_methods << m[1][1] if m[0] == :symbol && m[1].is_a?(Array) && m[1][1].is_a?(String)
      end
    end
  end
end

# Bare-callable methods that legitimately come from outside the plugin.
KNOWN = Set.new(%w[
  self nil true false __method__ __dir__ binding block_given? caller
  raise fail puts print p pp require require_relative load loop lambda proc
  rand srand sleep exit at_exit catch throw format sprintf gets
  freeze frozen? dup clone inspect to_s to_a to_i to_f hash class
  new initialize super allocate
  file_loaded file_loaded? register_extension
  extend include prepend private public protected module_function
  attr_accessor attr_reader attr_writer define_method instance_variable_get
  instance_variable_set respond_to? send __send__ method methods
  size length count first last empty? nil? any? all? none? map each select
  reject find reduce sort min max sum flatten compact uniq reverse join
  now
  object_id instance_variables instance_variables_get caller_locations
  frozen block_given
])

# Known-and-accepted: authentic upstream defects that are NOT dropped params.
# Keyed by "file#method:identifier" so a new occurrence still fails the scan.
ACCEPTED = {
  # `onSetCursor` is called bare in Menu#onMouseMove but never defined. The
  # author's `missing_method` typo (see menu.rb) meant this was never absorbed;
  # menu.rb now aliases it onto the real method_missing hook, so the call is a
  # logged no-op. Kept listed because the identifier genuinely does not resolve.
  "htu_scaleplus/radial_menu/menu.rb#onMouseMove:onSetCursor" => true,
}.freeze

# ---------------------------------------------------- pass 2: per-def vcall scan

findings = []

FILES.each do |f|
  src = File.read(f)
  sexp = Ripper.sexp(src)
  next unless sexp

  walk(sexp) do |n|
    next unless n[0] == :def || n[0] == :defs

    if n[0] == :def
      mname = n[1].is_a?(Array) ? n[1][1] : nil
      params = n[2]
      body   = n[3]
    else
      mname = n[3].is_a?(Array) ? n[3][1] : nil
      params = n[4]
      body   = n[5]
    end
    next unless mname

    # Collect declared parameter names.
    pnames = Set.new
    walk(params) { |m| pnames << m[1] if m[0] == :@ident }

    # Collect locals assigned anywhere in the body (incl. block params, for, rescue=>).
    locals = Set.new
    walk(body) do |m|
      case m[0]
      when :assign, :massign, :opassign
        walk(m[1]) { |t| locals << t[1] if t[0] == :@ident }
      when :params, :block_var
        walk(m) { |t| locals << t[1] if t[0] == :@ident }
      when :rescue
        walk(m[2]) { |t| locals << t[1] if t[0] == :@ident } if m[2]
      end
    end

    # Any bare identifier call in the body.
    walk(body) do |m|
      next unless m[0] == :vcall && m[1].is_a?(Array) && m[1][0] == :@ident

      name = m[1][1]
      line = m[1][2].is_a?(Array) ? m[1][2][0] : nil
      next if pnames.include?(name) || locals.include?(name)
      next if defined_methods.include?(name) || KNOWN.include?(name)

      rel = f.sub(File.dirname(ROOT) + File::SEPARATOR, "").tr("\\", "/")
      next if ACCEPTED["#{rel}##{mname}:#{name}"]

      findings << {
        file: rel,
        line: line,
        method: mname,
        name: name,
        params: pnames.to_a,
      }
    end
  end
end

puts "Scanned #{FILES.size} files for dropped-parameter symptoms.\n"

if findings.empty?
  puts "PASS — no method body references an unresolvable bare identifier."
  exit 0
end

findings.uniq! { |h| [h[:file], h[:method], h[:name]] }
puts "#{findings.size} suspect identifier(s):\n"
findings.each do |h|
  puts format("  %s:%s  in %s(%s)  ->  bare `%s`",
              h[:file], h[:line], h[:method], h[:params].join(", "), h[:name])
end
puts "\nEach is either a lost method parameter or a call into an API this scan"
puts "does not know about. Check the call sites to decide."
exit 1
