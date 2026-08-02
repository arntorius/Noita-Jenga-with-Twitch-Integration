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
