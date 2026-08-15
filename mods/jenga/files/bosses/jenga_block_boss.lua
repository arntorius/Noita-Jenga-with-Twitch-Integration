
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
    0.72,
    0.52
)

local frame =
    GameGetFrameNum()

local last =
    JENGA_BOSS_COMMON.get_int(
        entity_id,
        "jenga_last_aoe_frame",
        frame
    )

if JENGA_BOSS_COMMON.get_storage(
    entity_id,
    "jenga_last_aoe_frame"
) == nil
then
    JENGA_BOSS_COMMON.set_int(
        entity_id,
        "jenga_last_aoe_frame",
        frame
    )

    return
end

if frame - last < 180 then
    return
end

JENGA_BOSS_COMMON.set_int(
    entity_id,
    "jenga_last_aoe_frame",
    frame
)

local x, y =
    EntityGetTransform(entity_id)

EntityLoad(
    "mods/jenga/files/bosses/jenga_block_pulse.xml",
    x,
    y
)

-- The pulse entity itself applies one normal Noita damage event.
-- This preserves damage numbers, red vignette and normal hit feedback.
