
JENGA_BOSS_COMMON =
    JENGA_BOSS_COMMON or {}

function JENGA_BOSS_COMMON.get_storage(
    entity_id,
    name
)
    for _, component in ipairs(
        EntityGetComponentIncludingDisabled(
            entity_id,
            "VariableStorageComponent"
        ) or {}
    ) do
        if ComponentGetValue2(
            component,
            "name"
        ) == name
        then
            return component
        end
    end

    return nil
end

function JENGA_BOSS_COMMON.get_string(
    entity_id,
    name,
    default_value
)
    local component =
        JENGA_BOSS_COMMON.get_storage(
            entity_id,
            name
        )

    if component == nil then
        return default_value
    end

    return ComponentGetValue2(
        component,
        "value_string"
    ) or default_value
end

function JENGA_BOSS_COMMON.get_int(
    entity_id,
    name,
    default_value
)
    local component =
        JENGA_BOSS_COMMON.get_storage(
            entity_id,
            name
        )

    if component == nil then
        return default_value
    end

    return ComponentGetValue2(
        component,
        "value_int"
    ) or default_value
end

function JENGA_BOSS_COMMON.set_int(
    entity_id,
    name,
    value
)
    local component =
        JENGA_BOSS_COMMON.get_storage(
            entity_id,
            name
        )

    if component == nil then
        component =
            EntityAddComponent2(
                entity_id,
                "VariableStorageComponent",
                {
                    name = name,
                    value_int = value,
                }
            )
    else
        ComponentSetValue2(
            component,
            "value_int",
            value
        )
    end
end

function JENGA_BOSS_COMMON.get_player()
    for _, entity in ipairs(
        EntityGetWithTag(
            "player_unit"
        ) or {}
    ) do
        if EntityGetIsAlive(entity) then
            return entity
        end
    end

    for _, entity in ipairs(
        EntityGetWithTag(
            "polymorphed_player"
        ) or {}
    ) do
        if EntityGetIsAlive(entity) then
            return entity
        end
    end

    return 0
end

function JENGA_BOSS_COMMON.apply_leggy_once(
    entity_id
)
    if EntityHasTag(
        entity_id,
        "jenga_leggy_applied"
    ) then
        return
    end

    EntityAddTag(
        entity_id,
        "jenga_leggy_applied"
    )

    dofile_once(
        "data/scripts/perks/perk.lua"
    )

    local x, y =
        EntityGetTransform(entity_id)

    local perk =
        perk_spawn(
            x,
            y,
            "LEGGY_FEET"
        )

    if perk ~= nil
        and perk ~= 0
        and EntityGetIsAlive(perk)
    then
        perk_pickup(
            perk,
            entity_id,
            EntityGetName(perk),
            false,
            false
        )
    end
end

function JENGA_BOSS_COMMON.fly_toward_player(
    entity_id,
    player,
    speed
)
    local x, y =
        EntityGetTransform(entity_id)

    local tx, ty =
        EntityGetTransform(player)

    local dx = tx - x
    local dy = ty - y
    local distance_sq =
        dx * dx + dy * dy

    if distance_sq < 1 then
        return
    end

    local distance =
        math.sqrt(distance_sq)

    local frame =
        GameGetFrameNum()

    local rotation =
        math.sin(
            frame * 0.06
            + entity_id * 0.13
        ) * 0.12

    EntitySetTransform(
        entity_id,
        x + dx / distance * speed,
        y + dy / distance * speed,
        rotation
    )
end

function JENGA_BOSS_COMMON.walk_toward_player(
    entity_id,
    player,
    speed
)
    JENGA_BOSS_COMMON
        .apply_leggy_once(
            entity_id
        )

    local x, y =
        EntityGetTransform(entity_id)

    local tx, ty =
        EntityGetTransform(player)

    local direction =
        tx >= x
        and 1
        or -1

    -- Leggy supplies the visible limbs. The small horizontal push makes the
    -- enemy reliably pursue even if the inherited perk locomotion idles.
    EntitySetTransform(
        entity_id,
        x + direction * speed,
        y
    )
end

function JENGA_BOSS_COMMON.move(
    entity_id,
    player,
    fly_speed,
    walk_speed
)
    local mode =
        JENGA_BOSS_COMMON.get_string(
            entity_id,
            "jenga_movement_mode",
            "fly"
        )

    if mode == "leggy" then
        JENGA_BOSS_COMMON
            .walk_toward_player(
                entity_id,
                player,
                walk_speed
            )
    else
        JENGA_BOSS_COMMON
            .fly_toward_player(
                entity_id,
                player,
                fly_speed
            )
    end
end
