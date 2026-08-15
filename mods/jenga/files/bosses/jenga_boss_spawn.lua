
JENGA_BOSSES =
    JENGA_BOSSES or {}

function JENGA_BOSSES.set_mode(
    entity_id,
    mode
)
    if entity_id == nil
        or entity_id == 0
        or not EntityGetIsAlive(entity_id)
    then
        return
    end

    EntityAddComponent2(
        entity_id,
        "VariableStorageComponent",
        {
            name = "jenga_movement_mode",
            value_string = mode,
        }
    )
end

function JENGA_BOSSES.random_mode()
    if Random(0, 1) == 0 then
        return "fly"
    end

    return "leggy"
end

function JENGA_BOSSES.spawn_for_stack(
    zone,
    wand_count
)
    if zone == nil
        or zone == 0
        or not EntityGetIsAlive(zone)
    then
        return
    end

    local x, y =
        EntityGetTransform(zone)

    SetRandomSeed(
        math.floor(
            x + wand_count * 137
        ),
        math.floor(
            y + GameGetFrameNum() * 31
        )
    )

    local large_count = 1
    local small_count =
        Random(1, 3)

    if wand_count >= 10 then
        large_count =
            Random(1, 3)

        small_count =
            Random(1, 6)
    end

    for index = 1, large_count do
        local offset_x =
            (
                index
                - (large_count + 1) * 0.5
            ) * 24

        local boss =
            EntityLoad(
                "mods/jenga/files/bosses/jenga_block_boss.xml",
                x + offset_x,
                y - 30 - index * 3
            )

        JENGA_BOSSES.set_mode(
            boss,
            JENGA_BOSSES.random_mode()
        )
    end

    for index = 1, small_count do
        local row =
            math.floor(
                (index - 1) / 2
            )

        local side =
            index % 2 == 1
            and -1
            or 1

        local boss =
            EntityLoad(
                "mods/jenga/files/bosses/jenga_confusion_boss.xml",
                x + side * (15 + row * 8),
                y - 12 - row * 9
            )

        JENGA_BOSSES.set_mode(
            boss,
            JENGA_BOSSES.random_mode()
        )
    end

    GamePrint(
        "JENGA: The stack itself has come alive!"
    )
end
