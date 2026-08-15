
local entity_id =
    GetUpdatedEntityID()

local frame =
    GameGetFrameNum()

local storage =
    EntityGetFirstComponentIncludingDisabled(
        entity_id,
        "VariableStorageComponent"
    )

if storage == nil then
    EntityAddComponent2(
        entity_id,
        "VariableStorageComponent",
        {
            name = "jenga_birth_frame",
            value_int = frame,
        }
    )

    local x, y =
        EntityGetTransform(entity_id)

    for _, player in ipairs(
        EntityGetWithTag(
            "player_unit"
        ) or {}
    ) do
        if EntityGetIsAlive(player) then
            local px, py =
                EntityGetTransform(player)

            local dx = px - x
            local dy = py - y

            if dx * dx + dy * dy
                <= 75 * 75
            then
                EntityInflictDamage(
                    player,
                    1.2,
                    "DAMAGE_PROJECTILE",
                    "JENGA block pulse",
                    "NONE",
                    0,
                    0,
                    entity_id,
                    x,
                    y,
                    0
                )
            end
        end
    end

    return
end

local birth =
    ComponentGetValue2(
        storage,
        "value_int"
    ) or frame

local age = frame - birth

if age >= 20 then
    EntityKill(entity_id)
    return
end

local sprite =
    EntityGetFirstComponentIncludingDisabled(
        entity_id,
        "SpriteComponent"
    )

if sprite ~= nil then
    ComponentSetValue2(
        sprite,
        "alpha",
        math.max(
            0,
            0.8 * (1 - age / 20)
        )
    )
end
