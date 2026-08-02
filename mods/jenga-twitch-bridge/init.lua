local bridge_loaded = false

function OnModPreInit()
end

function OnModInit()
end

function OnModPostInit()
end

function OnPlayerSpawned(player_entity)
    if bridge_loaded then
        return
    end

    bridge_loaded = true

    local ok, error_message = pcall(
        dofile,
        "mods/jenga-twitch-bridge/data/ws/bridge.lua"
    )

    if not ok then
        GamePrintImportant(
            "JENGA Twitch Bridge Error",
            tostring(error_message)
        )
    end
end

function OnWorldPostUpdate()
    if type(JengaTwitchBridgeUpdate)
        == "function"
    then
        JengaTwitchBridgeUpdate()
    end
end
