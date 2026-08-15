
dofile_once(
    "mods/jenga/files/bosses/jenga_boss_common.lua"
)

local entity_id =
    GetUpdatedEntityID()

local player =
    JENGA_BOSS_COMMON.get_player()

if player == 0 then
    return
end

JENGA_BOSS_COMMON.move(
    entity_id,
    player,
    0.82,
    0.62
)
