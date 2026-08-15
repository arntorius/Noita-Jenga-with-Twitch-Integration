ModLuaFileAppend(
    "data/scripts/gun/gun_actions.lua",
    "mods/jenga/files/jenga_active_wand_charges.lua"
)

local MOD_PATH = "mods/jenga"

local twitch_fallback_checked = false

local function ensure_available_gameplay_mode()
    if twitch_fallback_checked then
        return
    end

    twitch_fallback_checked = true

    if ModSettingGet("jenga.mode") ~= "twitch" then
        return
    end

    local bridge_enabled = false

    if type(ModIsEnabled) == "function" then
        local ok, enabled = pcall(
            ModIsEnabled,
            "jenga-twitch-bridge"
        )

        bridge_enabled =
            ok and enabled == true
    end

    if bridge_enabled then
        return
    end

    ModSettingSet(
        "jenga.mode",
        "normal"
    )

    GamePrintImportant(
        "JENGA",
        "Twitch Bridge not enabled. Gameplay mode changed to Normal."
    )
end


local POLY_WAND_LOCK_TAG =
    "jenga_polymorph_wand_pickup_lock"

local POLY_WAND_LOCK_RADIUS = 96

local function get_item_component(entity)
    if entity == nil
        or entity == 0
        or not EntityGetIsAlive(entity)
    then
        return nil
    end

    return EntityGetFirstComponentIncludingDisabled(
        entity,
        "ItemComponent"
    )
end

local function set_wand_pickable_for_poly(
    wand,
    pickable
)
    local item_component =
        get_item_component(wand)

    if item_component == nil then
        return
    end

    ComponentSetValue2(
        item_component,
        "is_pickable",
        pickable == true
    )
end

local function is_near_polymorphed_player(
    wand,
    polymorphed_players
)
    local wand_x, wand_y =
        EntityGetTransform(wand)

    for _, poly_player in ipairs(
        polymorphed_players
    ) do
        if EntityGetIsAlive(poly_player) then
            local poly_x, poly_y =
                EntityGetTransform(poly_player)

            local dx = wand_x - poly_x
            local dy = wand_y - poly_y

            if dx * dx + dy * dy
                <= POLY_WAND_LOCK_RADIUS
                * POLY_WAND_LOCK_RADIUS
            then
                return true
            end
        end
    end

    return false
end

function OnWorldPreUpdate()
    local polymorphed_players =
        EntityGetWithTag(
            "polymorphed_player"
        ) or {}

    -- Restore only wands that JENGA itself disabled for polymorph safety.
    -- Stack and selection locks are never overridden.
    for _, wand in ipairs(
        EntityGetWithTag(
            POLY_WAND_LOCK_TAG
        ) or {}
    ) do
        if EntityGetIsAlive(wand) then
            local keep_locked =
                #polymorphed_players > 0
                and is_near_polymorphed_player(
                    wand,
                    polymorphed_players
                )

            if not keep_locked then
                EntityRemoveTag(
                    wand,
                    POLY_WAND_LOCK_TAG
                )

                if not EntityHasTag(
                    wand,
                    "jenga_stacked_wand"
                )
                    and not EntityHasTag(
                        wand,
                        "jenga_selection_pickup_locked"
                    )
                then
                    set_wand_pickable_for_poly(
                        wand,
                        true
                    )
                end
            end
        end
    end

    if #polymorphed_players == 0 then
        return
    end

    -- A polymorphed player can otherwise use the native item pickup logic.
    -- Disable only nearby pickable wands and remember exactly which wands
    -- were changed by this guard.
    for _, poly_player in ipairs(
        polymorphed_players
    ) do
        if EntityGetIsAlive(poly_player) then
            local x, y =
                EntityGetTransform(
                    poly_player
                )

            local nearby_wands =
                EntityGetInRadiusWithTag(
                    x,
                    y,
                    POLY_WAND_LOCK_RADIUS,
                    "wand"
                ) or {}

            for _, wand in ipairs(
                nearby_wands
            ) do
                if EntityGetIsAlive(wand)
                    and not EntityHasTag(
                        wand,
                        "jenga_stacked_wand"
                    )
                    and not EntityHasTag(
                        wand,
                        "jenga_selection_pickup_locked"
                    )
                then
                    local item_component =
                        get_item_component(wand)

                    if item_component ~= nil
                        and ComponentGetValue2(
                            item_component,
                            "is_pickable"
                        ) == true
                    then
                        set_wand_pickable_for_poly(
                            wand,
                            false
                        )

                        EntityAddTag(
                            wand,
                            POLY_WAND_LOCK_TAG
                        )
                    end
                end
            end
        end
    end
end

function OnPlayerSpawned(player_entity)
    if player_entity == nil or player_entity == 0 then
        return
    end

    ensure_available_gameplay_mode()

    if EntityHasTag(
        player_entity,
        "jenga_controller_attached"
    ) then
        return
    end

    EntityAddTag(
        player_entity,
        "jenga_controller_attached"
    )

    local x, y =
        EntityGetTransform(player_entity)

    local controller =
        EntityLoad(
            MOD_PATH .. "/files/controller.xml",
            x,
            y
        )

    if controller ~= nil
        and controller ~= 0
    then
        EntityAddChild(
            player_entity,
            controller
        )
    end
end

-- JENGA custom enemy progress registration.
-- Noita's Progress > Enemies screen is driven by data/ui_gfx/animal_icons/_list.txt.
local function jenga_register_progress_enemy(enemy_id, after_id)
    local path =
        "data/ui_gfx/animal_icons/_list.txt"

    local content =
        ModTextFileGetContent(path)

    if content == nil
        or content == ""
    then
        return
    end

    for line in content:gmatch(
        "[^\r\n]+"
    ) do
        if line == enemy_id then
            return
        end
    end

    local entries = {}

    for line in content:gmatch(
        "[^\r\n]+"
    ) do
        entries[#entries + 1] = line
    end

    local inserted = false

    if after_id ~= nil then
        for index = 1, #entries do
            if entries[index] == after_id then
                table.insert(
                    entries,
                    index + 1,
                    enemy_id
                )

                inserted = true
                break
            end
        end
    end

    if not inserted then
        entries[#entries + 1] =
            enemy_id
    end

    ModTextFileSetContent(
        path,
        table.concat(
            entries,
            "\n"
        )
    )
end

jenga_register_progress_enemy(
    "jenga_block_boss",
    "confusespirit"
)

jenga_register_progress_enemy(
    "jenga_confusion_boss",
    "jenga_block_boss"
)
