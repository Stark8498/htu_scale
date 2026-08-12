# encoding: UTF-8
#
# htu_hover_probe.rb
#
# Why the hover dimensions appear on one object and not on another, answered by
# the running plugin instead of by reading two screenshots. There are five
# separate reasons #update_hover can decide "no labels" and a screenshot shows
# none of them apart.
#
#   load "E:/htu_scaleplus/dev/htu_hover_probe.rb"
#   HTU_HoverProbe.on
#   # bam S, roi re chuot qua vat KHONG hien so do, roi qua vat CO hien
#   HTU_HoverProbe.off
#
# Prints only when the decision CHANGES, so a slow sweep over two objects gives
# two or three lines, not hundreds. Survives HTU_ScalePlusReload.run.
#
#   why=      the reason there are no labels, or "ok". This is the whole point:
#             pref-off / not-active / state=N / locked-axis / navigating /
#             pick-nil / already-selected / temp-wrapper.
#   pick=     what the pick helper returned under the cursor. "nil" means empty
#             space OR raw geometry -- a face or edge is not a scale target, so
#             #pick_object returns nil for both. If a panel reads nil while the
#             cursor is plainly on it, that panel is loose geometry, not a group.
#   defn=     whether the picked thing has a definition, i.e. is a group or a
#             component instance. This is the raw-geometry test.
#   sel=      whether it is already selected -- excluded on purpose, the selection
#             draws its own dimensions.
#   dims=     how many labels came out. 3 is normal; 0 with why=ok means the box
#             is degenerate (a flat panel seen edge-on loses one axis).
#   push=     whether this tool holds the tool stack, and own= whether the cursor
#             is outside the selection's padded grip box. Both are here because
#             "near the selection" and "far from it" is how the difference was
#             first described -- these two are the only things in the plugin that
#             change with that distance.
#
# Also traces every #clear_hover with the line that called it. A label that is
# computed and then wiped inside the same mouse event looks exactly like a label
# that was never computed.

module HTU_HoverProbe
  # `unless defined?` because this file gets `load`ed again after every
  # HTU_ScalePlusReload.run, and a plain assignment warns about an already
  # initialized constant every time -- noise in the middle of the measurements.
  P = TRINH_VAN_PHUC::HTU_ScalePlus unless defined?(P)

  class << self
    attr_accessor :running, :last, :calls, :mode, :printed
  end
  @running = false
  @last = nil
  @calls = 0
  @mode = nil
  @printed = 0

  # prepend, not alias_method: HTU_ScalePlusReload.run reloads scale_tool.rb and
  # would throw an aliased wrapper away while leaving the alias behind, so the
  # guard would refuse to put it back and every line would go quiet. See the note
  # in htu_nav_probe.rb -- a measuring instrument that lies is worse than none.
  module Trace
    # The plugin swallows its own errors with `p(e)`, which prints
    #   #<NoMethodError: undefined method `width' for nil:NilClass>
    # and nothing else -- no method, no line, no way to tell which of a dozen
    # rescues it came from. `p` is a private Kernel method called on the tool
    # itself, so a prepended module can take it over and add the backtrace.
    # Every rescue in ScalePPTool goes through here, #draw included.
    def p(*args)
      first = args.first
      if HTU_HoverProbe.running && first.is_a?(Exception)
        puts "  !! #{first.class}: #{first.message}"
        (first.backtrace || []).first(6).each { |line| puts "     #{line}" }
        return first
      end
      super
    end

    def update_hover(x, y, view)
      HTU_HoverProbe.calls += 1
      result = super
      HTU_HoverProbe.report(self, x, y, view)
      result
    end

    def clear_hover(view = nil)
      had = hover_object || hover_dims
      result = super
      if had && HTU_HoverProbe.running
        origin = caller.find { |line| !line.include?("htu_hover_probe") }
        puts "  cleared by #{origin}"
      end
      result
    end
  end

  def self.instrument
    P::ScalePPTool.prepend(Trace)
    true
  end

  # The same conditions #update_hover applies, in the same order, so the answer
  # names the branch that actually returned.
  def self.why(tool, x, y, view)
    unless P.show_hover_dim?
      return ["pref-off", nil]
    end
    unless tool.active?
      return ["not-active", nil]
    end
    state = tool.instance_variable_get(:@tool_state)
    unless state == 0
      return ["state=#{state.inspect}", nil]
    end
    locked = tool.instance_variable_get(:@locked_axis)
    if locked
      return ["locked-axis(#{locked})", nil]
    end
    if P.navigating?
      return ["navigating", nil]
    end
    entity = tool.pick_object(x, y, view)
    if entity.nil?
      return ["pick-nil", nil]
    end
    if P::GroupLock.temp?(entity)
      return ["temp-wrapper", entity]
    end
    if Sketchup.active_model.selection.to_a.include?(entity)
      return ["already-selected", entity]
    end
    ["ok", entity]
  end

  def self.report(tool, x, y, view)
    unless @running
      return
    end
    reason, entity = why(tool, x, y, view)
    dims = tool.hover_dims ? tool.hover_dims.compact.size : 0
    line = format("why=%-18s pick=%-22s defn=%-5s sel=%-5s dims=%d  push=%-5s own=%-5s at=(%d,%d)",
                  reason,
                  describe(entity),
                  (entity ? entity.respond_to?(:definition).to_s : "-"),
                  (entity ? Sketchup.active_model.selection.to_a.include?(entity).to_s : "-"),
                  dims,
                  tool.on_push_tool.to_s,
                  safe { tool.outside_grips?(x, y, view).to_s },
                  x, y)
    # Only on change, unless asked for everything. The cursor generates dozens of
    # moves per second, so the default keeps a sweep readable -- at the cost of
    # making "no line printed" ambiguous, which is what .here and :all are for.
    key = line.sub(/at=\(\d+,\d+\)/, "")
    if key == @last && @mode != :all
      return
    end
    @last = key
    if @mode == :all
      @printed = (@printed || 0) + 1
      if @printed > 300
        puts "  (300 dong, tu tat -- HTU_HoverProbe.on(:all) de chay lai)"
        @mode = nil
        @running = false
        return
      end
    end
    puts line
  rescue StandardError => e
    puts "hover probe: #{e.class}: #{e.message}"
  end

  # Degrades a step at a time instead of collapsing to "?". The first version
  # reached for #entityID unconditionally and printed "?" for everything the
  # moment that raised -- hiding the class, which is the one field that answers
  # "group or loose face".
  def self.describe(entity)
    unless entity
      return "nil"
    end
    short = entity.class.name.to_s.split("::").last
    parts = []
    name = safe_value { entity.name.to_s }
    if name && !name.empty?
      parts << name
    end
    defn = safe_value { entity.definition.name.to_s }
    if defn && !defn.empty? && defn != name
      parts << "<#{defn}>"
    end
    id = safe_value { entity.entityID } || entity.object_id
    parts.empty? ? "#{short}##{id}" : "#{short}:#{parts.join}"
  end

  def self.safe_value
    yield
  rescue StandardError
    nil
  end

  def self.safe
    yield
  rescue StandardError => e
    "raised #{e.class}"
  end

  def self.on(mode = nil)
    instrument
    @running = true
    @last = nil
    @calls = 0
    @printed = 0
    @mode = mode
    puts "HTU_HoverProbe: on#{mode == :all ? ' (moi cu di chuot mot dong, toi 300)' : ' (chi in khi quyet dinh doi)'}."
    puts "                re chuot len mat KHONG hien so do, roi go:"
    puts "                  HTU_HoverProbe.here   -> do tai dung vi tri con tro, in het"
    puts "                  HTU_HoverProbe.stats  -> update_hover da chay bao nhieu lan"
    puts "                  HTU_HoverProbe.dims   -> nhan nao thieu, va VI SAO thieu"
    puts "                  HTU_HoverProbe.grips  -> mask, truc suy bien, grip thay the"
    puts "                  HTU_HoverProbe.dc     -> cong thuc Dynamic Component nao vo"
    puts "                  HTU_HoverProbe.on(:all) / .off"
    true
  end

  # The command to use when a line does NOT appear.
  #
  # #report only prints when the decision changes, which is what keeps a mouse
  # sweep from flooding the console -- and it also means "no line" is ambiguous:
  # the path may never have run, or it ran and decided the same thing as last
  # time. This runs the whole decision again, at the cursor position the tool last
  # saw, prints every step whether it changed or not, and never dedupes.
  #
  #   re chuot len mat KHONG hien so do, roi go: HTU_HoverProbe.here
  #
  # Moving the hand over to the Ruby Console does not disturb it: @mouse keeps the
  # last position inside the viewport.
  def self.here
    overlay = P::PLUGIN.active_overlay
    tool = overlay && overlay.dim_scale
    unless tool
      puts "here: khong co tool"
      return false
    end
    mouse = tool.instance_variable_get(:@mouse) || (overlay.mouse if overlay.respond_to?(:mouse))
    unless mouse
      puts "here: chua co vi tri chuot nao"
      return false
    end
    x, y = mouse
    view = Sketchup.active_model.active_view
    puts "--- here at (#{x}, #{y}) ---"
    puts format("  pref=%s active=%s flag=%s state=%s locked=%s nav=%s",
                P.show_hover_dim?.to_s, tool.active?.to_s,
                tool.instance_variable_get(:@active).inspect,
                tool.instance_variable_get(:@tool_state).inspect,
                tool.instance_variable_get(:@locked_axis).inspect,
                P.navigating?.to_s)
    # The raw pick, before #pick_object throws away anything without a definition.
    # This is the line that separates "empty space" from "raw geometry": a loose
    # face or edge picks fine and is then dropped on purpose, and from a screenshot
    # the two look identical.
    helper = view.pick_helper
    helper.do_pick(x, y)
    best = safe { helper.best_picked }
    puts format("  raw: count=%s best=%s defn=%s",
                safe { helper.count.to_s },
                describe(best.is_a?(Sketchup::Entity) ? best : nil),
                (best.respond_to?(:definition) ? "yes" : "NO -- bi bo qua"))
    if best.respond_to?(:parent) && best.respond_to?(:definition) == false
      puts format("  raw: parent=%s (mat/canh roi thi parent la Entities cua context)",
                  safe { best.parent.class.name })
    end
    filtered = tool.pick_object(x, y, view)
    puts format("  pick_object -> %s", describe(filtered))
    reason, entity = why(tool, x, y, view)
    puts format("  why=%s entity=%s", reason, describe(entity))
    if entity
      built = safe { tool.build_hover_dims(view, entity) }
      count = built.is_a?(Array) ? built.compact.size : built.inspect
      bounds = safe do
        bb = tool.compute_bounds_for([entity])
        pts = bb[:points]
        pts ? format("%s .. %s", pts[0].to_a.map(&:round).inspect, pts[7].to_a.map(&:round).inspect) : "khong co points"
      end
      puts format("  build_hover_dims -> %s   bounds=%s", count, bounds)
    end
    puts format("  state bay gio: hover_object=%s dims=%s",
                describe(tool.hover_object),
                (tool.hover_dims ? tool.hover_dims.compact.size : "nil"))
    # The two things that change with distance to the selection, and the only two
    # in the plugin that do. If "near" and "far" is real, it shows up here.
    puts format("  push=%s own_click=%s outside_grips=%s",
                tool.on_push_tool.to_s,
                tool.own_click?.to_s,
                safe { tool.outside_grips?(x, y, view).to_s })
    true
  rescue StandardError => e
    puts "here: #{e.class}: #{e.message}"
    puts (e.backtrace || []).first(4).map { |l| "    #{l}" }.join("\n")
    false
  end

  # Which grips get drawn, and by whom -- the whole chain in one line each.
  #
  # Written for a report that the grip set changes as the cursor moves in and out,
  # and that choosing an axis does not take. Four different things decide what is on
  # screen and a screenshot shows none of them apart: whether the mask could be
  # written at all (only a definition can hold one), what mask_lines makes of it,
  # whether a bounding box axis is degenerate (a flat panel has one, and its two
  # grips land on top of each other in the middle), and whether this tool is standing
  # in for SketchUp's grips or staying quiet because SketchUp is drawing its own.
  #
  #   re chuot VAO trong tam -> HTU_HoverProbe.grips
  #   re chuot RA ngoai      -> HTU_HoverProbe.grips
  def self.grips
    overlay = P::PLUGIN.active_overlay
    tool = overlay && overlay.dim_scale
    unless tool
      puts "grips: khong co tool"
      return false
    end
    view = Sketchup.active_model.active_view
    sel = Sketchup.active_model.selection.to_a
    puts "--- grips ---"
    puts format("  behavior_state=%s (0=all 120=xyz 126=x 125=y 123=z)", P.behavior_state)
    puts format("  selection=%s", sel.empty? ? "rong" : sel.map { |e| describe(e) }.join(", "))
    # The mask lives on a ComponentDefinition. Loose geometry has none, so there is
    # nowhere for the chosen axis to be written -- apply_behavior skips it, and both
    # SketchUp and this plugin then show every grip.
    sel.each do |e|
      if e.respond_to?(:definition)
        puts format("    %s mask=%s", describe(e), safe { e.definition.behavior.no_scale_mask?.to_s })
      else
        puts format("    %s KHONG co definition -> mask khong ghi duoc vao dau", describe(e))
      end
    end
    bb = tool.instance_variable_get(:@bb)
    unless bb
      puts "  @bb=nil -> chua co khung bao nao"
      return true
    end
    tr = tool.instance_variable_get(:@tr_bb)
    lines = tool.bounds_center_lines(bb, tr)
    axes = %w[x y z]
    lines.each_with_index do |line, i|
      length = line[0].distance(line[1])
      puts format("  truc %s: dai %s%s", axes[i], length.round(2),
                  length < 1e-6 ? "  <- suy bien: hai grip trung nhau o giua" : "")
    end
    entity = sel.length == 1 ? sel[0] : nil
    kept = tool.mask_lines(lines, entity)
    puts format("  mask_lines giu %d/%d truc", kept.size, lines.size)
    standing_in = safe { tool.active_itself? || P.navigating? }
    puts format("  giu stack=%s nav=%s -> ve grip thay the: %s",
                safe { tool.active_itself?.to_s }, P.navigating?.to_s, standing_in.to_s)
    puts format("  hover_object=%s", describe(tool.hover_object))
    if tool.hover_object
      hbb = tool.instance_variable_get(:@hover_bb_data)
      hlines = hbb && hbb[:bounds] ? tool.mask_lines(tool.bounds_center_lines(hbb[:bounds], hbb[:tr]), tool.hover_object) : []
      live = hlines.reject { |l| !l[0].vector_to(l[1]).valid? }
      puts format("    grip hover: %d truc (bo %d truc suy bien), khong bao gio to",
                  live.size, hlines.size - live.size)
    end
    true
  rescue StandardError => e
    puts "grips: #{e.class}: #{e.message}"
    puts (e.backtrace || []).first(4).map { |l| "    #{l}" }.join("\n")
    false
  end

  # Why a dimension label is missing, and whether the one that IS there can be typed
  # into. A label seen end-on is a dot and gets dropped on purpose, so "no label" and
  # "broken" look identical on screen -- this separates them.
  def self.dims
    tool = safe { P::PLUGIN.active_overlay && P::PLUGIN.active_overlay.dim_scale }
    unless tool
      puts "dims: khong co tool"
      return false
    end
    view = Sketchup.active_model.active_view
    direction = view.camera.direction
    puts "--- dims ---"
    puts format("  selection=%s", Sketchup.active_model.selection.to_a.map { |e| describe(e) }.join(", "))
    puts format("  camera direction=(%s)", direction.to_a.map { |v| v.round(3) }.join(", "))

    points = safe_value { tool.instance_variable_get(:@bb_data)[:points] }
    unless points && points.length >= 5
      puts "  chua co khung bao -> khong co nhan nao"
      return true
    end
    # The three edges of the box as drawn, in the order compute_dimensions_lines reads
    # them. Each is dropped when the camera looks along it.
    edges = { "x" => points[0].vector_to(points[1]),
              "y" => points[1].vector_to(points[3]),
              "z" => points[0].vector_to(points[4]) }
    edges.each do |name, vec|
      along = vec.valid? && direction.parallel?(vec)
      puts format("  canh %s: dai %-8s %s", name, vec.length.round(2),
                  if !vec.valid?
                    "<- suy bien, day khung bao"
                  elsif along
                    "<- camera nhin DOC theo canh nay: nhan chi la mot diem, bo dung"
                  else
                    "ve duoc"
                  end)
    end

    raw = tool.instance_variable_get(:@dims) || []
    data = (tool.instance_variable_get(:@data_dims) || []).compact
    puts format("  tinh duoc %d nhan, ve duoc %d nhan", raw.length, data.length)
    data.each do |d|
      box = d[:bb_text_2d]
      size = if box
               xs = box.map { |pt| pt[0] }
               ys = box.map { |pt| pt[1] }
               format("%.0fx%.0f px", xs.max - xs.min, ys.max - ys.min)
             else
               "KHONG co o bam"
             end
      puts format("    %s = %s  o bam %s%s", safe { tool.dim_axis(d) } || "?",
                  d[:line] ? d[:line].first.distance(d[:line].last).to_s : "?", size,
                  d[:hover] ? "  <- con tro dang o day" : "")
    end
    missing = %w[lenx leny lenz].reject { |a| safe { tool.dim_for_axis(a) } }
    puts format("  khong bam duoc: %s", missing.empty? ? "khong thieu truc nao" : missing.join(", "))
    puts format("  locked_axis=%s", tool.locked_axis.inspect)
    true
  rescue StandardError => e
    puts "dims: #{e.class}: #{e.message}"
    puts (e.backtrace || []).first(4).map { |l| "    #{l}" }.join("\n")
    false
  end

  # A Dynamic Component has the last word on its own size: whatever a transformation
  # sets, the DC engine recomputes lenx/leny/lenz from the component's formulas and
  # overwrites it. So a typed dimension that "does nothing" on a DC is usually the DC
  # throwing it away -- and when a formula cannot be parsed, SketchUp says so in the
  # console and then reverts in silence. This prints the formulas so the broken one is
  # visible instead of inferred.
  #
  # Nothing here writes: it reads dictionaries only.
  DC_DICT = "dynamic_attributes".freeze

  def self.dc
    sel = Sketchup.active_model.selection.to_a
    if sel.empty?
      puts "dc: chua chon gi"
      return false
    end
    puts "--- dc ---"
    sel.each do |entity|
      definition = safe_value { entity.definition }
      unless definition
        puts format("  %s: khong co definition -> khong phai DC", describe(entity))
        next
      end
      dicts = [["instance", entity], ["definition", definition]]
      unless dicts.any? { |(_where, holder)| dc_dict(holder) }
        puts format("  %s: khong co '%s' -> component thuong, KHONG phai Dynamic Component",
                    describe(entity), DC_DICT)
        next
      end
      puts format("  %s", describe(entity))
      dicts.each do |where, holder|
        dict = dc_dict(holder)
        next unless dict

        names = dict.keys.reject { |k| k.to_s.start_with?("_") }.sort
        puts format("    %s: %d thuoc tinh", where, names.length)
        names.each { |name| puts dc_line(dict, name) }
      end
    end
    true
  rescue StandardError => e
    puts "dc: #{e.class}: #{e.message}"
    puts (e.backtrace || []).first(4).map { |l| "    #{l}" }.join("\n")
    false
  end

  def self.dc_dict(holder)
    safe_value { holder.attribute_dictionaries && holder.attribute_dictionaries[DC_DICT] }
  end

  # DC keeps the value in `name` and the formula in `_name_formula`. A formula that
  # names a component with a space in it cannot be parsed -- DC identifiers have no
  # spaces -- and that is what "failed to parse ... inside <instance>.<attr>" means.
  def self.dc_line(dict, name)
    value = dict[name]
    formula = dict["_#{name}_formula"]
    note = ""
    if formula.to_s.length.positive?
      ref = formula.to_s[/([^\s!=+\-*\/()]+(?:\s+[^\s!=+\-*\/()]+)*)\s*!/, 1]
      note = "  <- ten '#{ref}' co DAU CACH, DC khong parse duoc" if ref && ref.include?(" ")
    end
    format("      %-12s = %-14s %s%s", name, value.inspect,
           formula.to_s.empty? ? "(khong co cong thuc)" : "cong thuc: #{formula}", note)
  end

  # Worth its own command: "no lines printed" has two completely different causes.
  # Either the hover path never ran at all -- the tool is not active, so neither
  # Overlay#dispatch_mouse nor SketchUp calls into it -- or it ran and decided the
  # same thing every time, which prints once. This tells the two apart.
  def self.stats
    overlay = P::PLUGIN.active_overlay
    tool = overlay && overlay.dim_scale
    puts format("update_hover calls=%d  tool=%s  active=%s  flag=%s  state=%s  pref=%s",
                @calls,
                (tool ? "yes" : "NO TOOL"),
                (tool ? tool.active?.to_s : "-"),
                (tool ? tool.instance_variable_get(:@active).inspect : "-"),
                (tool ? tool.instance_variable_get(:@tool_state).inspect : "-"),
                P.show_hover_dim?.to_s)
    true
  end

  def self.off
    @running = false
    true
  end
end
