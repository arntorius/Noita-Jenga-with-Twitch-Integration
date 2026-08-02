-- JENGA charges for permanent Always Casts.
--
-- No actions are added or removed. Existing finite-use actions are wrapped
-- in place, so the Progress menu remains exactly vanilla.

local LOCK_TAG = "jenga_world_wand_spell"
local CHARGE_TRACKED = "jenga_charge_tracked"
local CHARGE_REMAINING = "jenga_charge_remaining"

local function find_storage(entity, name)
    if entity == nil or entity == 0 or not EntityGetIsAlive(entity) then
        return nil
    end

    for _, component in ipairs(
        EntityGetComponentIncludingDisabled(
            entity,
            "VariableStorageComponent"
        ) or {}
    ) do
        if ComponentGetValue2(component, "name") == name then
            return component
        end
    end

    return nil
end

local function get_int(entity, name, fallback)
    local component = find_storage(entity, name)

    if component == nil then
        return fallback
    end

    return ComponentGetValue2(component, "value_int") or fallback
end

local function set_int(entity, name, value)
    local component = find_storage(entity, name)

    if component == nil then
        EntityAddComponent2(
            entity,
            "VariableStorageComponent",
            {
                name = name,
                value_int = value,
            }
        )
    else
        ComponentSetValue2(component, "value_int", value)
    end
end

local function get_active_player_wand()
    for _, player in ipairs(
        EntityGetWithTag("player_unit") or {}
    ) do
        if EntityGetIsAlive(player) then
            local inventory =
                EntityGetFirstComponentIncludingDisabled(
                    player,
                    "Inventory2Component"
                )

            if inventory ~= nil then
                local active = ComponentGetValue2(
                    inventory,
                    "mActiveItem"
                ) or 0

                if active ~= 0
                    and EntityGetIsAlive(active)
                    and EntityHasTag(active, "wand")
                then
                    return active
                end
            end
        end
    end

    return 0
end

local function has_unlimited_spells()
    local world = GameGetWorldStateEntity()

    if world == nil or world == 0 then
        return false
    end

    local component =
        EntityGetFirstComponentIncludingDisabled(
            world,
            "WorldStateComponent"
        )

    if component == nil then
        return false
    end

    return ComponentGetValue2(
        component,
        "perk_infinite_spells"
    ) == true
end

local function get_action_id(spell)
    local component =
        EntityGetFirstComponentIncludingDisabled(
            spell,
            "ItemActionComponent"
        )

    if component == nil then
        return ""
    end

    return ComponentGetValue2(component, "action_id") or ""
end

local function collect_matching_spells(wand, action_id)
    local result = {}

    if wand == 0 or not EntityGetIsAlive(wand) then
        return result
    end

    for _, child in ipairs(EntityGetAllChildren(wand) or {}) do
        if EntityHasTag(child, LOCK_TAG)
            and get_action_id(child) == action_id
            and get_int(child, CHARGE_TRACKED, 0) == 1
        then
            table.insert(result, child)
        end
    end

    table.sort(result)
    return result
end

local invocation_state = {}
local action_execution_state = {}

local function select_spell_for_invocation(wand, action_id)
    local frame = GameGetFrameNum()
    local key = tostring(wand) .. ":" .. action_id
    local matches = collect_matching_spells(wand, action_id)

    if #matches == 0 then
        return 0
    end

    local state = invocation_state[key]

    if state == nil or state.frame ~= frame then
        state = {
            frame = frame,
            spell = 0,
        }

        invocation_state[key] = state
    end

    -- Reuse the same charged instance for all evaluations of this action
    -- during the current frame.
    if state.spell ~= nil
        and state.spell ~= 0
        and EntityGetIsAlive(state.spell)
        and get_int(
            state.spell,
            CHARGE_REMAINING,
            0
        ) > 0
    then
        return state.spell
    end

    -- Pick the first identical spell that still has charges. Once one copy
    -- reaches zero, subsequent casts automatically continue with the next.
    for _, spell in ipairs(matches) do
        if get_int(
            spell,
            CHARGE_REMAINING,
            0
        ) > 0
        then
            state.spell = spell
            return spell
        end
    end

    -- All identical copies are empty.
    state.spell = matches[1]
    return state.spell
end

local function should_execute_identical_action_once(
    wand,
    action_id
)
    local frame = GameGetFrameNum()
    local key = tostring(wand) .. ":" .. action_id
    local previous_frame = action_execution_state[key]

    if previous_frame == frame then
        return false
    end

    action_execution_state[key] = frame
    return true
end

for _, action in ipairs(actions or {}) do
    local maximum = tonumber(action.max_uses)

    if maximum ~= nil
        and maximum >= 0
        and type(action.action) == "function"
    then
        local action_id = action.id
        local original_action = action.action
        local never_unlimited = action.never_unlimited == true

        action.action = function()
            -- Noita evaluates actions in reflecting mode for wand rebuilds,
            -- inventory/tooltips and other metadata passes. Those evaluations
            -- are not real casts and must never consume JENGA charges.
            if reflecting == true then
                original_action()
                return
            end

            local wand = get_active_player_wand()
            local spell = select_spell_for_invocation(wand, action_id)

            -- Enemies, ordinary wands and non-JENGA spells stay vanilla.
            if spell == 0 then
                original_action()
                return
            end

            -- Multiple identical JENGA Always Cast entities may evaluate the
            -- same action during one wand shot. Treat them as one shared
            -- charge pool: execute and consume only once per wand/action/frame.
            if not should_execute_identical_action_once(
                wand,
                action_id
            ) then
                return
            end

            if has_unlimited_spells() and not never_unlimited then
                original_action()
                return
            end

            local remaining = get_int(
                spell,
                CHARGE_REMAINING,
                0
            )

            if remaining <= 0 then
                return
            end

            remaining = remaining - 1

            set_int(
                spell,
                CHARGE_REMAINING,
                remaining
            )

            local item_component =
                EntityGetFirstComponentIncludingDisabled(
                    spell,
                    "ItemComponent"
                )

            if item_component ~= nil then
                ComponentSetValue2(
                    item_component,
                    "uses_remaining",
                    remaining
                )
            end

            original_action()
        end
    end
end
