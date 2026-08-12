module TRINH_VAN_PHUC::HTU_ScalePlus
  # The axis lock, for a selection of more than one object.
  #
  # no_scale_mask lives on a ComponentDefinition, so it can only ever speak for
  # one object. Select two and SketchUp scales the union of their bounding
  # boxes -- a cage that belongs to no definition, so no mask governs it and all
  # 27 handles come back, silently undoing the mode the user picked on the
  # toolbar. main.rb#apply_behavior writes the mask onto every selected object
  # and it still looks like nothing happened, because the cage is not any of
  # them.
  #
  # So give the cage a definition of its own: wrap the selection in a group, put
  # the remembered mask on that group's definition, and let SketchUp's own Scale
  # tool take it from there. Handles, dragging, the VCB and inference all keep
  # working, because as far as SketchUp is concerned it is still the native tool
  # scaling one ordinary group. The wrapper is taken out again the moment the
  # user leaves the Scale tool.
  module GroupLock
    extend self

    # Stamped on the wrapper so a stray one can be recognised later by a session
    # that has forgotten it. Undo is why that is needed: the wrap is its own undo
    # step, so undoing past the scale puts the group back in the model with
    # nothing holding a reference to it. #sweep is what finds those.
    TEMP_DICT = "HTU_ScalePlus".freeze
    TEMP_KEY  = "temp_scale_group".freeze

    # The live wrapper, or nil. Never returns a deleted one: an undo can take it
    # out from under us at any moment, so every reader goes through here.
    def temp_group
      @temp_group = nil unless @temp_group && @temp_group.valid?
      @temp_group
    end

    # A deliberate round trip out of the Scale tool and straight back
    # (PLUGIN.repick_scale_tool, which is how a mask change is made visible) looks
    # exactly like the user leaving the tool. Unwrapping there would explode the
    # wrapper still under the cursor and cost two undo steps for one button press,
    # so the caller can mark its own trip. A real departure is unaffected.
    def suspend
      @suspended = true
      yield
    ensure
      @suspended = false
    end

    def suspended?
      @suspended ? true : false
    end

    # Deferred by a tick for the same reason ScalePP2Observer#apply_behavior is:
    # this edits the model, and an edit made from inside an observer callback can
    # land in the middle of whatever operation caused the callback.
    def tool_changed(tool_name)
      # Only the leaving half is suspended. The Scale tool coming back still wraps,
      # and #wrappable? refuses a second wrapper while one is live, so the round trip
      # leaves exactly what it found.
      return if suspended? && tool_name != "ScaleTool"

      model = Sketchup.active_model
      return unless model

      id = UI.start_timer(0, false) do
        UI.stop_timer(id)
        if tool_name == "ScaleTool"
          wrap(model)
        else
          unwrap(model)
        end
      end
    rescue StandardError => e
      p(e)
    end

    # Only a selection that is entirely groups and components, and more than one
    # of them.
    #
    # Raw geometry is left alone on purpose. Pulling faces and edges out of the
    # context they live in and pushing them back afterwards is not a reversible
    # operation -- edges reweld against whatever they now touch -- and the user
    # would get back a different model than the one they scaled. A mixed
    # selection is simply not wrapped; it scales with all 27 handles, which is
    # what it did before this file existed.
    def wrappable?(model)
      return false unless model && model.valid?
      return false if PLUGIN.behavior_state == BEHAVIOR_ALL
      return false if temp_group

      objects = model.selection.to_a
      return false if objects.length < 2

      objects.all? { |e| e.respond_to?(:definition) && e.valid? }
    end

    def wrap(model)
      # Strays first. One of them would also be sitting in the selection, which
      # makes #wrappable? false, and the model would then keep it forever.
      sweep(model)
      return nil unless wrappable?(model)

      group = build_wrapper(model)
      return nil unless group

      @temp_group = group
      # The Scale tool read its handles off the old selection and does not reliably
      # notice this one. PLUGIN.repick_scale_tool is the one way in this plugin that
      # reliably makes it look again -- a bare send_action is a no-op while the Scale
      # tool is already the active tool, which is exactly the bug the behaviour
      # buttons had. It fires onActiveToolChanged again, which comes back here, and
      # the #temp_group guard in #wrappable? is what stops a second wrapper.
      PLUGIN.repick_scale_tool
      group
    end

    def unwrap(model)
      return nil unless model && model.valid?

      group = temp_group
      remembered = @previous_selection || []
      @temp_group = nil
      @previous_selection = []

      unless group
        sweep(model)
        return nil
      end

      objects = explode_wrapper(model, group, remembered)
      # explode drops the selection. Putting the objects back is not a nicety:
      # the user still has them selected as far as they can tell, and the mask
      # each one carries has to be restored now that the wrapper holding it is
      # gone -- apply_behavior needs a selection to do that.
      unless objects.empty?
        model.selection.clear
        model.selection.add(objects)
        PLUGIN.apply_behavior(model.selection)
      end
      objects
    end

    # Any wrapper still in the model that nothing is holding on to. Runs before
    # a wrap and before a save, so the count can never grow past one and a .skp
    # can never be written with one inside it.
    #
    # Only the two contexts a wrapper can be made in are scanned, not the whole
    # model recursively: a wrapper is only ever created in the active context,
    # and this runs often enough that walking every definition would be felt.
    def sweep(model)
      return 0 unless model && model.valid?

      # The live wrapper looks exactly like a stray -- same stamp, same context --
      # so it has to be excluded by identity. Without this the re-pick of the
      # Scale tool comes back into #wrap, the sweep at the top of it eats the
      # wrapper that is currently under the user's cursor, and the selection is
      # left holding a deleted group.
      live = temp_group
      strays = contexts(model).flat_map { |ents| ents.select { |e| temp?(e) } }.uniq
      strays.delete(live) if live
      return 0 if strays.empty?

      model.start_operation("Scale Handles Cleanup", true)
      strays.each { |group| group.explode }
      model.commit_operation
      strays.size
    rescue StandardError => e
      p(e)
      abort_quietly(model)
      0
    end

    def temp?(entity)
      return false unless entity.is_a?(Sketchup::Group)
      return false unless entity.valid?

      entity.get_attribute(TEMP_DICT, TEMP_KEY, false) == true
    end

    private

    def contexts(model)
      [model.active_entities, model.entities].compact.uniq
    rescue StandardError
      []
    end

    # Kept apart from #wrap so the operation opens and closes in one place, with
    # nothing that can raise between the commit and the return.
    def build_wrapper(model)
      objects = model.selection.to_a
      @previous_selection = objects
      model.start_operation("Scale Handles Group", true)
      group = model.active_entities.add_group(objects)
      group.set_attribute(TEMP_DICT, TEMP_KEY, true)
      group.definition.behavior.no_scale_mask = PLUGIN.behavior_state
      model.selection.clear
      model.selection.add(group)
      model.commit_operation
      group
    rescue StandardError => e
      p(e)
      abort_quietly(model)
      @previous_selection = []
      nil
    end

    # explode's return value is the only reliable handle on the children: the
    # objects went into the group by reference, but SketchUp does not promise
    # those same references survive coming back out. The remembered selection is
    # the fallback, and it is filtered for validity because an undo may have
    # taken some of it away while the wrapper was live.
    def explode_wrapper(model, group, remembered)
      model.start_operation("Scale Handles Ungroup", true)
      exploded = group.explode || []
      model.commit_operation
      objects = exploded.select { |e| e.respond_to?(:definition) && e.valid? }
      return objects unless objects.empty?

      remembered.select { |e| e && e.valid? }
    rescue StandardError => e
      p(e)
      abort_quietly(model)
      remembered.select { |e| e && e.valid? }
    end

    def abort_quietly(model)
      model.abort_operation
    rescue StandardError
      nil
    end
  end
end
