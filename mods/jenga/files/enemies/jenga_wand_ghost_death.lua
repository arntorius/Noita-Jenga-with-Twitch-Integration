local ghost = GetUpdatedEntityID()

if ghost == nil or ghost == 0 then
    return
end

local function make_wand_recoverable(entity)
    if entity == nil
        or entity == 0
        or not EntityGetIsAlive(entity)
    then
        return
    end

    local is_wand =
        EntityHasTag(entity, "wand")
        or EntityGetFirstComponentIncludingDisabled(
            entity,
            "AbilityComponent"
        ) ~= nil

    if not is_wand then
        return
    end

    EntityRemoveTag(entity, "jenga_stacked_wand")
    EntityRemoveTag(entity, "jenga_ghost_pending_wand")
    EntityRemoveTag(entity, "jenga_ghost_wand")

    local item_component =
        EntityGetFirstComponentIncludingDisabled(
            entity,
            "ItemComponent"
        )

    if item_component ~= nil then
        ComponentSetValue2(
            item_component,
            "is_pickable",
            true
        )
    end
end

local assigned_wand = 0

for _, component in ipairs(
    EntityGetComponentIncludingDisabled(
        ghost,
        "VariableStorageComponent"
    ) or {}
) do
    if ComponentGetValue2(
        component,
        "name"
    ) == "jenga_assigned_wand" then
        assigned_wand = ComponentGetValue2(
            component,
            "value_int"
        ) or 0
    end
end

make_wand_recoverable(assigned_wand)

for _, child in ipairs(EntityGetAllChildren(ghost) or {}) do
    make_wand_recoverable(child)

    for _, grandchild in ipairs(
        EntityGetAllChildren(child) or {}
    ) do
        make_wand_recoverable(grandchild)
    end
end
