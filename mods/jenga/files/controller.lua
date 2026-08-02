-- =========================================================
-- JENGA – Hauptcontroller
-- =========================================================

dofile_once("data/scripts/gun/gun_enums.lua")
dofile_once("data/scripts/gun/gun_actions.lua")

jenga_spell_selection_gui = jenga_spell_selection_gui or nil
jenga_pinned_wand_gui = jenga_pinned_wand_gui or nil
jenga_pinned_wand_entity = jenga_pinned_wand_entity or 0
jenga_charge_display_gui = jenga_charge_display_gui or nil
jenga_charge_display_error_shown = jenga_charge_display_error_shown or false

local controller = GetUpdatedEntityID()

if controller == nil or controller == 0 then
    return
end

local player = EntityGetParent(controller)

if player == nil
    or player == 0
    or not EntityGetIsAlive(player)
then
    return
end

-- =========================================================
-- Konfiguration
-- =========================================================

local MAX_WAND_SLOTS = 4

-- Abstand, in dem ein Drop als Ablage am JENGA-Stapel gilt.
local STACK_USE_RADIUS = 100

-- Horizontal position of every JENGA stack.
local STACK_BASE_X = -680

-- Exact Y coordinates for Holy Mountains 1 through 6.
-- The final Holy Mountain is intentionally excluded.
local JENGA_MOUNTAIN_Y = {
    1418,  -- HM 1
    2954,  -- HM 2
    5002,  -- HM 3
    6538,  -- HM 4
    8586,  -- HM 5
    10634, -- HM 6
}

local JENGA_MOUNTAIN_COUNT = #JENGA_MOUNTAIN_Y

-- Wie nahe der Spieler an der vorgesehenen Position sein muss,
-- bevor der Sockel geladen wird.
local STACK_SPAWN_DISTANCE_X = 700
local STACK_SPAWN_DISTANCE_Y = 500

-- Wie lange JENGA versucht, einen asynchronen Inventartausch
-- fertigzustellen.
local MAX_PENDING_FRAMES = 30

-- Awakening chance uses get_stack_awakening_chance().
local GHOST_SPAWN_RADIUS = 34

-- =========================================================
-- Speicherbezeichnungen
-- =========================================================

local STORAGE_INITIALIZED = "jenga_initialized"
local STORAGE_ZONE_PREFIX = "jenga_stack_zone_spawned_"
local STORAGE_PREVIOUS_PREFIX = "jenga_previous_wand_"

local STORAGE_PENDING_STATE = "jenga_pending_state"
local STORAGE_PENDING_OLD_WAND = "jenga_pending_old_wand"
local STORAGE_PENDING_DONOR_WAND = "jenga_pending_donor_wand"
local STORAGE_PENDING_FRAMES = "jenga_pending_frames"

local STORAGE_SELECTION_ACTIVE = "jenga_selection_active"
local STORAGE_SELECTION_DONOR = "jenga_selection_donor"
local STORAGE_SELECTION_TARGET = "jenga_selection_target"
local STORAGE_SELECTION_TYPE = "jenga_selection_type"
local STORAGE_SELECTION_SPELL = "jenga_selection_spell"
local STORAGE_TWITCH_PENDING_CONFIRM = "jenga_twitch_pending_confirm"
local STORAGE_TWITCH_VOTE_ID =
    "jenga_twitch_vote_id_local"

local STORAGE_TWITCH_STARTED_AT =
    "jenga_twitch_started_at"

local TWITCH_VOTE_DURATION = 30

local TWITCH_BRIDGE_CONNECTED =
    "jenga_twitch_bridge_connected"

local TWITCH_COMMAND =
    "jenga_twitch_command"

local TWITCH_COMMAND_SERIAL =
    "jenga_twitch_command_serial"

local TWITCH_STATE_VOTE_ID =
    "jenga_twitch_state_vote_id"

local TWITCH_STATE_STATUS =
    "jenga_twitch_state_status"

local TWITCH_STATE_REMAINING =
    "jenga_twitch_state_remaining"

local TWITCH_STATE_VOTES =
    "jenga_twitch_state_votes"

local TWITCH_STATE_WINNER =
    "jenga_twitch_state_winner"
local SELECTION_PICKUP_LOCK_TAG = "jenga_selection_pickup_locked"

local SELECTION_NONE = 0
local SELECTION_TRANSFER = 1
local SELECTION_KEEP_WAND = 2

-- Zustände:
--
-- 0 = kein Vorgang
-- 1 = erfolgreicher Transfer; alten Stab wieder aufnehmen,
--     danach Spenderstab löschen
-- 2 = abgebrochener Transfer; alten Stab wieder aufnehmen,
--     Spenderstab auf dem Boden lassen

local PENDING_NONE = 0

-- Spender wurde gelöscht. Alter Stab muss wieder aufgenommen werden.
local PENDING_RESTORE_AFTER_SUCCESS = 1

-- Spender wurde aus dem Inventar auf den Boden gelegt.
-- Alter Stab muss wieder aufgenommen werden.
local PENDING_RESTORE_AFTER_CANCEL = 2

-- =========================================================
-- Allgemeine Hilfsfunktionen
-- =========================================================

local function is_alive(entity)
    return entity ~= nil
        and entity ~= 0
        and EntityGetIsAlive(entity)
end

local function contains_text(value, search)
    if value == nil then
        return false
    end

    value = string.lower(tostring(value))
    search = string.lower(tostring(search))

    return string.find(value, search, 1, true) ~= nil
end

local function distance_squared(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1

    return dx * dx + dy * dy
end

local function get_gameplay_mode()
    local mode = ModSettingGet("jenga.mode")

    if mode == "normal" then
        return "normal"
    elseif mode == "twitch" then
        return "twitch"
    end

    return "random"
end

-- =========================================================
-- VariableStorageComponent
-- =========================================================

local function find_storage(name)
    local components = EntityGetComponentIncludingDisabled(
        controller,
        "VariableStorageComponent"
    ) or {}

    for _, component in ipairs(components) do
        if ComponentGetValue2(component, "name") == name then
            return component
        end
    end

    return nil
end

local function get_or_create_storage(name)
    local component = find_storage(name)

    if component ~= nil then
        return component
    end

    return EntityAddComponent2(
        controller,
        "VariableStorageComponent",
        {
            name = name,
            value_int = 0,
            value_bool = false,
            value_string = "",
            value_float = 0.0,
        }
    )
end

local function get_int(name)
    local component = get_or_create_storage(name)
    return ComponentGetValue2(component, "value_int") or 0
end

local function set_int(name, value)
    local component = get_or_create_storage(name)

    ComponentSetValue2(
        component,
        "value_int",
        tonumber(value) or 0
    )
end

local function get_bool(name)
    local component = get_or_create_storage(name)
    return ComponentGetValue2(component, "value_bool") == true
end

local function set_bool(name, value)
    local component = get_or_create_storage(name)

    ComponentSetValue2(
        component,
        "value_bool",
        value == true
    )
end

local function get_float(name)
    local component = get_or_create_storage(name)
    return ComponentGetValue2(component, "value_float") or 0.0
end

local function set_float(name, value)
    local component = get_or_create_storage(name)

    ComponentSetValue2(
        component,
        "value_float",
        tonumber(value) or 0.0
    )
end

local function get_string(name)
    local component = get_or_create_storage(name)

    return ComponentGetValue2(
        component,
        "value_string"
    ) or ""
end

local function set_string(name, value)
    local component = get_or_create_storage(name)

    ComponentSetValue2(
        component,
        "value_string",
        tostring(value or "")
    )
end

-- =========================================================
-- Inventarfunktionen
-- =========================================================

local function get_inventory_quick()
    local children = EntityGetAllChildren(player) or {}

    for _, child in ipairs(children) do
        if EntityGetName(child) == "inventory_quick" then
            return child
        end
    end

    return nil
end

local function is_wand(entity)
    if not is_alive(entity) then
        return false
    end

    if EntityHasTag(entity, "wand") then
        return true
    end

    local ability = EntityGetFirstComponentIncludingDisabled(
        entity,
        "AbilityComponent"
    )

    if ability == nil then
        return false
    end

    local use_gun_script = ComponentGetValue2(
        ability,
        "use_gun_script"
    )

    return use_gun_script == true
end

local function get_item_component(entity)
    if not is_alive(entity) then
        return nil
    end

    return EntityGetFirstComponentIncludingDisabled(
        entity,
        "ItemComponent"
    )
end

local function get_item_slot(entity)
    local item_component = get_item_component(entity)

    if item_component == nil then
        return -1, -1
    end

    local slot_x, slot_y = ComponentGetValue2(
        item_component,
        "inventory_slot"
    )

    return slot_x or -1, slot_y or -1
end

local function set_item_slot(entity, slot_x, slot_y)
    local item_component = get_item_component(entity)

    if item_component == nil then
        return
    end

    ComponentSetValue2(
        item_component,
        "inventory_slot",
        slot_x,
        slot_y
    )
end

local function get_inventory_wands()
    local result = {}
    local inventory = get_inventory_quick()

    if inventory == nil then
        return result
    end

    local children = EntityGetAllChildren(inventory) or {}

    for _, child in ipairs(children) do
        if is_wand(child) then
            local slot_x, slot_y = get_item_slot(child)

            table.insert(
                result,
                {
                    entity = child,
                    slot_x = slot_x,
                    slot_y = slot_y,
                }
            )
        end
    end

    table.sort(
        result,
        function(a, b)
            if a.slot_y == b.slot_y then
                return a.slot_x < b.slot_x
            end

            return a.slot_y < b.slot_y
        end
    )

    return result
end

local function inventory_contains_entity(entity)
    if not is_alive(entity) then
        return false
    end

    local inventory = get_inventory_quick()

    if inventory == nil then
        return false
    end

    return EntityGetParent(entity) == inventory
end

local function make_wand_owned(wand)
    if not is_alive(wand) then
        return
    end

    EntityAddTag(wand, "jenga_owned_wand")
end

local function set_wand_pickable(wand, pickable)
    if not is_alive(wand) then
        return false
    end

    local item_component = get_item_component(wand)

    if item_component == nil then
        return false
    end

    ComponentSetValue2(
        item_component,
        "is_pickable",
        pickable == true
    )

    return true
end

-- =========================================================
-- Zauberfunktionen
-- =========================================================

local function get_action_component(entity)
    if not is_alive(entity) then
        return nil
    end

    return EntityGetFirstComponentIncludingDisabled(
        entity,
        "ItemActionComponent"
    )
end

local function is_spell_entity(entity)
    return get_action_component(entity) ~= nil
end

local function is_always_cast(entity)
    if not is_spell_entity(entity) then
        return false
    end

    local item_component = get_item_component(entity)

    if item_component == nil then
        return false
    end

    return ComponentGetValue2(
        item_component,
        "permanently_attached"
    ) == true
end

local function is_normal_spell(entity)
    return is_spell_entity(entity)
        and not is_always_cast(entity)
end

local function get_normal_spells(wand)
    local result = {}

    if not is_alive(wand) then
        return result
    end

    local children = EntityGetAllChildren(wand) or {}

    for _, child in ipairs(children) do
        if is_normal_spell(child) then
            local slot_x, slot_y = get_item_slot(child)

            table.insert(
                result,
                {
                    entity = child,
                    slot_x = slot_x,
                    slot_y = slot_y,
                }
            )
        end
    end

    table.sort(
        result,
        function(a, b)
            if a.slot_y == b.slot_y then
                return a.slot_x < b.slot_x
            end

            return a.slot_y < b.slot_y
        end
    )

    return result
end

-- =========================================================
-- Restricted wand editing
--
-- Existing normal spells on player-owned wands are locked to their
-- current wand and slot. Loose inventory spells remain editable and may
-- only be inserted into currently empty wand slots.
-- =========================================================

local SPELL_LOCK_TAG = "jenga_world_wand_spell"
local SPELL_LOCK_WAND = "jenga_locked_wand_id"
local SPELL_LOCK_SLOT_X = "jenga_locked_wand_slot_x"
local SPELL_LOCK_SLOT_Y = "jenga_locked_wand_slot_y"
local SPELL_CHARGE_TRACKED =
    "jenga_charge_tracked"

local SPELL_CHARGE_REMAINING =
    "jenga_charge_remaining"

local SPELL_CHARGE_MAX =
    "jenga_charge_max"

local function get_entity_storage_component(entity, name)
    if not is_alive(entity) then
        return nil
    end

    local components = EntityGetComponentIncludingDisabled(
        entity,
        "VariableStorageComponent"
    ) or {}

    for _, component in ipairs(components) do
        if ComponentGetValue2(component, "name") == name then
            return component
        end
    end

    return nil
end

local function set_entity_storage_int(entity, name, value)
    local component = get_entity_storage_component(
        entity,
        name
    )

    if component == nil then
        EntityAddComponent2(
            entity,
            "VariableStorageComponent",
            {
                name = name,
                value_int = tonumber(value) or 0,
            }
        )
    else
        ComponentSetValue2(
            component,
            "value_int",
            tonumber(value) or 0
        )
    end
end

local function get_entity_storage_int(entity, name)
    local component = get_entity_storage_component(
        entity,
        name
    )

    if component == nil then
        return 0
    end

    return ComponentGetValue2(
        component,
        "value_int"
    ) or 0
end

local function remove_entity_storage(entity, name)
    local component = get_entity_storage_component(
        entity,
        name
    )

    if component ~= nil then
        EntityRemoveComponent(entity, component)
    end
end

local function get_charge_action_definition(spell)
    local component =
        EntityGetFirstComponentIncludingDisabled(
            spell,
            "ItemActionComponent"
        )

    if component == nil then
        return nil
    end

    local action_id = ComponentGetValue2(
        component,
        "action_id"
    ) or ""

    for _, action in ipairs(actions or {}) do
        if action.id == action_id then
            return action
        end
    end

    return nil
end

local function capture_spell_charge_state(spell)
    if not is_alive(spell) then
        return
    end

    local action = get_charge_action_definition(spell)

    if action == nil then
        return
    end

    local maximum = tonumber(action.max_uses)

    if maximum == nil or maximum < 0 then
        set_entity_storage_int(
            spell,
            SPELL_CHARGE_TRACKED,
            0
        )

        return
    end

    local remaining = maximum
    local item_component = get_item_component(spell)

    if item_component ~= nil then
        local native_remaining = tonumber(
            ComponentGetValue2(
                item_component,
                "uses_remaining"
            )
        )

        if native_remaining ~= nil
            and native_remaining >= 0
        then
            remaining = native_remaining
        end
    end

    set_entity_storage_int(
        spell,
        SPELL_CHARGE_TRACKED,
        1
    )

    set_entity_storage_int(
        spell,
        SPELL_CHARGE_REMAINING,
        remaining
    )

    set_entity_storage_int(
        spell,
        SPELL_CHARGE_MAX,
        maximum
    )
end

JENGA_INTERNAL =
    JENGA_INTERNAL or {}

function JENGA_INTERNAL.regen_item_actions_preserving_charges(wand)
    if not is_alive(wand) then
        return
    end

    local snapshots = {}

    for _, spell in ipairs(
        EntityGetAllChildren(wand) or {}
    ) do
        if EntityHasTag(
            spell,
            SPELL_LOCK_TAG
        )
            and get_entity_storage_int(
                spell,
                SPELL_CHARGE_TRACKED
            ) == 1
        then
            table.insert(
                snapshots,
                {
                    spell = spell,
                    remaining =
                        get_entity_storage_int(
                            spell,
                            SPELL_CHARGE_REMAINING
                        ),
                }
            )
        end
    end

    GameRegenItemActionsInContainer(wand)

    -- GameRegenItemActionsInContainer may restore ItemComponent
    -- uses_remaining to the action maximum. JENGA's stored remaining value is
    -- authoritative for this internal rebuild, so put it back immediately.
    for _, snapshot in ipairs(snapshots) do
        local spell = snapshot.spell

        if is_alive(spell) then
            local remaining =
                math.max(
                    0,
                    tonumber(
                        snapshot.remaining
                    ) or 0
                )

            set_entity_storage_int(
                spell,
                SPELL_CHARGE_REMAINING,
                remaining
            )

            local item_component =
                get_item_component(spell)

            if item_component ~= nil then
                pcall(
                    ComponentSetValue2,
                    item_component,
                    "uses_remaining",
                    remaining
                )
            end
        end
    end
end

local function synchronize_spell_refresher_charges()
    for _, spell in ipairs(
        EntityGetWithTag(SPELL_LOCK_TAG) or {}
    ) do
        if is_alive(spell)
            and get_entity_storage_int(
                spell,
                SPELL_CHARGE_TRACKED
            ) == 1
        then
            local item_component = get_item_component(spell)

            if item_component ~= nil then
                local native_remaining = tonumber(
                    ComponentGetValue2(
                        item_component,
                        "uses_remaining"
                    )
                )

                local stored =
                    get_entity_storage_int(
                        spell,
                        SPELL_CHARGE_REMAINING
                    )

                local maximum =
                    get_entity_storage_int(
                        spell,
                        SPELL_CHARGE_MAX
                    )

                if native_remaining ~= nil
                    and native_remaining >= 0
                    and native_remaining > stored
                then
                    set_entity_storage_int(
                        spell,
                        SPELL_CHARGE_REMAINING,
                        math.min(native_remaining, maximum)
                    )
                end
            end
        end
    end
end

local function set_spell_locked(spell, locked)
    local item_component = get_item_component(spell)

    if item_component == nil then
        return
    end

    ComponentSetValue2(
        item_component,
        "is_frozen",
        locked == true
    )

    ComponentSetValue2(
        item_component,
        "is_pickable",
        locked ~= true
    )

    -- Permanent native Always Cast. This value is never toggled when
    -- opening or closing the inventory, preventing Noita from rebuilding
    -- and shifting the normal spell deck on every inventory open.
    ComponentSetValue2(
        item_component,
        "permanently_attached",
        locked == true
    )
end

local function lock_spell_to_wand(
    spell,
    wand,
    slot_x,
    slot_y
)
    if not is_alive(spell)
        or not is_alive(wand)
        or not is_normal_spell(spell)
    then
        return
    end

    -- This tag is only applied to a spell originating from a
    -- JENGA-processed world wand.
    EntityAddTag(spell, SPELL_LOCK_TAG)

    set_entity_storage_int(
        spell,
        SPELL_LOCK_WAND,
        wand
    )

    set_entity_storage_int(
        spell,
        SPELL_LOCK_SLOT_X,
        slot_x
    )

    set_entity_storage_int(
        spell,
        SPELL_LOCK_SLOT_Y,
        slot_y
    )

    capture_spell_charge_state(spell)
    set_spell_locked(spell, true)
end

local function unlock_spell(spell)
    if not is_alive(spell) then
        return
    end

    EntityRemoveTag(spell, SPELL_LOCK_TAG)

    remove_entity_storage(spell, SPELL_LOCK_WAND)
    remove_entity_storage(spell, SPELL_LOCK_SLOT_X)
    remove_entity_storage(spell, SPELL_LOCK_SLOT_Y)

    set_spell_locked(spell, false)
end

local function restore_locked_spell(spell)
    if not is_alive(spell) then
        return
    end

    local wand = get_entity_storage_int(
        spell,
        SPELL_LOCK_WAND
    )

    local slot_x = get_entity_storage_int(
        spell,
        SPELL_LOCK_SLOT_X
    )

    local slot_y = get_entity_storage_int(
        spell,
        SPELL_LOCK_SLOT_Y
    )

    if not is_alive(wand) then
        unlock_spell(spell)
        return
    end

    -- Keep world-wand spells locked even while the wand is temporarily
    -- outside the inventory, for example during JENGA replacement logic.
    local changed = false

    if EntityGetParent(spell) ~= wand then
        EntityRemoveFromParent(spell)
        EntityAddChild(wand, spell)
        changed = true
    end

    local current_x, current_y = get_item_slot(spell)

    if current_x ~= slot_x or current_y ~= slot_y then
        set_item_slot(
            spell,
            slot_x,
            slot_y
        )
        changed = true
    end

    -- Reapply the restrictions every frame. While the inventory is open,
    -- permanently_attached prevents even the visual drag operation. When it
    -- closes, that temporary flag is removed again.
    set_spell_locked(spell, true)

    if changed then
        JENGA_INTERNAL.regen_item_actions_preserving_charges(wand)
    end
end

local function update_wand_spell_locks()
    -- Only spells explicitly created or transferred by JENGA from a
    -- world wand carry SPELL_LOCK_TAG. Those spells are restored to
    -- their original wand and exact slot every frame.
    --
    -- Ordinary loose inventory spells and spells the player inserts
    -- manually are intentionally not tagged and remain movable.
    local locked_spells = EntityGetWithTag(
        SPELL_LOCK_TAG
    ) or {}

    for _, spell in ipairs(locked_spells) do
        restore_locked_spell(spell)
    end
end

local function choose_random_normal_spell(wand)
    local spells = get_normal_spells(wand)

    if #spells == 0 then
        return nil
    end

    local x, y = EntityGetTransform(wand)
    local frame = GameGetFrameNum()

    SetRandomSeed(
        math.floor(x + frame),
        math.floor(y + wand + frame * 7)
    )

    local index = Random(1, #spells)

    return spells[index].entity
end

local function trim_wand_to_one_random_spell(wand)
    local keep = choose_random_normal_spell(wand)

    if keep == nil then
        return false
    end

    local spells = get_normal_spells(wand)

    for _, spell_data in ipairs(spells) do
        if spell_data.entity ~= keep then
            EntityKill(spell_data.entity)
        end
    end

    local keep_slot_x, keep_slot_y = get_item_slot(keep)

    lock_spell_to_wand(
        keep,
        wand,
        keep_slot_x,
        keep_slot_y
    )

    JENGA_INTERNAL.regen_item_actions_preserving_charges(wand)

    return true
end

local function trim_wand_to_selected_spell(wand, selected_spell)
    if not is_alive(wand) or not is_alive(selected_spell) then
        return false
    end

    local found = false
    local spells = get_normal_spells(wand)

    for _, spell_data in ipairs(spells) do
        if spell_data.entity == selected_spell then
            found = true
        else
            EntityKill(spell_data.entity)
        end
    end

    if not found then
        return false
    end

    local selected_slot_x, selected_slot_y =
        get_item_slot(selected_spell)

    lock_spell_to_wand(
        selected_spell,
        wand,
        selected_slot_x,
        selected_slot_y
    )

    JENGA_INTERNAL.regen_item_actions_preserving_charges(wand)
    return true
end

local function get_spell_action_id(spell)
    local component = get_action_component(spell)
    if component == nil then return "" end
    return ComponentGetValue2(component, "action_id") or ""
end

local function get_action_definition(action_id)
    if action_id == nil or action_id == "" or actions == nil then
        return nil
    end

    for _, action in ipairs(actions) do
        if action.id == action_id then
            return action
        end
    end

    return nil
end

local function get_spell_icon(spell)
    local action = get_action_definition(get_spell_action_id(spell))
    if action ~= nil and action.sprite ~= nil and action.sprite ~= "" then
        return action.sprite
    end

    local sprites = EntityGetComponentIncludingDisabled(spell, "SpriteComponent") or {}
    for _, component in ipairs(sprites) do
        local image = ComponentGetValue2(component, "image_file")
        if image ~= nil and image ~= "" then return image end
    end

    return "data/ui_gfx/inventory/icon_unknown.png"
end

local function get_spell_display_name(spell)
    local action = get_action_definition(get_spell_action_id(spell))
    if action ~= nil and action.name ~= nil then
        return GameTextGetTranslatedOrNot(action.name)
    end

    return get_spell_action_id(spell)
end

local function get_wand_capacity(wand)
    if not is_alive(wand) then
        return 0
    end

    local ability = EntityGetFirstComponentIncludingDisabled(
        wand,
        "AbilityComponent"
    )

    if ability == nil then
        return 0
    end

    local capacity = ComponentObjectGetValue2(
        ability,
        "gun_config",
        "deck_capacity"
    )

    return tonumber(capacity) or 0
end

local function get_first_free_spell_slot(wand)
    local capacity = get_wand_capacity(wand)

    if capacity <= 0 then
        return nil
    end

    local occupied = {}

    for _, child in ipairs(EntityGetAllChildren(wand) or {}) do
        if EntityHasTag(child, SPELL_LOCK_TAG) then
            local stored_slot = get_entity_storage_int(
                child,
                SPELL_LOCK_SLOT_X
            )

            if stored_slot >= 0 then
                occupied[stored_slot] = true
            end
        elseif is_normal_spell(child) then
            local slot_x = get_item_slot(child)

            if slot_x >= 0 then
                occupied[slot_x] = true
            end
        end
    end

    for slot = 0, capacity - 1 do
        if not occupied[slot] then
            return slot
        end
    end

    return nil
end

local function clear_normal_spell_slot(wand, slot_x)
    if not is_alive(wand) then
        return false
    end

    local removed_any = false
    local children = EntityGetAllChildren(wand) or {}

    for _, child in ipairs(children) do
        if is_normal_spell(child)
            and not EntityHasTag(child, SPELL_LOCK_TAG)
        then
            local child_slot_x = get_item_slot(child)

            if child_slot_x == slot_x then
                EntityKill(child)
                removed_any = true
            end
        end
    end

    if removed_any then
        JENGA_INTERNAL.regen_item_actions_preserving_charges(wand)
    end

    return removed_any
end

local function get_transfer_spell_slot(wand)
    local free_slot = get_first_free_spell_slot(wand)

    if free_slot ~= nil then
        return free_slot, false
    end

    -- Full wand: do not overwrite any existing spell.
    return nil, false
end

local function transfer_random_spell(donor_wand, target_wand)
    if not is_alive(donor_wand)
        or not is_alive(target_wand)
    then
        return false
    end

    local target_slot, overwrite =
        get_transfer_spell_slot(target_wand)

    if target_slot == nil then
        return false
    end

    local spell = choose_random_normal_spell(donor_wand)

    if spell == nil then
        return false
    end

    if overwrite then
        clear_normal_spell_slot(
            target_wand,
            target_slot
        )
    end

    EntityRemoveFromParent(spell)
    EntityAddChild(target_wand, spell)
    set_item_slot(spell, target_slot, 0)

    lock_spell_to_wand(
        spell,
        target_wand,
        target_slot,
        0
    )

    JENGA_INTERNAL.regen_item_actions_preserving_charges(target_wand)

    return true
end

local function transfer_selected_spell(donor_wand, target_wand, spell)
    if not is_alive(donor_wand)
        or not is_alive(target_wand)
        or not is_alive(spell)
        or EntityGetParent(spell) ~= donor_wand
        or not is_normal_spell(spell)
    then
        return false
    end

    local target_slot, overwrite = get_transfer_spell_slot(target_wand)
    if target_slot == nil then return false end

    if overwrite then
        clear_normal_spell_slot(target_wand, target_slot)
    end

    EntityRemoveFromParent(spell)
    EntityAddChild(target_wand, spell)
    set_item_slot(spell, target_slot, 0)

    lock_spell_to_wand(
        spell,
        target_wand,
        target_slot,
        0
    )

    JENGA_INTERNAL.regen_item_actions_preserving_charges(target_wand)

    return true
end

-- =========================================================
-- Inventar-Snapshots
-- =========================================================

local function save_current_wands(wands)
    for index = 1, MAX_WAND_SLOTS do
        local entity = 0

        if wands[index] ~= nil then
            entity = wands[index].entity
        end

        set_int(
            STORAGE_PREVIOUS_PREFIX .. tostring(index),
            entity
        )
    end
end

local function load_previous_wands()
    local result = {}

    for index = 1, MAX_WAND_SLOTS do
        local entity = get_int(
            STORAGE_PREVIOUS_PREFIX .. tostring(index)
        )

        if entity ~= 0 then
            result[index] = entity
        end
    end

    return result
end

local function count_entries(values)
    local count = 0

    for _, _ in pairs(values) do
        count = count + 1
    end

    return count
end

local function current_wand_set(current)
    local result = {}

    for _, wand_data in ipairs(current) do
        result[wand_data.entity] = true
    end

    return result
end

local function previous_wand_set(previous)
    local result = {}

    for _, entity in pairs(previous) do
        result[entity] = true
    end

    return result
end

local function find_added_wand(previous, current)
    local old_set = previous_wand_set(previous)

    for _, wand_data in ipairs(current) do
        if not old_set[wand_data.entity] then
            return wand_data
        end
    end

    return nil
end

local function find_removed_wands(previous, current)
    local result = {}
    local new_set = current_wand_set(current)

    for _, entity in pairs(previous) do
        if not new_set[entity] then
            table.insert(result, entity)
        end
    end

    return result
end

local function find_single_removed_wand(previous, current)
    local removed = find_removed_wands(previous, current)

    if #removed == 1 then
        return removed[1]
    end

    return nil
end

-- =========================================================
-- Holy-Mountain- und Stapelzone
-- =========================================================


local function get_nearest_stack_zone(
    origin_x,
    origin_y,
    radius
)
    local zones = EntityGetInRadiusWithTag(
        origin_x,
        origin_y,
        radius,
        "jenga_stack_zone"
    ) or {}

    local nearest = nil
    local nearest_distance = nil

    for _, zone in ipairs(zones) do
        if is_alive(zone) then
            local zone_x, zone_y = EntityGetTransform(zone)

            local distance = distance_squared(
                origin_x,
                origin_y,
                zone_x,
                zone_y
            )

            if nearest == nil
                or distance < nearest_distance
            then
                nearest = zone
                nearest_distance = distance
            end
        end
    end

    return nearest
end

local function get_stack_zone_near_player()
    local x, y = EntityGetTransform(player)

    return get_nearest_stack_zone(
        x,
        y,
        STACK_USE_RADIUS
    )
end

local function get_parallel_world_offset(x)
    -- Die Hauptwelt ist ungefähr 35840 Pixel breit.
    -- Dadurch funktioniert die Position auch in Parallelwelten.
    local world_width = 35840

    if x >= 0 then
        return math.floor((x + world_width * 0.5) / world_width)
            * world_width
    end

    return math.ceil((x - world_width * 0.5) / world_width)
        * world_width
end

local function get_stack_position(mountain_index, world_offset)
    local x = STACK_BASE_X + world_offset

    -- mountain_index is zero-based in the spawning loop.
    local y = JENGA_MOUNTAIN_Y[mountain_index + 1]

    return x, y
end

local function zone_exists_near(x, y)
    local zones = EntityGetInRadiusWithTag(
        x,
        y,
        100,
        "jenga_stack_zone"
    ) or {}

    for _, zone in ipairs(zones) do
        if is_alive(zone) then
            return true
        end
    end

    return false
end

local function get_zone_storage_name(
    mountain_index,
    world_offset
)
    return STORAGE_ZONE_PREFIX
        .. tostring(world_offset)
        .. "_"
        .. tostring(mountain_index)
end

local function try_spawn_holy_mountain_stack_zone()
    local player_x, player_y = EntityGetTransform(player)

    local world_offset =
        get_parallel_world_offset(player_x)

    for mountain_index = 0, JENGA_MOUNTAIN_COUNT - 1 do
        local zone_x, zone_y = get_stack_position(
            mountain_index,
            world_offset
        )

        local close_enough_x =
            math.abs(player_x - zone_x)
            <= STACK_SPAWN_DISTANCE_X

        local close_enough_y =
            math.abs(player_y - zone_y)
            <= STACK_SPAWN_DISTANCE_Y

        if close_enough_x and close_enough_y then
            local storage_name = get_zone_storage_name(
                mountain_index,
                world_offset
            )

            local already_spawned =
                get_bool(storage_name)

            if not already_spawned then
                if zone_exists_near(zone_x, zone_y) then
                    set_bool(storage_name, true)
                    return
                end

                local zone = EntityLoad(
                    "mods/jenga/files/stack_zone.xml",
                    zone_x,
                    zone_y
                )

                if zone ~= nil and zone ~= 0 then
                    set_bool(storage_name, true)

                    GamePrint(
                        "JENGA: Wand stack created."
                    )
                else
                    GamePrint(
                        "JENGA: Wand stack could not be created."
                    )
                end
            end

            return
        end
    end
end


local function get_stacked_wands_for_zone(zone)
    local result = {}
    if not is_alive(zone) then return result end
    local zone_x, zone_y = EntityGetTransform(zone)
    local nearby = EntityGetInRadiusWithTag(zone_x, zone_y, 140, "jenga_stacked_wand") or {}
    for _, wand in ipairs(nearby) do
        if is_alive(wand) then table.insert(result, wand) end
    end
    table.sort(result, function(a,b) return a < b end)
    return result
end

local function return_stacked_wand_to_zone(wand)
    if not is_alive(wand) then
        return false
    end

    remove_wand_from_inventory(wand)

    local home_x, home_y = get_wand_stack_home(wand)

    if home_x == nil or home_y == nil then
        local wand_x, wand_y = EntityGetTransform(wand)

        local zone = get_nearest_stack_zone(
            wand_x,
            wand_y,
            1200
        )

        if zone == nil then
            local player_x, player_y = EntityGetTransform(player)

            zone = get_nearest_stack_zone(
                player_x,
                player_y,
                1200
            )
        end

        if zone == nil then
            return false
        end

        home_x, home_y = EntityGetTransform(zone)
    end

    EntitySetTransform(
        wand,
        home_x,
        home_y
    )

    local velocity = EntityGetFirstComponentIncludingDisabled(
        wand,
        "VelocityComponent"
    )

    if velocity ~= nil then
        ComponentSetValue2(
            velocity,
            "mVelocity",
            0,
            0
        )
    end

    return true
end

local function spawn_wand_ghost_for_wand(
    wand,
    zone,
    index,
    total
)
    if not is_alive(wand) or not is_alive(zone) then
        return false
    end

    local zone_x, zone_y = EntityGetTransform(zone)

    local angle =
        ((index - 1) / math.max(total, 1))
        * math.pi
        * 2

    local spawn_x =
        zone_x + math.cos(angle) * GHOST_SPAWN_RADIUS

    local spawn_y =
        zone_y - 24 + math.sin(angle) * GHOST_SPAWN_RADIUS

    -- Der Stab bleibt bis zur erfolgreichen Übergabe gesperrt.
    EntityRemoveTag(wand, "jenga_stacked_wand")
    EntityAddTag(wand, "jenga_ghost_pending_wand")
    set_wand_pickable(wand, false)

    EntitySetTransform(
        wand,
        spawn_x,
        spawn_y
    )

    local ghost = EntityLoad(
        "mods/jenga/files/enemies/jenga_wand_ghost.xml",
        spawn_x,
        spawn_y
    )

    if not is_alive(ghost) then
        EntityRemoveTag(
            wand,
            "jenga_ghost_pending_wand"
        )

        EntityAddTag(
            wand,
            "jenga_stacked_wand"
        )

        set_wand_pickable(wand, false)
        EntitySetTransform(wand, zone_x, zone_y)

        return false
    end

    EntityAddComponent2(
        ghost,
        "VariableStorageComponent",
        {
            name = "jenga_assigned_wand",
            value_int = wand,
        }
    )

    EntityAddComponent2(
        ghost,
        "VariableStorageComponent",
        {
            name = "jenga_stack_zone",
            value_int = zone,
        }
    )

    return true
end

local function awaken_stack(zone)
    local wands = get_stacked_wands_for_zone(zone)

    if #wands == 0 then
        return false
    end

    local spawned = 0

    for index, wand in ipairs(wands) do
        if spawn_wand_ghost_for_wand(
            wand,
            zone,
            index,
            #wands
        ) then
            spawned = spawned + 1
        end
    end

    if spawned > 0 then
        GamePrintImportant(
            "JENGA!",
            tostring(spawned)
            .. " wand ghosts have awakened."
        )

        return true
    end

    GamePrint(
        "JENGA: The wand ghosts could not be spawned."
    )

    return false
end

local function get_stack_awakening_chance(count)
    if count <= 1 then
        return 0
    elseif count == 2 then
        return 1
    elseif count == 3 then
        return 3
    elseif count == 4 then
        return 6
    elseif count == 5 then
        return 10
    end

    return math.min(
        10 + (count - 5) * 5,
        100
    )
end

local function try_awaken_stack(zone)
    local count =
        #get_stacked_wands_for_zone(zone)

    local chance =
        get_stack_awakening_chance(count)

    GamePrint(
        "JENGA: Awakening chance "
        .. tostring(chance)
        .. "%"
    )

    if chance <= 0 then
        return false
    end

    local zx, zy = EntityGetTransform(zone)

    SetRandomSeed(
        math.floor(zx + count * 101),
        math.floor(
            zy + GameGetFrameNum() * 17
        )
    )

    local roll = Random(1, 100)

    if roll <= chance then
        return awaken_stack(zone)
    end

    return false
end

local function set_wand_stack_home(wand, zone)
    if not is_alive(wand) or not is_alive(zone) then
        return
    end

    local zone_x, zone_y = EntityGetTransform(zone)

    local components = EntityGetComponentIncludingDisabled(
        wand,
        "VariableStorageComponent"
    ) or {}

    local home_x_component = nil
    local home_y_component = nil

    for _, component in ipairs(components) do
        local name = ComponentGetValue2(component, "name")

        if name == "jenga_stack_home_x" then
            home_x_component = component
        elseif name == "jenga_stack_home_y" then
            home_y_component = component
        end
    end

    if home_x_component == nil then
        home_x_component = EntityAddComponent2(
            wand,
            "VariableStorageComponent",
            {
                name = "jenga_stack_home_x",
                value_float = zone_x,
            }
        )
    else
        ComponentSetValue2(
            home_x_component,
            "value_float",
            zone_x
        )
    end

    if home_y_component == nil then
        home_y_component = EntityAddComponent2(
            wand,
            "VariableStorageComponent",
            {
                name = "jenga_stack_home_y",
                value_float = zone_y,
            }
        )
    else
        ComponentSetValue2(
            home_y_component,
            "value_float",
            zone_y
        )
    end
end

local function get_wand_stack_home(wand)
    if not is_alive(wand) then
        return nil, nil
    end

    local components = EntityGetComponentIncludingDisabled(
        wand,
        "VariableStorageComponent"
    ) or {}

    local home_x = nil
    local home_y = nil

    for _, component in ipairs(components) do
        local name = ComponentGetValue2(component, "name")

        if name == "jenga_stack_home_x" then
            home_x = ComponentGetValue2(
                component,
                "value_float"
            )
        elseif name == "jenga_stack_home_y" then
            home_y = ComponentGetValue2(
                component,
                "value_float"
            )
        end
    end

    return home_x, home_y
end

local function clear_wand_stack_home(wand)
    if not is_alive(wand) then
        return
    end

    local components = EntityGetComponentIncludingDisabled(
        wand,
        "VariableStorageComponent"
    ) or {}

    for _, component in ipairs(components) do
        local name = ComponentGetValue2(component, "name")

        if name == "jenga_stack_home_x"
            or name == "jenga_stack_home_y"
        then
            EntityRemoveComponent(wand, component)
        end
    end
end

local function add_wand_to_stack(wand, zone)
    if not is_alive(wand) or not is_alive(zone) then
        return false
    end

    local zone_x, zone_y = EntityGetTransform(zone)

    make_wand_owned(wand)
    set_wand_stack_home(wand, zone)
    set_wand_pickable(wand, false)

    EntityAddTag(wand, "jenga_stacked_wand")
    EntitySetTransform(wand, zone_x, zone_y)

    local velocity = EntityGetFirstComponentIncludingDisabled(
        wand,
        "VelocityComponent"
    )

    if velocity ~= nil then
        ComponentSetValue2(
            velocity,
            "mVelocity",
            0,
            0
        )
    end

    return true
end

-- =========================================================
-- Wiederaufnahme und verzögerter Tausch
-- =========================================================

local function pick_up_wand(wand)
    if not is_alive(wand) then
        return false
    end

    GamePickUpInventoryItem(
        player,
        wand,
        false
    )

    return true
end

local function clear_pending_operation()
    set_int(
        STORAGE_PENDING_STATE,
        PENDING_NONE
    )

    set_int(
        STORAGE_PENDING_OLD_WAND,
        0
    )

    set_int(
        STORAGE_PENDING_DONOR_WAND,
        0
    )

    set_int(
        STORAGE_PENDING_FRAMES,
        0
    )
end

local function remove_wand_from_inventory(wand)
    if not is_alive(wand) then
        return false
    end

    local parent = EntityGetParent(wand)

    if parent ~= nil and parent ~= 0 then
        EntityRemoveFromParent(wand)
    end

    return true
end

local function place_wand_near_player(wand)
    if not is_alive(wand) then
        return false
    end

    remove_wand_from_inventory(wand)

    local player_x, player_y = EntityGetTransform(player)

    EntitySetTransform(
        wand,
        player_x + 18,
        player_y
    )

    local velocity = EntityGetFirstComponentIncludingDisabled(
        wand,
        "VelocityComponent"
    )

    if velocity ~= nil then
        ComponentSetValue2(
            velocity,
            "mVelocity",
            25,
            -10
        )
    end

    return true
end

local function count_inventory_wands()
    return #get_inventory_wands()
end

local function start_pending_operation(
    state,
    old_wand,
    donor_wand
)
    set_int(
        STORAGE_PENDING_STATE,
        state
    )

    set_int(
        STORAGE_PENDING_OLD_WAND,
        old_wand
    )

    set_int(
        STORAGE_PENDING_DONOR_WAND,
        donor_wand
    )

    set_int(
        STORAGE_PENDING_FRAMES,
        0
    )
end

local function process_pending_operation()
    local state = get_int(
        STORAGE_PENDING_STATE
    )

    if state == PENDING_NONE then
        return false
    end

    local old_wand = get_int(
        STORAGE_PENDING_OLD_WAND
    )

    local donor_wand = get_int(
        STORAGE_PENDING_DONOR_WAND
    )

    local frames = get_int(
        STORAGE_PENDING_FRAMES
    ) + 1

    set_int(
        STORAGE_PENDING_FRAMES,
        frames
    )

    -- Der alte Stab ist bereits wieder im Inventar.
    if is_alive(old_wand)
        and inventory_contains_entity(old_wand)
    then
        make_wand_owned(old_wand)

        clear_pending_operation()
        save_current_wands(get_inventory_wands())

        return true
    end

    -- Sicherheit: Solange der Spender noch im Inventar ist,
    -- wird der alte Stab nicht aufgenommen.
    if is_alive(donor_wand)
        and inventory_contains_entity(donor_wand)
    then
        return true
    end

    -- Der Spender ist jetzt sicher weg beziehungsweise auf dem Boden.
    -- Nun ist wieder ein regulärer Stabplatz frei.
    if is_alive(old_wand) then
        pick_up_wand(old_wand)
    end

    -- Aufnahme kann erst im folgenden Frame sichtbar werden.
    if frames < MAX_PENDING_FRAMES then
        return true
    end

    GamePrint(
        "JENGA: The original wand could not be restored."
    )

    clear_pending_operation()
    save_current_wands(get_inventory_wands())

    return true
end

-- =========================================================
-- Normal mode spell selection
-- =========================================================

local function set_player_controls_enabled(enabled)
    -- Intentionally left as a no-op.
    -- Disabling ControlsComponent while drawing a custom GUI can cause
    -- unstable behavior in some Noita versions and input configurations.
end

local function set_world_wand_selection_lock(enabled)
    if enabled then
        local donor = get_int(
            STORAGE_SELECTION_DONOR
        )

        for _, wand in ipairs(
            EntityGetWithTag("wand") or {}
        ) do
            if is_alive(wand)
                and wand ~= donor
                and not EntityHasTag(
                    wand,
                    "jenga_owned_wand"
                )
                and not EntityHasTag(
                    wand,
                    "jenga_stacked_wand"
                )
                and not EntityHasTag(
                    wand,
                    "jenga_ghost_pending_wand"
                )
            then
                local item_component =
                    get_item_component(wand)

                if item_component ~= nil then
                    local pickable =
                        ComponentGetValue2(
                            item_component,
                            "is_pickable"
                        ) == true

                    if pickable then
                        ComponentSetValue2(
                            item_component,
                            "is_pickable",
                            false
                        )

                        EntityAddTag(
                            wand,
                            SELECTION_PICKUP_LOCK_TAG
                        )
                    end
                end
            end
        end

        return
    end

    for _, wand in ipairs(
        EntityGetWithTag(
            SELECTION_PICKUP_LOCK_TAG
        ) or {}
    ) do
        if is_alive(wand) then
            local item_component =
                get_item_component(wand)

            if item_component ~= nil then
                ComponentSetValue2(
                    item_component,
                    "is_pickable",
                    true
                )
            end

            EntityRemoveTag(
                wand,
                SELECTION_PICKUP_LOCK_TAG
            )
        end
    end
end

local function enforce_spell_selection_pause()
    if not get_bool(STORAGE_SELECTION_ACTIVE) then
        return
    end

    -- Keep the player stationary while the custom picker remains active.
    local velocity =
        EntityGetFirstComponentIncludingDisabled(
            player,
            "VelocityComponent"
        )

    if velocity ~= nil then
        pcall(
            ComponentSetValue2,
            velocity,
            "mVelocity",
            0,
            0
        )
    end

    local character_data =
        EntityGetFirstComponentIncludingDisabled(
            player,
            "CharacterDataComponent"
        )

    if character_data ~= nil then
        pcall(
            ComponentSetValue2,
            character_data,
            "mVelocity",
            0,
            0
        )
    end

    -- Block gameplay controls while retaining mouse input for the JENGA GUI.
    local controls =
        EntityGetFirstComponentIncludingDisabled(
            player,
            "ControlsComponent"
        )

    if controls ~= nil then
        local down_fields = {
            "mButtonDownLeft",
            "mButtonDownRight",
            "mButtonDownUp",
            "mButtonDownDown",
            "mButtonDownFire",
            "mButtonDownFire2",
            "mButtonDownInteract",
            "mButtonDownKick",
            "mButtonDownThrow",
        }

        for _, field in ipairs(down_fields) do
            pcall(
                ComponentSetValue2,
                controls,
                field,
                false
            )
        end

        local frame_fields = {
            "mButtonFrameFire",
            "mButtonFrameFire2",
            "mButtonFrameInteract",
            "mButtonFrameKick",
            "mButtonFrameThrow",
        }

        for _, field in ipairs(frame_fields) do
            pcall(
                ComponentSetValue2,
                controls,
                field,
                -1
            )
        end
    end

    set_world_wand_selection_lock(true)
end

local function clear_spell_selection()
    set_bool(
        STORAGE_TWITCH_PENDING_CONFIRM,
        false
    )

    set_world_wand_selection_lock(false)
    set_bool(STORAGE_SELECTION_ACTIVE, false)
    set_int(STORAGE_SELECTION_DONOR, 0)
    set_int(STORAGE_SELECTION_TARGET, 0)
    set_int(STORAGE_SELECTION_TYPE, SELECTION_NONE)
    set_int(STORAGE_SELECTION_SPELL, 0)

    if jenga_spell_selection_gui ~= nil then
        GuiDestroy(jenga_spell_selection_gui)
        jenga_spell_selection_gui = nil
    end
end

local function lock_native_inventory_during_selection()
    if not get_bool(STORAGE_SELECTION_ACTIVE) then
        return
    end

    -- Force Noita's native inventory window closed while JENGA owns the
    -- world-wand pickup and spell-selection state.
    local inventory_gui =
        EntityGetFirstComponentIncludingDisabled(
            player,
            "InventoryGuiComponent"
        )

    if inventory_gui ~= nil then
        ComponentSetValue2(
            inventory_gui,
            "mActive",
            false
        )
    end

    -- Suppress inventory-toggle input for the current frame. pcall keeps
    -- compatibility with builds where one of these control fields differs.
    local controls =
        EntityGetFirstComponentIncludingDisabled(
            player,
            "ControlsComponent"
        )

    if controls ~= nil then
        local boolean_fields = {
            "mButtonDownInventory",
            "mButtonDownInventory2",
        }

        for _, field in ipairs(boolean_fields) do
            pcall(
                ComponentSetValue2,
                controls,
                field,
                false
            )
        end

        local frame_fields = {
            "mButtonFrameInventory",
            "mButtonFrameInventory2",
        }

        for _, field in ipairs(frame_fields) do
            pcall(
                ComponentSetValue2,
                controls,
                field,
                -1
            )
        end
    end
end

local function twitch_bridge_is_connected()
    return GlobalsGetValue(
        TWITCH_BRIDGE_CONNECTED,
        "0"
    ) == "1"
end

local function send_twitch_command(command)
    local serial = tonumber(
        GlobalsGetValue(
            TWITCH_COMMAND_SERIAL,
            "0"
        )
    ) or 0

    serial = serial + 1

    GlobalsSetValue(
        TWITCH_COMMAND,
        tostring(command or "")
    )

    GlobalsSetValue(
        TWITCH_COMMAND_SERIAL,
        tostring(serial)
    )
end

local function reset_twitch_state(vote_id)
    GlobalsSetValue(
        TWITCH_STATE_VOTE_ID,
        tostring(vote_id or "")
    )

    GlobalsSetValue(
        TWITCH_STATE_STATUS,
        "waiting"
    )

    GlobalsSetValue(
        TWITCH_STATE_REMAINING,
        tostring(TWITCH_VOTE_DURATION)
    )

    GlobalsSetValue(
        TWITCH_STATE_VOTES,
        ""
    )

    GlobalsSetValue(
        TWITCH_STATE_WINNER,
        "0"
    )
end

local function start_twitch_vote(spells)
    local vote_id =
        tostring(GameGetFrameNum())
        .. "_"
        .. tostring(
            math.floor(
                GameGetRealWorldTimeSinceStarted()
                * 1000
            )
        )

    set_string(
        STORAGE_TWITCH_VOTE_ID,
        vote_id
    )

    set_float(
        STORAGE_TWITCH_STARTED_AT,
        GameGetRealWorldTimeSinceStarted()
    )

    reset_twitch_state(vote_id)

    send_twitch_command(
        "START|"
        .. vote_id
        .. "|"
        .. tostring(#spells)
        .. "|"
        .. tostring(TWITCH_VOTE_DURATION)
    )

    GamePrintImportant(
        "JENGA Twitch Vote",
        "Chat votes with numbers only. Voting ends in 30 seconds."
    )

    return true
end

local function cancel_twitch_vote()
    local vote_id = get_string(
        STORAGE_TWITCH_VOTE_ID
    )

    if vote_id ~= "" then
        send_twitch_command(
            "CANCEL|" .. vote_id
        )
    end

    set_string(
        STORAGE_TWITCH_VOTE_ID,
        ""
    )
end

local function get_twitch_snapshot(option_count)
    local local_vote_id = get_string(
        STORAGE_TWITCH_VOTE_ID
    )

    local remote_vote_id = GlobalsGetValue(
        TWITCH_STATE_VOTE_ID,
        ""
    )

    local votes = {}

    for value in string.gmatch(
        GlobalsGetValue(
            TWITCH_STATE_VOTES,
            ""
        ),
        "[^,]+"
    ) do
        table.insert(
            votes,
            tonumber(value) or 0
        )
    end

    for index = #votes + 1, option_count do
        votes[index] = 0
    end

    if remote_vote_id ~= local_vote_id then
        return {
            status = twitch_bridge_is_connected()
                and "waiting"
                or "bridge_missing",
            remaining = TWITCH_VOTE_DURATION,
            winner = 0,
            votes = votes,
        }
    end

    return {
        status = GlobalsGetValue(
            TWITCH_STATE_STATUS,
            "waiting"
        ),
        remaining = math.max(
            0,
            tonumber(
                GlobalsGetValue(
                    TWITCH_STATE_REMAINING,
                    tostring(TWITCH_VOTE_DURATION)
                )
            ) or TWITCH_VOTE_DURATION
        ),
        winner = tonumber(
            GlobalsGetValue(
                TWITCH_STATE_WINNER,
                "0"
            )
        ) or 0,
        votes = votes,
    }
end

local function get_twitch_winner_if_ready(spells)
    local snapshot =
        get_twitch_snapshot(#spells)

    if snapshot.status == "finished"
        and snapshot.winner >= 1
        and snapshot.winner <= #spells
    then
        return spells[snapshot.winner].entity
    end

    return 0
end

local function start_spell_selection(donor, target, selection_type)
    if not is_alive(donor) then return false end

    local spells = get_normal_spells(donor)
    if #spells == 0 then return false end

    if get_gameplay_mode() == "twitch" then
        spells =
            JENGA_INTERNAL.get_unique_vote_spells(
                spells
            )
    end

    set_bool(STORAGE_SELECTION_ACTIVE, true)

    set_int(STORAGE_SELECTION_DONOR, donor)
    set_int(STORAGE_SELECTION_TARGET, target or 0)
    set_int(STORAGE_SELECTION_TYPE, selection_type)
    set_int(STORAGE_SELECTION_SPELL, 0)
    set_bool(
        STORAGE_TWITCH_PENDING_CONFIRM,
        false
    )

    if get_gameplay_mode() == "twitch" then
        -- A vote is unnecessary when there is only one possible spell.
        if #spells == 1 then
            set_int(
                STORAGE_SELECTION_SPELL,
                spells[1].entity
            )

            set_bool(
                STORAGE_TWITCH_PENDING_CONFIRM,
                true
            )

            GamePrint(
                "JENGA: Only one distinct spell available; selected automatically."
            )

            return true
        end

        -- Player movement remains fully controllable during chat voting.
        -- Inventory is locked and other world wands are unpickable.
        lock_native_inventory_during_selection()
        start_twitch_vote(spells)
        set_world_wand_selection_lock(true)
    else
        lock_native_inventory_during_selection()
        set_player_controls_enabled(false)
        enforce_spell_selection_pause()
    end

    return true
end

local function cancel_spell_selection()
    if get_gameplay_mode() == "twitch" then
        cancel_twitch_vote()
    end

    local donor = get_int(STORAGE_SELECTION_DONOR)
    local target = get_int(STORAGE_SELECTION_TARGET)
    local selection_type = get_int(STORAGE_SELECTION_TYPE)

    clear_spell_selection()

    if selection_type == SELECTION_TRANSFER and is_alive(target) then
        if is_alive(donor) then place_wand_near_player(donor) end
        start_pending_operation(PENDING_RESTORE_AFTER_CANCEL, target, donor)
    else
        if is_alive(donor) then place_wand_near_player(donor) end
        save_current_wands(get_inventory_wands())
    end
end

local function confirm_spell_selection()
    local donor = get_int(STORAGE_SELECTION_DONOR)
    local target = get_int(STORAGE_SELECTION_TARGET)
    local selection_type = get_int(STORAGE_SELECTION_TYPE)
    local selected_spell = get_int(STORAGE_SELECTION_SPELL)

    if not is_alive(donor) or not is_alive(selected_spell) then
        return false
    end

    if EntityGetParent(selected_spell) ~= donor
        or not is_normal_spell(selected_spell)
    then
        set_int(STORAGE_SELECTION_SPELL, 0)
        return false
    end

    if selection_type == SELECTION_TRANSFER then
        if not is_alive(target) then
            cancel_spell_selection()
            return false
        end

        if get_first_free_spell_slot(target) == nil then
            place_wand_near_player(donor)

            start_pending_operation(
                PENDING_RESTORE_AFTER_CANCEL,
                target,
                donor
            )

            clear_spell_selection()

            GamePrint(
                "JENGA: This wand is full. Take it to the JENGA stack before collecting another spell."
            )

            return true
        end

        local success = transfer_selected_spell(donor, target, selected_spell)
        if not success then return false end

        make_wand_owned(target)
        clear_spell_selection()

        if is_alive(donor) then EntityKill(donor) end
        start_pending_operation(PENDING_RESTORE_AFTER_SUCCESS, target, donor)

        GamePrint("JENGA: Selected spell added to the chosen wand.")
        return true
    end

    if selection_type == SELECTION_KEEP_WAND then
        local success = trim_wand_to_selected_spell(donor, selected_spell)
        if not success then return false end

        make_wand_owned(donor)
        clear_spell_selection()
        save_current_wands(get_inventory_wands())

        GamePrint("JENGA: World wand acquired with the selected spell.")
        return true
    end

    cancel_spell_selection()
    return false
end

-- =========================================================
-- Pinned native-style wand card
--
-- Hover a wand in the native inventory and hold Left Alt.
-- The hovered wand is remembered while Alt remains held, allowing the
-- mouse to move onto the replicated Always Cast icons and read tooltips.
-- =========================================================

local KEY_LEFT_ALT = 226
local KEY_RIGHT_ALT = 230

local function is_alt_down()
    return InputIsKeyDown(KEY_LEFT_ALT)
        or InputIsKeyDown(KEY_RIGHT_ALT)
end

local function get_wand_stat_value(
    wand,
    object_name,
    value_name,
    default_value
)
    local ability = EntityGetFirstComponentIncludingDisabled(
        wand,
        "AbilityComponent"
    )

    if ability == nil then
        return default_value
    end

    if object_name ~= nil then
        local value = ComponentObjectGetValue2(
            ability,
            object_name,
            value_name
        )

        if value ~= nil then
            return value
        end

        return default_value
    end

    local value = ComponentGetValue2(
        ability,
        value_name
    )

    if value ~= nil then
        return value
    end

    return default_value
end

local function format_seconds_from_frames(value)
    local frames = tonumber(value) or 0
    return string.format("%.2f s", frames / 60)
end

local function get_pinned_card_spells(wand)
    local result = {}

    if not is_alive(wand) then
        return result
    end

    for _, child in ipairs(EntityGetAllChildren(wand) or {}) do
        if is_spell_entity(child) then
            local item_component = get_item_component(child)

            if item_component ~= nil then
                local permanent = ComponentGetValue2(
                    item_component,
                    "permanently_attached"
                ) == true

                local fixed_by_jenga =
                    EntityHasTag(
                        child,
                        SPELL_LOCK_TAG
                    )

                if permanent or fixed_by_jenga then
                    table.insert(result, child)
                end
            end
        end
    end

    table.sort(
        result,
        function(a, b)
            local ax = get_item_slot(a)
            local bx = get_item_slot(b)
            return ax < bx
        end
    )

    return result
end

local function get_active_wand()
    local inventory_component =
        EntityGetFirstComponentIncludingDisabled(
            player,
            "Inventory2Component"
        )

    if inventory_component == nil then
        return 0
    end

    local active_item = ComponentGetValue2(
        inventory_component,
        "mActiveItem"
    ) or 0

    if is_wand(active_item) then
        return active_item
    end

    return 0
end

local function get_fixed_charge_entries()
    local entries = {}
    local wand = get_active_wand()

    if not is_alive(wand) then
        return entries
    end

    for _, spell in ipairs(EntityGetAllChildren(wand) or {}) do
        if EntityHasTag(spell, SPELL_LOCK_TAG) then
            local tracked = get_entity_storage_int(
                spell,
                SPELL_CHARGE_TRACKED
            )

            if tracked == 1 then
                table.insert(
                    entries,
                    {
                        spell = spell,
                        remaining = math.max(
                            0,
                            get_entity_storage_int(
                                spell,
                                SPELL_CHARGE_REMAINING
                            )
                        ),
                        slot = get_entity_storage_int(
                            spell,
                            SPELL_LOCK_SLOT_X
                        ),
                    }
                )
            end
        end
    end

    table.sort(
        entries,
        function(a, b)
            if a.slot == b.slot then
                return a.spell < b.spell
            end

            return a.slot < b.slot
        end
    )

    return entries
end

local function render_fixed_charge_display()
    if GameIsInventoryOpen()
        or get_bool(STORAGE_SELECTION_ACTIVE)
    then
        return
    end

    local entries = get_fixed_charge_entries()

    if #entries == 0 then
        return
    end

    if jenga_charge_display_gui == nil then
        jenga_charge_display_gui = GuiCreate()
    end

    local gui = jenga_charge_display_gui

    if gui == nil then
        return
    end

    GuiStartFrame(gui)
    GuiZSet(gui, -1000)

    -- Fixed screen-space area below the left side of the native hotbar.
    local start_x = 6
    local start_y = 45
    local spacing = 27

    for index, entry in ipairs(entries) do
        local x = start_x + (index - 1) * spacing
        local icon = get_spell_icon(entry.spell)

        if icon == nil or icon == "" then
            icon = "data/ui_gfx/inventory/icon_unknown.png"
        end

        -- Use full-size icon rendering known to work in JENGA's other GUIs.
        GuiImage(
            gui,
            970000 + index,
            x,
            start_y,
            icon,
            1,
            0.75,
            0.75,
            0
        )

        local value = tostring(entry.remaining)

        GuiColorSetForNextWidget(gui, 0, 0, 0, 1)
        GuiText(
            gui,
            x + 14,
            start_y + 5,
            value
        )

        GuiColorSetForNextWidget(gui, 1, 1, 1, 1)
        GuiText(
            gui,
            x + 13,
            start_y + 4,
            value
        )
    end
end

local function draw_fixed_charge_display()
    local ok, error_message = pcall(
        render_fixed_charge_display
    )

    if not ok
        and not jenga_charge_display_error_shown
    then
        jenga_charge_display_error_shown = true

        GamePrint(
            "JENGA charge display error: "
            .. tostring(error_message)
        )
    end
end


local function get_hovered_native_wand(gui, wands)
    local mouse_x, mouse_y =
        InputGetMousePosOnScreen()

    local screen_w, screen_h =
        GuiGetScreenDimensions(gui)

    if mouse_x == nil or mouse_y == nil then
        return 0
    end

    -- The native inventory is anchored to the upper-left corner.
    -- These ratios are based on Noita's actual inventory layout rather
    -- than custom GUI widgets, so native UI elements cannot consume the
    -- hover event before JENGA sees it.
    local area_left = screen_w * 0.035
    local area_top = screen_h * 0.008
    local area_width = screen_w * 0.315
    local area_height = screen_h * 0.125

    if mouse_x < area_left
        or mouse_x > area_left + area_width
        or mouse_y < area_top
        or mouse_y > area_top + area_height
    then
        return 0
    end

    local relative_x =
        (mouse_x - area_left) / area_width

    local slot_index =
        math.floor(relative_x * 4) + 1

    slot_index = math.max(
        1,
        math.min(4, slot_index)
    )

    if wands[slot_index] ~= nil then
        return wands[slot_index].entity
    end

    return 0
end

JENGA_INTERNAL =
    JENGA_INTERNAL or {}

function JENGA_INTERNAL.get_unique_vote_spells(spells)
    local result = {}
    local seen_action_ids = {}

    for _, spell_data in ipairs(spells or {}) do
        local spell = spell_data.entity
        local action_id =
            get_spell_action_id(spell)

        -- Entity ID fallback keeps unusual malformed/modded spells selectable
        -- without accidentally merging unrelated empty action IDs.
        local key

        if action_id ~= nil
            and action_id ~= ""
        then
            key = action_id
        else
            key = "entity:"
                .. tostring(spell)
        end

        if not seen_action_ids[key] then
            seen_action_ids[key] = true
            table.insert(
                result,
                spell_data
            )
        end
    end

    return result
end

function JENGA_INTERNAL.get_spell_description(spell)
    local action = get_action_definition(
        get_spell_action_id(spell)
    )

    if action == nil then
        return ""
    end

    local description = action.description or ""

    if description ~= "" then
        description = GameTextGetTranslatedOrNot(
            description
        )
    end

    return description
end

local ACTION_TYPE_NAMES = {
    [0] = "Projectile",
    [1] = "Static projectile",
    [2] = "Modifier",
    [3] = "Draw many",
    [4] = "Material",
    [5] = "Other",
    [6] = "Utility",
    [7] = "Passive",
}

function JENGA_INTERNAL.get_spell_action_definition(spell)
    return get_action_definition(
        get_spell_action_id(spell)
    )
end

function JENGA_INTERNAL.get_spell_type_name(spell)
    local action = JENGA_INTERNAL.get_spell_action_definition(spell)

    if action == nil then
        return "Unknown"
    end

    local action_type = action.type

    -- Prefer comparisons against Noita's actual enum constants.
    if action_type == ACTION_TYPE_PROJECTILE then
        return "Projectile"
    elseif action_type == ACTION_TYPE_STATIC_PROJECTILE then
        return "Static projectile"
    elseif action_type == ACTION_TYPE_MODIFIER then
        return "Modifier"
    elseif action_type == ACTION_TYPE_DRAW_MANY then
        return "Draw many"
    elseif action_type == ACTION_TYPE_MATERIAL then
        return "Material"
    elseif action_type == ACTION_TYPE_OTHER then
        return "Other"
    elseif action_type == ACTION_TYPE_UTILITY then
        return "Utility"
    elseif action_type == ACTION_TYPE_PASSIVE then
        return "Passive"
    end

    -- Numeric fallback for unusual modded action definitions.
    local numeric_type = tonumber(action_type)

    if numeric_type ~= nil then
        return ACTION_TYPE_NAMES[numeric_type]
            or ("Type " .. tostring(numeric_type))
    end

    return "Unknown"
end

function JENGA_INTERNAL.get_spell_mana_cost(spell)
    local action = JENGA_INTERNAL.get_spell_action_definition(spell)

    if action == nil then
        return nil
    end

    return tonumber(action.mana)
end

function JENGA_INTERNAL.get_spell_uses_text(spell)
    if get_entity_storage_int(
        spell,
        SPELL_CHARGE_TRACKED
    ) == 1 then
        local remaining =
            get_entity_storage_int(
                spell,
                SPELL_CHARGE_REMAINING
            )

        local maximum =
            get_entity_storage_int(
                spell,
                SPELL_CHARGE_MAX
            )

        return tostring(math.max(0, remaining))
            .. " / "
            .. tostring(math.max(0, maximum))
    end

    local action = JENGA_INTERNAL.get_spell_action_definition(spell)
    local item_component = get_item_component(spell)

    local max_uses = nil
    local remaining_uses = nil

    if action ~= nil then
        max_uses = tonumber(action.max_uses)
    end

    if item_component ~= nil then
        remaining_uses = tonumber(
            ComponentGetValue2(
                item_component,
                "uses_remaining"
            )
        )
    end

    if max_uses == nil or max_uses < 0 then
        return "Unlimited"
    end

    if remaining_uses ~= nil and remaining_uses >= 0 then
        return tostring(remaining_uses)
            .. " / "
            .. tostring(max_uses)
    end

    return tostring(max_uses)
end

function JENGA_INTERNAL.format_spell_stat_number(value)
    value = tonumber(value)

    if value == nil then
        return nil
    end

    if math.abs(value) >= 100 then
        return tostring(
            math.floor(value + 0.5)
        )
    end

    return string.format("%.2f", value)
        :gsub("0+$", "")
        :gsub("%.$", "")
end

function JENGA_INTERNAL.format_noita_damage(value)
    value = tonumber(value)

    if value == nil then
        return nil
    end

    -- Noita internally stores damage in units where 1.0 equals 25 displayed
    -- damage. This matches the values shown by the vanilla spell tooltip.
    return JENGA_INTERNAL.format_spell_stat_number(
        value * 25
    )
end

function JENGA_INTERNAL.get_spell_attachment_status(spell)
    local item_component =
        get_item_component(spell)

    local natural = false

    if item_component ~= nil then
        natural =
            ComponentGetValue2(
                item_component,
                "permanently_attached"
            ) == true
    end

    if EntityHasTag(
        spell,
        SPELL_LOCK_TAG
    ) then
        return "JENGA Fixed"
    end

    if natural then
        return "Natural"
    end

    return "Editable"
end

local projectile_stat_cache = {}

local action_runtime_stat_cache = {}

function JENGA_INTERNAL.make_default_action_probe_config()
    return {
        fire_rate_wait = 0,
        reload_time = 0,
        damage_projectile_add = 0,
        damage_melee_add = 0,
        damage_electricity_add = 0,
        damage_fire_add = 0,
        damage_explosion_add = 0,
        damage_ice_add = 0,
        damage_slice_add = 0,
        damage_healing_add = 0,
        damage_curse_add = 0,
        damage_drill_add = 0,
        damage_critical_chance = 0,
        damage_critical_multiplier = 0,
        explosion_radius = 0,
        spread_degrees = 0,
        speed_multiplier = 1,
        lifetime_add = 0,
        bounces = 0,
        knockback_force = 0,
        recoil_knockback = 0,
        friendly_fire = false,
        extra_entities = "",
        game_effect_entities = "",
        trail_material = "",
        trail_material_amount = 0,
        screenshake = 0,
        gore_particles = 0,
        ragdoll_fx = 0,
    }
end

function JENGA_INTERNAL.probe_action_runtime_stats(action)
    if action == nil then
        return {}
    end

    local action_id = tostring(action.id or "")

    if action_runtime_stat_cache[action_id] ~= nil then
        return action_runtime_stat_cache[action_id]
    end

    local result = {
        projectiles = {},
    }

    if type(action.action) ~= "function" then
        action_runtime_stat_cache[action_id] = result
        return result
    end

    local saved = {
        c = _G.c,
        shot_effects = _G.shot_effects,
        reflecting = _G.reflecting,
        current_reload_time = _G.current_reload_time,
        draw_actions = _G.draw_actions,
        add_projectile = _G.add_projectile,
        add_projectile_trigger_timer = _G.add_projectile_trigger_timer,
        add_projectile_trigger_hit_world = _G.add_projectile_trigger_hit_world,
        add_projectile_trigger_death = _G.add_projectile_trigger_death,
        add_projectile_trigger = _G.add_projectile_trigger,
        add_projectile_trigger_timer_world = _G.add_projectile_trigger_timer_world,
        add_projectile_trigger_hit_world_world = _G.add_projectile_trigger_hit_world_world,
        add_projectile_trigger_death_world = _G.add_projectile_trigger_death_world,
    }

    local probe_c = JENGA_INTERNAL.make_default_action_probe_config()
    local probe_shot_effects = {
        recoil_knockback = 0,
    }

    local function capture_projectile(path)
        if type(path) == "string" and path ~= "" then
            table.insert(result.projectiles, path)
        end

        return 0
    end

    local function capture_projectile_trigger(path, ...)
        return capture_projectile(path)
    end

    _G.c = probe_c
    _G.shot_effects = probe_shot_effects
    _G.reflecting = true
    _G.current_reload_time = 0
    _G.draw_actions = function() end
    _G.add_projectile = capture_projectile
    _G.add_projectile_trigger_timer = capture_projectile_trigger
    _G.add_projectile_trigger_hit_world = capture_projectile_trigger
    _G.add_projectile_trigger_death = capture_projectile_trigger
    _G.add_projectile_trigger = capture_projectile_trigger
    _G.add_projectile_trigger_timer_world = capture_projectile_trigger
    _G.add_projectile_trigger_hit_world_world = capture_projectile_trigger
    _G.add_projectile_trigger_death_world = capture_projectile_trigger

    local ok = pcall(action.action)

    _G.c = saved.c
    _G.shot_effects = saved.shot_effects
    _G.reflecting = saved.reflecting
    _G.current_reload_time = saved.current_reload_time
    _G.draw_actions = saved.draw_actions
    _G.add_projectile = saved.add_projectile
    _G.add_projectile_trigger_timer = saved.add_projectile_trigger_timer
    _G.add_projectile_trigger_hit_world = saved.add_projectile_trigger_hit_world
    _G.add_projectile_trigger_death = saved.add_projectile_trigger_death
    _G.add_projectile_trigger = saved.add_projectile_trigger
    _G.add_projectile_trigger_timer_world = saved.add_projectile_trigger_timer_world
    _G.add_projectile_trigger_hit_world_world = saved.add_projectile_trigger_hit_world_world
    _G.add_projectile_trigger_death_world = saved.add_projectile_trigger_death_world

    if ok then
        for key, value in pairs(probe_c) do
            result[key] = value
        end

        result.current_reload_time =
            tonumber(_G.current_reload_time)
            or tonumber(probe_c.reload_time)
            or 0

        result.recoil_knockback =
            tonumber(probe_shot_effects.recoil_knockback)
            or tonumber(probe_c.recoil_knockback)
            or 0
    end

    action_runtime_stat_cache[action_id] = result
    return result
end

function JENGA_INTERNAL.merge_projectile_stats(base, incoming)
    base = base or {}
    incoming = incoming or {}

    local numeric_keys = {
        "projectile",
        "melee",
        "fire",
        "ice",
        "electricity",
        "explosion",
        "slice",
        "healing",
        "curse",
        "drill",
    }

    for _, key in ipairs(numeric_keys) do
        local value = tonumber(incoming[key])

        if value ~= nil then
            base[key] =
                (tonumber(base[key]) or 0)
                + value
        end
    end

    local max_keys = {
        "explosion_radius",
        "lifetime",
        "speed_min",
        "speed_max",
    }

    for _, key in ipairs(max_keys) do
        local value = tonumber(incoming[key])

        if value ~= nil then
            base[key] = math.max(
                tonumber(base[key]) or 0,
                value
            )
        end
    end

    return base
end


function JENGA_INTERNAL.read_component_number(
    component,
    field
)
    if component == nil then
        return nil
    end

    local ok, value = pcall(
        ComponentGetValue2,
        component,
        field
    )

    if not ok then
        return nil
    end

    return tonumber(value)
end

function JENGA_INTERNAL.read_object_number(
    component,
    object_name,
    field
)
    if component == nil then
        return nil
    end

    local ok, value = pcall(
        ComponentObjectGetValue2,
        component,
        object_name,
        field
    )

    if not ok then
        return nil
    end

    return tonumber(value)
end

function JENGA_INTERNAL.get_projectile_file_from_action(
    action
)
    if action == nil then
        return nil
    end

    local candidates = {
        action.projectile_file,
        action.projectile_file_1,
        action.projectile,
        action.entity_file,
    }

    for _, candidate in ipairs(candidates) do
        if type(candidate) == "string"
            and candidate ~= ""
        then
            return candidate
        end
    end

    return nil
end

function JENGA_INTERNAL.get_projectile_entity_stats(action)
    if action == nil then
        return {}
    end

    local action_id =
        tostring(action.id or "")

    if projectile_stat_cache[action_id]
        ~= nil
    then
        return projectile_stat_cache[action_id]
    end

    local result = {}
    local projectile_file =
        JENGA_INTERNAL.get_projectile_file_from_action(action)

    if projectile_file == nil then
        projectile_stat_cache[action_id] =
            result

        return result
    end

    local ok, entity = pcall(
        EntityLoad,
        projectile_file,
        0,
        -100000
    )

    if not ok
        or entity == nil
        or entity == 0
    then
        projectile_stat_cache[action_id] =
            result

        return result
    end

    local projectile =
        EntityGetFirstComponentIncludingDisabled(
            entity,
            "ProjectileComponent"
        )

    if projectile ~= nil then
        result.projectile =
            JENGA_INTERNAL.read_component_number(
                projectile,
                "damage"
            )
            or JENGA_INTERNAL.read_object_number(
                projectile,
                "damage_by_type",
                "projectile"
            )

        result.melee =
            JENGA_INTERNAL.read_object_number(
                projectile,
                "damage_by_type",
                "melee"
            )

        result.fire =
            JENGA_INTERNAL.read_object_number(
                projectile,
                "damage_by_type",
                "fire"
            )

        result.ice =
            JENGA_INTERNAL.read_object_number(
                projectile,
                "damage_by_type",
                "ice"
            )

        result.electricity =
            JENGA_INTERNAL.read_object_number(
                projectile,
                "damage_by_type",
                "electricity"
            )

        result.explosion =
            JENGA_INTERNAL.read_object_number(
                projectile,
                "damage_by_type",
                "explosion"
            )

        result.slice =
            JENGA_INTERNAL.read_object_number(
                projectile,
                "damage_by_type",
                "slice"
            )

        result.healing =
            JENGA_INTERNAL.read_object_number(
                projectile,
                "damage_by_type",
                "healing"
            )

        result.curse =
            JENGA_INTERNAL.read_object_number(
                projectile,
                "damage_by_type",
                "curse"
            )

        result.drill =
            JENGA_INTERNAL.read_object_number(
                projectile,
                "damage_by_type",
                "drill"
            )

        result.lifetime =
            JENGA_INTERNAL.read_component_number(
                projectile,
                "lifetime"
            )

        result.speed_min =
            JENGA_INTERNAL.read_component_number(
                projectile,
                "speed_min"
            )

        result.speed_max =
            JENGA_INTERNAL.read_component_number(
                projectile,
                "speed_max"
            )
    end

    local explosion =
        EntityGetFirstComponentIncludingDisabled(
            entity,
            "ExplodeOnDamageComponent"
        )
        or EntityGetFirstComponentIncludingDisabled(
            entity,
            "ExplosionComponent"
        )

    if explosion ~= nil then
        result.explosion =
            result.explosion
            or JENGA_INTERNAL.read_component_number(
                explosion,
                "damage"
            )
            or JENGA_INTERNAL.read_object_number(
                explosion,
                "config_explosion",
                "damage"
            )

        result.explosion_radius =
            JENGA_INTERNAL.read_component_number(
                explosion,
                "explosion_radius"
            )
            or JENGA_INTERNAL.read_object_number(
                explosion,
                "config_explosion",
                "explosion_radius"
            )
    end

    EntityKill(entity)

    projectile_stat_cache[action_id] =
        result

    return result
end

function JENGA_INTERNAL.get_spell_detail_rows(spell)
    local rows = {}
    local action =
        JENGA_INTERNAL.get_spell_action_definition(spell)

    local function add(label, value)
        if value == nil or value == "" then
            return
        end

        table.insert(
            rows,
            {
                tostring(label),
                tostring(value),
            }
        )
    end

    local function add_damage(label, value)
        value = tonumber(value)

        if value == nil or value == 0 then
            return
        end

        add(
            label,
            JENGA_INTERNAL.format_noita_damage(value)
        )
    end

    add(
        "Mana drain",
        JENGA_INTERNAL.get_spell_mana_cost(spell)
    )

    add(
        "Remaining uses",
        JENGA_INTERNAL.get_spell_uses_text(spell)
    )

    add(
        "Attachment",
        JENGA_INTERNAL.get_spell_attachment_status(spell)
    )

    if action == nil then
        return rows
    end

    local runtime =
        JENGA_INTERNAL.probe_action_runtime_stats(action)

    local combined_projectile = {}

    local static_projectile =
        JENGA_INTERNAL.get_projectile_entity_stats(action)

    JENGA_INTERNAL.merge_projectile_stats(
        combined_projectile,
        static_projectile
    )

    for _, projectile_file in ipairs(
        runtime.projectiles or {}
    ) do
        local synthetic_action = {
            id = tostring(action.id or "")
                .. "|"
                .. projectile_file,
            projectile_file = projectile_file,
        }

        JENGA_INTERNAL.merge_projectile_stats(
            combined_projectile,
            JENGA_INTERNAL.get_projectile_entity_stats(
                synthetic_action
            )
        )
    end

    local projectile_damage =
        tonumber(action.damage_projectile)
        or tonumber(action.damage)
        or tonumber(
            action.damage_projectile_add
        )
        or tonumber(
            runtime.damage_projectile_add
        )
        or 0

    projectile_damage =
        projectile_damage
        + (tonumber(
            combined_projectile.projectile
        ) or 0)

    local explosion_damage =
        tonumber(action.damage_explosion)
        or tonumber(
            action.damage_explosion_add
        )
        or tonumber(
            runtime.damage_explosion_add
        )
        or 0

    explosion_damage =
        explosion_damage
        + (tonumber(
            combined_projectile.explosion
        ) or 0)

    local melee_damage =
        tonumber(action.damage_melee)
        or tonumber(action.damage_melee_add)
        or tonumber(runtime.damage_melee_add)
        or 0

    melee_damage =
        melee_damage
        + (tonumber(
            combined_projectile.melee
        ) or 0)

    local fire_damage =
        tonumber(action.damage_fire)
        or tonumber(action.damage_fire_add)
        or tonumber(runtime.damage_fire_add)
        or 0

    fire_damage =
        fire_damage
        + (tonumber(
            combined_projectile.fire
        ) or 0)

    local ice_damage =
        tonumber(action.damage_ice)
        or tonumber(action.damage_ice_add)
        or tonumber(runtime.damage_ice_add)
        or 0

    ice_damage =
        ice_damage
        + (tonumber(
            combined_projectile.ice
        ) or 0)

    local electric_damage =
        tonumber(action.damage_electricity)
        or tonumber(
            action.damage_electricity_add
        )
        or tonumber(
            runtime.damage_electricity_add
        )
        or 0

    electric_damage =
        electric_damage
        + (tonumber(
            combined_projectile.electricity
        ) or 0)

    local slice_damage =
        tonumber(action.damage_slice)
        or tonumber(action.damage_slice_add)
        or tonumber(runtime.damage_slice_add)
        or 0

    slice_damage =
        slice_damage
        + (tonumber(
            combined_projectile.slice
        ) or 0)

    local healing_damage =
        tonumber(action.damage_healing)
        or tonumber(action.damage_healing_add)
        or tonumber(runtime.damage_healing_add)
        or 0

    healing_damage =
        healing_damage
        + (tonumber(
            combined_projectile.healing
        ) or 0)

    local curse_damage =
        tonumber(action.damage_curse)
        or tonumber(action.damage_curse_add)
        or tonumber(runtime.damage_curse_add)
        or 0

    curse_damage =
        curse_damage
        + (tonumber(
            combined_projectile.curse
        ) or 0)

    local drill_damage =
        tonumber(action.damage_drill)
        or tonumber(action.damage_drill_add)
        or tonumber(runtime.damage_drill_add)
        or 0

    drill_damage =
        drill_damage
        + (tonumber(
            combined_projectile.drill
        ) or 0)

    add_damage(
        "Projectile dmg",
        projectile_damage
    )

    add_damage(
        "Explosion dmg",
        explosion_damage
    )

    add_damage(
        "Melee dmg",
        melee_damage
    )

    add_damage(
        "Slice dmg",
        slice_damage
    )

    add_damage(
        "Fire dmg",
        fire_damage
    )

    add_damage(
        "Ice dmg",
        ice_damage
    )

    add_damage(
        "Electric dmg",
        electric_damage
    )

    add_damage(
        "Drill dmg",
        drill_damage
    )

    add_damage(
        "Curse dmg",
        curse_damage
    )

    if healing_damage ~= 0 then
        add(
            "Healing",
            JENGA_INTERNAL.format_noita_damage(
                healing_damage
            )
        )
    end

    local critical_chance =
        tonumber(action.damage_critical_chance)
        or tonumber(
            action.damage_critical_chance_add
        )
        or tonumber(
            runtime.damage_critical_chance
        )

    if critical_chance ~= nil
        and critical_chance ~= 0
    then
        add(
            "Critical chance",
            JENGA_INTERNAL.format_spell_stat_number(
                critical_chance
            )
            .. "%"
        )
    end

    local critical_multiplier =
        tonumber(action.damage_critical_multiplier)
        or tonumber(
            runtime.damage_critical_multiplier
        )

    if critical_multiplier ~= nil
        and critical_multiplier ~= 0
    then
        add(
            "Critical multiplier",
            "x"
            .. JENGA_INTERNAL.format_spell_stat_number(
                critical_multiplier
            )
        )
    end

    local cast_delay =
        tonumber(action.fire_rate_wait)
        or tonumber(runtime.fire_rate_wait)

    if cast_delay ~= nil
        and cast_delay ~= 0
    then
        add(
            "Cast delay",
            format_seconds_from_frames(
                cast_delay
            )
        )
    end

    local recharge =
        tonumber(action.reload_time)
        or tonumber(
            runtime.current_reload_time
        )
        or tonumber(runtime.reload_time)

    if recharge ~= nil
        and recharge ~= 0
    then
        add(
            "Recharge",
            format_seconds_from_frames(
                recharge
            )
        )
    end

    local spread =
        tonumber(action.spread_degrees)
        or tonumber(runtime.spread_degrees)

    if spread ~= nil
        and spread ~= 0
    then
        add(
            "Spread",
            JENGA_INTERNAL.format_spell_stat_number(spread)
            .. " DEG"
        )
    end

    local speed_multiplier =
        tonumber(action.speed_multiplier)
        or tonumber(runtime.speed_multiplier)

    if speed_multiplier ~= nil
        and speed_multiplier ~= 1
    then
        add(
            "Speed",
            "x"
            .. JENGA_INTERNAL.format_spell_stat_number(
                speed_multiplier
            )
        )
    elseif combined_projectile.speed_min ~= nil
        or combined_projectile.speed_max ~= nil
    then
        local minimum =
            combined_projectile.speed_min
            or combined_projectile.speed_max

        local maximum =
            combined_projectile.speed_max
            or combined_projectile.speed_min

        add(
            "Base speed",
            JENGA_INTERNAL.format_spell_stat_number(minimum)
            .. (
                maximum ~= minimum
                and (
                    " - "
                    .. JENGA_INTERNAL.format_spell_stat_number(
                        maximum
                    )
                )
                or ""
            )
        )
    end

    local lifetime_add =
        tonumber(action.lifetime_add)
        or tonumber(runtime.lifetime_add)

    if lifetime_add ~= nil
        and lifetime_add ~= 0
    then
        add(
            "Lifetime change",
            tostring(lifetime_add)
            .. " frames"
        )
    elseif combined_projectile.lifetime ~= nil
        and combined_projectile.lifetime ~= 0
    then
        add(
            "Base lifetime",
            tostring(
                combined_projectile.lifetime
            )
            .. " frames"
        )
    end

    local bounces =
        tonumber(action.bounces)
        or tonumber(action.bounces_add)
        or tonumber(runtime.bounces)

    if bounces ~= nil and bounces ~= 0 then
        add(
            "Bounces",
            tostring(bounces)
        )
    end

    local explosion_radius =
        tonumber(action.explosion_radius)
        or tonumber(runtime.explosion_radius)
        or tonumber(
            combined_projectile.explosion_radius
        )

    if explosion_radius ~= nil
        and explosion_radius ~= 0
    then
        add(
            "Explosion radius",
            JENGA_INTERNAL.format_spell_stat_number(
                explosion_radius
            )
        )
    end

    local recoil =
        tonumber(action.recoil_knockback)
        or tonumber(runtime.recoil_knockback)

    if recoil ~= nil and recoil ~= 0 then
        add(
            "Recoil",
            JENGA_INTERNAL.format_spell_stat_number(recoil)
        )
    end

    local knockback =
        tonumber(action.knockback_force)
        or tonumber(runtime.knockback_force)

    if knockback ~= nil
        and knockback ~= 0
    then
        add(
            "Knockback",
            JENGA_INTERNAL.format_spell_stat_number(
                knockback
            )
        )
    end

    if runtime.friendly_fire == true then
        add(
            "Friendly fire",
            "Yes"
        )
    end

    return rows
end

function JENGA_INTERNAL.wrap_text_lines(text_value, max_chars)
    local result = {}
    local current = ""

    text_value = tostring(text_value or "")

    for word in string.gmatch(text_value, "%S+") do
        if current == "" then
            current = word
        elseif #current + #word + 1 <= max_chars then
            current = current .. " " .. word
        else
            table.insert(result, current)
            current = word
        end
    end

    if current ~= "" then
        table.insert(result, current)
    end

    if #result == 0 then
        table.insert(result, "")
    end

    return result
end

function JENGA_INTERNAL.draw_full_spell_card(
    gui,
    spell,
    x,
    y,
    screen_w,
    screen_h
)
    if not is_alive(spell) then
        return
    end

    local card_w = 236
    local description =
        JENGA_INTERNAL.get_spell_description(spell)

    local description_lines =
        JENGA_INTERNAL.wrap_text_lines(description, 35)

    local detail_rows =
        JENGA_INTERNAL.get_spell_detail_rows(spell)

    local details_height =
        math.max(1, #detail_rows) * 10

    local description_y_offset =
        38 + details_height + 8

    local card_h =
        description_y_offset
        + math.max(
            1,
            #description_lines
        ) * 9
        + 8

    x = math.min(
        math.max(8, x),
        screen_w - card_w - 8
    )

    y = math.min(
        math.max(8, y),
        screen_h - card_h - 8
    )

    -- Spell details must sit above the pinned wand and native inventory.
    GuiZSet(gui, -3200)

    GuiImageNinePiece(
        gui,
        930001,
        x,
        y,
        card_w,
        card_h,
        0.99,
        "data/ui_gfx/decorations/9piece0_gray.png",
        "data/ui_gfx/decorations/9piece0_gray.png"
    )

    GuiZSet(gui, -3210)

    local icon = get_spell_icon(spell)

    if type(icon) ~= "string"
        or icon == ""
    then
        icon =
            "data/ui_gfx/inventory/icon_unknown.png"
    end

    GuiImage(
        gui,
        930002,
        x + 10,
        y + 9,
        icon,
        1,
        1,
        0,
        0
    )

    GuiText(
        gui,
        x + 36,
        y + 9,
        get_spell_display_name(spell)
    )

    GuiText(
        gui,
        x + 36,
        y + 20,
        JENGA_INTERNAL.get_spell_type_name(spell)
    )

    local details_y = y + 36

    for index, row in ipairs(detail_rows) do
        local row_y =
            details_y
            + (index - 1) * 10

        GuiText(
            gui,
            x + 10,
            row_y,
            row[1]
        )

        GuiText(
            gui,
            x + 132,
            row_y,
            row[2]
        )
    end

    local description_y =
        y + description_y_offset

    for index, line in ipairs(
        description_lines
    ) do
        GuiText(
            gui,
            x + 10,
            description_y
                + (index - 1) * 9,
            line
        )
    end
end

function JENGA_INTERNAL.draw_pinned_wand_card_impl()
    if not GameIsInventoryOpen() then
        jenga_pinned_wand_entity = 0

        if jenga_pinned_wand_gui ~= nil then
            GuiDestroy(jenga_pinned_wand_gui)
            jenga_pinned_wand_gui = nil
        end

        return false
    end

    if jenga_pinned_wand_gui == nil then
        jenga_pinned_wand_gui = GuiCreate()
    end

    local gui = jenga_pinned_wand_gui

    if gui == nil then
        error("Pinned wand GuiCreate returned nil")
    end

    GuiStartFrame(gui)

    local wands = get_inventory_wands()
    local hovered_wand =
        get_hovered_native_wand(gui, wands)

    if not is_alt_down() then
        jenga_pinned_wand_entity = 0
        return false
    end

    -- While Alt is held, hovering another native wand updates the pin.
    -- Once the cursor leaves the slot, keep the last valid wand pinned.
    if is_alive(hovered_wand) then
        jenga_pinned_wand_entity =
            hovered_wand
    elseif not is_alive(jenga_pinned_wand_entity) then
        -- Fallback for unusual resolutions or UI scales.
        jenga_pinned_wand_entity =
            get_active_wand()
    end

    local wand = jenga_pinned_wand_entity

    if not is_alive(wand) then
        return false
    end

    local screen_w, screen_h =
        GuiGetScreenDimensions(gui)

    local card_w = 220

    local spells = get_pinned_card_spells(wand)
    local spell_columns = 5
    local spell_rows =
        math.max(
            1,
            math.ceil(#spells / spell_columns)
        )

    local spell_row_height = 23
    local card_h =
        145 + (spell_rows - 1) * spell_row_height

    local card_x =
        math.max(8, screen_w - card_w - 12)

    local card_y =
        math.max(
            8,
            math.min(
                math.floor(screen_h * 0.18),
                screen_h - card_h - 8
            )
        )

    GuiZSet(gui, -3000)

    GuiImageNinePiece(
        gui,
        910001,
        card_x,
        card_y,
        card_w,
        card_h,
        0.98,
        "data/ui_gfx/decorations/9piece0_gray.png",
        "data/ui_gfx/decorations/9piece0_gray.png"
    )

    GuiZSet(gui, -3010)

    GuiText(
        gui,
        card_x + 10,
        card_y + 9,
        "JENGA - PINNED WAND"
    )

    GuiText(
        gui,
        card_x + 10,
        card_y + 18,
        "Hold Alt; hover spell icons below"
    )

    local shuffle =
        get_wand_stat_value(
            wand,
            "gun_config",
            "shuffle_deck_when_empty",
            false
        )

    local actions_per_round =
        tonumber(
            get_wand_stat_value(
                wand,
                "gun_config",
                "actions_per_round",
                1
            )
        ) or 1

    local cast_delay =
        get_wand_stat_value(
            wand,
            "gunaction_config",
            "fire_rate_wait",
            0
        )

    local recharge =
        get_wand_stat_value(
            wand,
            "gun_config",
            "reload_time",
            0
        )

    local mana_max =
        tonumber(
            get_wand_stat_value(
                wand,
                nil,
                "mana_max",
                0
            )
        ) or 0

    local mana_charge =
        tonumber(
            get_wand_stat_value(
                wand,
                nil,
                "mana_charge_speed",
                0
            )
        ) or 0

    local capacity = get_wand_capacity(wand)

    local spread =
        tonumber(
            get_wand_stat_value(
                wand,
                "gunaction_config",
                "spread_degrees",
                0
            )
        ) or 0

    local labels = {
        {"Shuffle", shuffle and "Yes" or "No"},
        {"Spells/Cast", tostring(actions_per_round)},
        {"Cast delay", format_seconds_from_frames(cast_delay)},
        {"Rechrg. Time", format_seconds_from_frames(recharge)},
        {"Mana max", tostring(math.floor(mana_max + 0.5))},
        {"Mana Chg. Spd", tostring(math.floor(mana_charge + 0.5))},
        {"Capacity", tostring(capacity)},
        {"Spread", string.format("%.1f DEG", spread)},
    }

    for index, row in ipairs(labels) do
        local y = card_y + 35 + (index - 1) * 11

        GuiText(
            gui,
            card_x + 12,
            y,
            row[1]
        )

        GuiText(
            gui,
            card_x + 118,
            y,
            row[2]
        )
    end

    GuiText(
        gui,
        card_x + 12,
        card_y + 127,
        "Always Casts"
    )

    if #spells == 0 then
        GuiText(
            gui,
            card_x + 87,
            card_y + 126,
            "None"
        )
    else
        GuiZSet(gui, -3020)

        for index, spell in ipairs(spells) do
            local icon = get_spell_icon(spell)

            if type(icon) ~= "string"
                or icon == ""
            then
                icon =
                    "data/ui_gfx/inventory/icon_unknown.png"
            end

            local column =
                (index - 1) % spell_columns

            local row =
                math.floor(
                    (index - 1) / spell_columns
                )

            local icon_x =
                card_x + 87 + column * 22

            local icon_y =
                card_y + 121 + row * spell_row_height

            GuiImageButton(
                gui,
                920000 + index,
                icon_x,
                icon_y,
                "",
                icon
            )

            local _, _, hovered =
                GuiGetPreviousWidgetInfo(gui)

            if hovered then
                JENGA_INTERNAL.draw_full_spell_card(
                    gui,
                    spell,
                    card_x - 238,
                    card_y + row * 8,
                    screen_w,
                    screen_h
                )
            end
        end
    end

    return true
end

function JENGA_INTERNAL.draw_pinned_wand_card()
    local ok, result =
        pcall(JENGA_INTERNAL.draw_pinned_wand_card_impl)

    if ok then
        return result
    end

    jenga_pinned_wand_entity = 0

    if jenga_pinned_wand_gui ~= nil then
        GuiDestroy(jenga_pinned_wand_gui)
        jenga_pinned_wand_gui = nil
    end

    GamePrint(
        "JENGA: Pinned wand card error: "
        .. tostring(result)
    )

    return false
end

function JENGA_INTERNAL.draw_spell_selection_impl()
    local donor = get_int(STORAGE_SELECTION_DONOR)

    if not is_alive(donor) then
        clear_spell_selection()
        save_current_wands(get_inventory_wands())
        return true
    end

    local spells = get_normal_spells(donor)

    local twitch_mode =
        get_gameplay_mode() == "twitch"

    if twitch_mode then
        spells =
            JENGA_INTERNAL.get_unique_vote_spells(
                spells
            )
    end

    if #spells == 0 then
        cancel_spell_selection()
        GamePrint("JENGA: This world wand contains no regular spell.")
        return true
    end

    if jenga_spell_selection_gui == nil then
        jenga_spell_selection_gui = GuiCreate()
    end

    local gui = jenga_spell_selection_gui

    if gui == nil then
        error("GuiCreate returned nil")
    end

    GuiStartFrame(gui)

    local screen_w, screen_h = GuiGetScreenDimensions(gui)

    local columns = 8
    local rows =
        math.max(
            1,
            math.ceil(#spells / columns)
        )

    local cell = 24
    local panel_w =
        math.max(
            230,
            columns * cell + 30
        )

    local votes_per_line = 4
    local vote_line_count =
        math.max(
            1,
            math.ceil(
                #spells / votes_per_line
            )
        )

    local number_row_height =
        twitch_mode and 10 or 0

    local grid_y_offset =
        28 + number_row_height
    local grid_height = rows * cell
    local vote_header_height =
        twitch_mode and 12 or 0

    local vote_rows_height =
        twitch_mode
        and vote_line_count * 10
        or 0

    -- Compact dynamic height: title, spell rows, vote rows, and one button row.
    local panel_h =
        grid_y_offset
        + grid_height
        + vote_header_height
        + vote_rows_height
        + 20

    local panel_x
    local panel_y

    if twitch_mode then
        -- Keep the center of the screen clear while the player continues
        -- moving during the vote.
        panel_x = 8
        panel_y = math.max(
            8,
            screen_h - panel_h - 10
        )
    else
        panel_x =
            math.floor(
                (screen_w - panel_w) * 0.5
            )

        panel_y =
            math.floor(
                (screen_h - panel_h) * 0.5
            )
    end

    -- In Noita, larger Z values are deeper. Keep the panel behind its controls.
    GuiZSet(gui, 100)

    GuiImageNinePiece(
        gui,
        700001,
        panel_x,
        panel_y,
        panel_w,
        panel_h,
        0.96,
        "data/ui_gfx/decorations/9piece0_gray.png",
        "data/ui_gfx/decorations/9piece0_gray.png"
    )

    GuiZSet(gui, 90)

    local title

    if twitch_mode then
        title =
            "JENGA - Twitch vote: send a number"
    else
        title = "JENGA - Choose one spell"
    end
    local title_w = GuiGetTextDimensions(gui, title, 1, 2)

    GuiText(
        gui,
        panel_x + math.floor((panel_w - title_w) * 0.5),
        panel_y + 10,
        title
    )

    local selected_spell = get_int(STORAGE_SELECTION_SPELL)
    local grid_x = panel_x + 16
    local grid_y =
        panel_y + grid_y_offset

    for index, spell_data in ipairs(spells) do
        local spell = spell_data.entity
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local x = grid_x + column * cell
        local y = grid_y + row * cell

        local icon = get_spell_icon(spell)

        if type(icon) ~= "string" or icon == "" then
            icon = "data/ui_gfx/inventory/icon_unknown.png"
        end

        if spell == selected_spell then
            GuiColorSetForNextWidget(gui, 1.0, 0.85, 0.2, 1.0)
            GuiImage(
                gui,
                710000 + index,
                x - 2,
                y - 2,
                "mods/jenga/files/gfx/spell_selection_highlight.png",
                1,
                1,
                0,
                0
            )
        end

        if twitch_mode then
            GuiImage(
                gui,
                720000 + index,
                x,
                y,
                icon,
                1,
                1,
                1,
                0
            )

            local number_text =
                tostring(index)

            local number_w =
                GuiGetTextDimensions(
                    gui,
                    number_text
                )

            GuiColorSetForNextWidget(
                gui,
                1,
                1,
                1,
                1
            )

            GuiText(
                gui,
                x
                    + math.floor(
                        (20 - number_w) * 0.5
                    ),
                y - 10,
                number_text
            )

            GuiTooltip(
                gui,
                get_spell_display_name(spell),
                "Chat option "
                    .. tostring(index)
            )
        else
            local clicked = GuiImageButton(
                gui,
                720000 + index,
                x,
                y,
                "",
                icon
            )

            GuiTooltip(
                gui,
                get_spell_display_name(spell),
                "Click to select this spell."
            )

            if clicked then
                set_int(
                    STORAGE_SELECTION_SPELL,
                    spell
                )

                selected_spell = spell
            end
        end
    end

    local content_bottom =
        grid_y + grid_height

    local footer_y =
        panel_y + panel_h - 14

    if twitch_mode then
        local snapshot =
            get_twitch_snapshot(#spells)

        local vote_header_y =
            content_bottom + 3

        local vote_rows_y =
            vote_header_y + 10

        if snapshot.status == "bridge_missing" then
            GuiText(
                gui,
                panel_x + 12,
                vote_header_y,
                "Connector not running"
            )
        elseif snapshot.status == "waiting" then
            GuiText(
                gui,
                panel_x + 12,
                vote_header_y,
                "Connecting vote..."
            )
        else
            GuiText(
                gui,
                panel_x + 12,
                vote_header_y,
                "Time "
                .. tostring(
                    math.ceil(snapshot.remaining)
                )
                .. "s"
            )

            -- Four compact entries per row, directly below the spell grid.
            local vote_start_x =
                panel_x + 12

            local vote_column_width =
                math.floor(
                    (panel_w - 24)
                    / votes_per_line
                )

            for index = 1, #spells do
                local column =
                    (index - 1)
                    % votes_per_line

                local row =
                    math.floor(
                        (index - 1)
                        / votes_per_line
                    )

                GuiText(
                    gui,
                    vote_start_x
                        + column
                        * vote_column_width,
                    vote_rows_y
                        + row * 10,
                    tostring(index)
                        .. ": "
                        .. tostring(
                            snapshot.votes[index]
                            or 0
                        )
                )
            end
        end

        local winner =
            get_twitch_winner_if_ready(spells)

        if is_alive(winner) then
            set_int(
                STORAGE_SELECTION_SPELL,
                winner
            )

            set_bool(
                STORAGE_TWITCH_PENDING_CONFIRM,
                true
            )

            GamePrint(
                "JENGA: Chat selected "
                .. get_spell_display_name(winner)
                .. "."
            )

            return true
        end
    else
        local selected_name =
            "No spell selected"

        if is_alive(selected_spell) then
            selected_name =
                get_spell_display_name(
                    selected_spell
                )
        end

        GuiText(
            gui,
            panel_x + 14,
            footer_y,
            selected_name
        )

        if selected_spell ~= 0
            and is_alive(selected_spell)
        then
            if GuiButton(
                gui,
                730001,
                panel_x + panel_w - 105,
                footer_y,
                "Confirm"
            ) then
                confirm_spell_selection()
                return true
            end
        end
    end

    if not twitch_mode then
        if GuiButton(
            gui,
            730002,
            panel_x + panel_w - 54,
            footer_y,
            "Cancel"
        ) then
            cancel_spell_selection()
            return true
        end
    end

    return true
end

function JENGA_INTERNAL.draw_spell_selection()
    local ok, result = pcall(JENGA_INTERNAL.draw_spell_selection_impl)

    if ok then
        return result
    end

    local error_message = tostring(result)

    GamePrintImportant(
        "JENGA GUI ERROR",
        error_message
    )

    -- Safely revert the current pickup instead of leaving the inventory
    -- in a partially processed state.
    cancel_spell_selection()

    return true
end

function JENGA_INTERNAL.process_spell_selection()
    if not get_bool(STORAGE_SELECTION_ACTIVE) then
        return false
    end

    -- While any spell selection is active, the normal manual-drop handler is
    -- unreachable because this function returns first. Enforce the same wand
    -- drop rule here for both Normal and Twitch modes.
    do
        local previous_selection_wands =
            load_previous_wands()

        local current_selection_wands =
            get_inventory_wands()

        local removed_selection_wands =
            find_removed_wands(
                previous_selection_wands,
                current_selection_wands
            )

        if #removed_selection_wands > 0 then
            local selection_donor =
                get_int(
                    STORAGE_SELECTION_DONOR
                )

            local selection_target =
                get_int(
                    STORAGE_SELECTION_TARGET
                )

            local selection_stack_zone =
                get_stack_zone_near_player()

            local changed_inventory = false

            for _, dropped_wand in ipairs(
                removed_selection_wands
            ) do
                if is_alive(dropped_wand)
                    and dropped_wand ~= selection_donor
                    and dropped_wand ~= selection_target
                    and EntityHasTag(
                        dropped_wand,
                        "jenga_owned_wand"
                    )
                then
                    local velocity =
                        EntityGetFirstComponentIncludingDisabled(
                            dropped_wand,
                            "VelocityComponent"
                        )

                    if velocity ~= nil then
                        pcall(
                            ComponentSetValue2,
                            velocity,
                            "mVelocity",
                            0,
                            0
                        )
                    end

                    if selection_stack_zone ~= nil then
                        if add_wand_to_stack(
                            dropped_wand,
                            selection_stack_zone
                        ) then
                            changed_inventory = true

                            GamePrint(
                                "JENGA: Wand added to the stack."
                            )
                        end
                    else
                        set_wand_pickable(
                            dropped_wand,
                            true
                        )

                        if pick_up_wand(
                            dropped_wand
                        ) then
                            changed_inventory = true

                            GamePrint(
                                "JENGA: Wands may only be dropped at the JENGA stack during spell selection."
                            )
                        end
                    end
                end
            end

            if changed_inventory then
                save_current_wands(
                    get_inventory_wands()
                )
            end
        end
    end

    if get_bool(
        STORAGE_TWITCH_PENDING_CONFIRM
    ) then
        set_bool(
            STORAGE_TWITCH_PENDING_CONFIRM,
            false
        )

        if confirm_spell_selection() then
            return true
        end

        -- A stale entity should not leave JENGA in a permanent waiting state.
        set_int(
            STORAGE_SELECTION_SPELL,
            0
        )

        cancel_spell_selection()
        return true
    end

    if get_gameplay_mode() == "twitch" then
        -- Movement remains free, but the native inventory must stay closed
        -- so Tinker Wands Everywhere cannot alter the reserved world wand.
        lock_native_inventory_during_selection()
        set_world_wand_selection_lock(true)
    else
        lock_native_inventory_during_selection()
        enforce_spell_selection_pause()
    end

    return JENGA_INTERNAL.draw_spell_selection()
end

-- =========================================================
-- Drop-Sperre
-- =========================================================

local function handle_manual_wand_drops(
    previous,
    current,
    added
)
    -- Bei einem normalen Stabtausch wird gleichzeitig ein neuer
    -- Stab aufgenommen. Der herausfallende alte Stab darf deshalb
    -- hier nicht als manueller Drop behandelt werden.
    if added ~= nil then
        return false
    end

    local removed = find_removed_wands(
        previous,
        current
    )

    if #removed == 0 then
        return false
    end

    local zone = get_stack_zone_near_player()

    for _, wand in ipairs(removed) do
        if is_alive(wand)
            and EntityHasTag(wand, "jenga_owned_wand")
        then
            if zone ~= nil then
                local added_to_stack = add_wand_to_stack(wand, zone)

                if added_to_stack then
                    GamePrint(
                        "JENGA: Wand added to the stack."
                    )

                    try_awaken_stack(zone)
                end
            else
                pick_up_wand(wand)

                GamePrint(
                    "JENGA: Wands can only be dropped at the JENGA stack."
                )
            end
        end
    end

    save_current_wands(get_inventory_wands())

    return true
end

-- =========================================================
-- Initialisierung
-- =========================================================

local function lock_existing_spells_on_wand(wand)
    if not is_alive(wand) then
        return
    end

    local spells = get_normal_spells(wand)

    for _, spell_data in ipairs(spells) do
        lock_spell_to_wand(
            spell_data.entity,
            wand,
            spell_data.slot_x,
            spell_data.slot_y
        )
    end
end

local function initialize_controller()
    local current = get_inventory_wands()

    -- Spells already present on starting or pre-existing wands were not
    -- placed by the player and are therefore fixed immediately.
    for _, wand_data in ipairs(current) do
        local wand = wand_data.entity

        make_wand_owned(wand)
        lock_existing_spells_on_wand(wand)
    end

    save_current_wands(current)
    set_bool(STORAGE_INITIALIZED, true)
end

-- =========================================================
-- Harte Begrenzung auf vier Stäbe
-- =========================================================

local function enforce_four_wand_limit()
    local wands = get_inventory_wands()

    if #wands <= MAX_WAND_SLOTS then
        return false
    end

    -- Normalerweise ist der neu aufgenommene Weltstab der einzige
    -- Stab ohne jenga_owned_wand-Tag.
    local excess_wand = nil

    for index = #wands, 1, -1 do
        local wand = wands[index].entity

        if not EntityHasTag(
            wand,
            "jenga_owned_wand"
        ) then
            excess_wand = wand
            break
        end
    end

    -- Notfall: Falls alle fünf Stäbe als Eigentum markiert sind,
    -- den letzten Stab entfernen.
    if excess_wand == nil then
        excess_wand = wands[#wands].entity
    end

    if is_alive(excess_wand) then
        place_wand_near_player(excess_wand)

        GamePrint(
            "JENGA: You cannot carry more than four wands."
        )
    end

    save_current_wands(
        get_inventory_wands()
    )

    return true
end

-- =========================================================
-- Hauptablauf
-- =========================================================

try_spawn_holy_mountain_stack_zone()

-- A Normal mode selection owns the inventory state until confirmed/cancelled.
if JENGA_INTERNAL.process_spell_selection() then
    return
end

-- Zuerst einen bereits laufenden Tausch abschließen.
if process_pending_operation() then
    return
end

-- Existing wand spells are fixed in place. Loose inventory spells remain
-- available for insertion into empty slots.
update_wand_spell_locks()
synchronize_spell_refresher_charges()

-- Fixed left-side icon and remaining-charge display.
draw_fixed_charge_display()

-- Hover a native wand slot and hold Left Alt to pin its wand card.
JENGA_INTERNAL.draw_pinned_wand_card()

if not get_bool(STORAGE_INITIALIZED) then
    initialize_controller()
    return
end

local previous = load_previous_wands()
local current = get_inventory_wands()

local previous_count = count_entries(previous)
local current_count = #current

local added = find_added_wand(
    previous,
    current
)

-- ---------------------------------------------------------
-- Mehr als vier Stäbe
--
-- Wichtig: Einen neu aufgenommenen fünften Stab nicht sofort
-- entfernen, wenn er gerade als Spender verarbeitet werden soll.
-- Der normale Tauschfall weiter unten muss ihn zuerst erkennen.
-- ---------------------------------------------------------

if current_count > MAX_WAND_SLOTS then
    -- Bei fünf Stäben wurde möglicherweise kein alter Stab aus dem
    -- Inventar removed. In diesem Fall existiert kein gewählter
    -- Zielstab, mit dem ein Zaubertransfer durchgeführt werden könnte.
    enforce_four_wand_limit()
    return
end

-- ---------------------------------------------------------
-- Manuellen Drop behandeln
-- ---------------------------------------------------------

if handle_manual_wand_drops(
    previous,
    current,
    added
) then
    return
end

-- Keine relevante Inventaränderung.
if added == nil then
    save_current_wands(current)
    return
end

local added_wand = added.entity

-- ---------------------------------------------------------
-- Stab wurde aus dem eigenen JENGA-Stapel zurückgenommen
-- ---------------------------------------------------------

if EntityHasTag(
    added_wand,
    "jenga_stacked_wand"
) then
    local returned = return_stacked_wand_to_zone(
        added_wand
    )

    save_current_wands(
        get_inventory_wands()
    )

    if returned then
        GamePrint(
            "JENGA: This wand belongs to the stack and cannot be picked up."
        )
    else
        GamePrint(
            "JENGA: The stacked wand could not be returned to its pedestal."
        )
    end

    return
end

if EntityHasTag(
    added_wand,
    "jenga_owned_wand"
) then
    EntityRemoveTag(added_wand, "jenga_ghost_wand")
    save_current_wands(current)
    GamePrint("JENGA: Recovered wand picked up.")
    return
end

-- ---------------------------------------------------------
-- Pickup-Ziel bestimmen
--
-- Die Zahl freier Slots entscheidet NICHT über die Aktion.
--
-- Wurde ein alter Stab aus dem Inventar removed, hat der Spieler
-- einen belegten Slot gewählt. Dann wird ein Zauber übertragen.
--
-- Wurde kein alter Stab removed und die Anzahl der Inventarstäbe
-- ist um eins gestiegen, wurde ein freier Slot gewählt. Nur dann
-- bleibt der Weltstab erhalten.
-- ---------------------------------------------------------

local removed_wands = find_removed_wands(
    previous,
    current
)

local old_wand = nil

if #removed_wands == 1 then
    old_wand = removed_wands[1]
end

-- ---------------------------------------------------------
-- Fall A: belegter Slot gewählt
-- Gilt bei 1, 2, 3 oder 4 zuvor getragenen Stäben.
-- ---------------------------------------------------------

if is_alive(old_wand) then
    if get_first_free_spell_slot(old_wand) == nil then
        place_wand_near_player(added_wand)

        start_pending_operation(
            PENDING_RESTORE_AFTER_CANCEL,
            old_wand,
            added_wand
        )

        GamePrint(
            "JENGA: This wand is full. Take it to the JENGA stack before collecting another spell."
        )

        return
    end

    local pickup_mode = get_gameplay_mode()

    if pickup_mode == "normal"
        or pickup_mode == "twitch"
    then
        if start_spell_selection(added_wand, old_wand, SELECTION_TRANSFER) then
            return
        end
    end

    if choose_random_normal_spell(added_wand) == nil then
        place_wand_near_player(added_wand)

        start_pending_operation(
            PENDING_RESTORE_AFTER_CANCEL,
            old_wand,
            added_wand
        )

        GamePrint(
            "JENGA: The world wand contains no regular spell."
        )

        return
    end

    local transferred = transfer_random_spell(
        added_wand,
        old_wand
    )

    if not transferred then
        place_wand_near_player(added_wand)

        start_pending_operation(
            PENDING_RESTORE_AFTER_CANCEL,
            old_wand,
            added_wand
        )

        GamePrint(
            "JENGA: This wand is full. Take it to the JENGA stack before collecting another spell."
        )

        return
    end

    make_wand_owned(old_wand)

    -- Weltstab zuerst löschen. Erst danach wird der ursprüngliche
    -- Stab im nächsten Frame wieder aufgenommen.
    if is_alive(added_wand) then
        EntityKill(added_wand)
    end

    start_pending_operation(
        PENDING_RESTORE_AFTER_SUCCESS,
        old_wand,
        added_wand
    )

    GamePrint(
        "JENGA: A random spell was added to the selected wand."
    )

    return
end

-- ---------------------------------------------------------
-- Fall B: freier Slot gewählt
-- Nur hier bleibt der Weltstab erhalten.
-- ---------------------------------------------------------

if previous_count < MAX_WAND_SLOTS
    and current_count == previous_count + 1
then
    local pickup_mode = get_gameplay_mode()

    if pickup_mode == "normal"
        or pickup_mode == "twitch"
    then
        if start_spell_selection(added_wand, 0, SELECTION_KEEP_WAND) then
            return
        end
    end

    local success = trim_wand_to_one_random_spell(
        added_wand
    )

    make_wand_owned(added_wand)

    if success then
        GamePrint(
            "JENGA: World wand acquired; one random spell remains."
        )
    else
        GamePrint(
            "JENGA: This world wand contains no regular spell."
        )
    end

    save_current_wands(
        get_inventory_wands()
    )

    return
end

-- Unbekannter Zustand: neuen Weltstab sicher aus dem Inventar entfernen.
if is_alive(added_wand)
    and not EntityHasTag(
        added_wand,
        "jenga_owned_wand"
    )
then
    place_wand_near_player(added_wand)

    GamePrint(
        "JENGA: Pickup state was ambiguous (before "
        .. tostring(previous_count)
        .. ", after "
        .. tostring(current_count)
        .. ", removed "
        .. tostring(#removed_wands)
        .. ")."
    )
end

save_current_wands(
    get_inventory_wands()
)