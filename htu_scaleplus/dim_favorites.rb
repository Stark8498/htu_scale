module TRINH_VAN_PHUC::HTU_ScalePlus
  # Owns the saved-size list ("favorite dimensions") shown on a dimension's
  # context menu.
  #
  # The list is a machine-wide preference shared by every axis, every component
  # and every model. It used to be an attribute dictionary on the component,
  # which meant it lived inside the .skp: it survived only if the file was
  # saved, and a new model started empty. Standard sizes are a property of the
  # workshop, not of one cabinet, so they belong in preferences.
  #
  # Lengths are stored as inches, the unit SketchUp keeps internally, so a list
  # entered in a millimetre model still reads correctly in an inch one.
  module DimFavorites
    AXES = ["lenx", "leny", "lenz"].freeze

    # One list for all three axes. There used to be one per axis, on the theory
    # that cabinet depths should not turn up in the list of heights -- but the
    # sizes a workshop works to are the same handful whichever way round the
    # part is measured, and three separate lists meant typing each size three
    # times. The axis is still passed in everywhere, because everything except
    # storage genuinely is per axis.
    SHARED_KEY = :dims

    # The per-axis name: both the attribute older models keep the list in and
    # the preference key that came before SHARED_KEY. Nothing writes it any
    # more, it is only read once, to carry old values across.
    def self.attribute(axis)
      "#{axis}_dims"
    end

    def self.key(_axis = nil)
      SHARED_KEY
    end

    def self.definition_of(object)
      object.is_a?(Sketchup::ComponentDefinition) ? object : object.definition
    end

    # nil means the preference has never been written, which is what triggers
    # the one-time import below. An empty string means "written, and empty" --
    # a list the user emptied on purpose.
    def self.stored(axis)
      PLUGIN.settings[key(axis), nil]
    end

    def self.list(object, axis)
      unless AXES.include?(axis)
        return []
      end
      raw = stored(axis)
      if raw.nil?
        return adopt_legacy(object, axis)
      end
      decode(raw)
    rescue StandardError => e
      p(e)
      []
    end

    def self.decode(raw)
      raw.to_s.split(",").map { |n| n.to_f }.reject { |f| f <= 0 }.map(&:to_l).uniq.sort
    end

    # Single write path: everything is deduplicated and sorted here, so callers
    # never have to remember to do it.
    def self.write(_object, axis, values)
      unless AXES.include?(axis)
        return []
      end
      values = values.to_a.map(&:to_l).uniq.sort
      PLUGIN.settings[key(axis)] = values.map { |v| v.to_f }.join(",")
      values
    rescue StandardError => e
      p(e)
      []
    end

    # Carries across whatever the user already had, the first time the list is
    # asked for and has never been written. Without it, moving the storage would
    # simply lose what was saved before.
    #
    # Two places to look, and all three axes in each: the per-axis preferences
    # this replaces, and the attribute dictionary older models keep the list in.
    # Everything found is merged into the one list, which is the point -- a
    # depth of 560 saved on X is a size this workshop uses, whatever axis it
    # happened to be entered on.
    #
    # Keyed on "never written" rather than "currently empty": once the user has
    # touched the list, emptying it must stay empty instead of refilling from
    # the next old component they right-click.
    def self.adopt_legacy(object, _axis = nil)
      legacy = AXES.flat_map { |axis| legacy_values(object, axis) }
      if legacy.empty?
        return []
      end
      write(object, AXES.first, legacy)
    rescue StandardError => e
      p(e)
      []
    end

    def self.legacy_values(object, axis)
      values = decode(PLUGIN.settings[attribute(axis).to_sym, nil])
      unless object
        return values
      end
      values + definition_of(object).get_attribute(PLUGIN, attribute(axis), []).to_a.map(&:to_l)
    rescue StandardError => e
      p(e)
      []
    end

    def self.add(object, axis, values)
      write(object, axis, list(object, axis) + values.to_a)
    end

    def self.remove(object, axis, value)
      write(object, axis, list(object, axis).reject { |v| v == value })
    end

    def self.clear(object, axis)
      write(object, axis, [])
    end

    # "45, 200, 400" -> [[Length, ...], ["bad", ...]]
    #
    # Splits on comma, semicolon and newline so pasting a column of numbers
    # works too. String#to_l reads the model's current units and raises on
    # anything it cannot parse; a zero or negative length is meaningless for a
    # scale target, so it is reported as bad rather than silently dropped.
    def self.parse(text)
      good = []
      bad = []
      text.to_s.split(/[,;\n]/).each do |raw|
        entry = raw.strip
        if entry.empty?
          next
        end
        begin
          length = entry.to_l
          if length.to_f > 0
            good << length
          else
            bad << entry
          end
        rescue StandardError
          bad << entry
        end
      end
      [good.uniq.sort, bad]
    end
  end
end
