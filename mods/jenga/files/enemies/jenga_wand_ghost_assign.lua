local ghost = GetUpdatedEntityID()

if ghost == nil
    or ghost == 0
    or not EntityGetIsAlive(ghost)
then
    return
end

local function get_storage_int(name)
    local components = EntityGetComponentIncludingDisabled(
        ghost,
        "VariableStorageComponent"
    ) or {}

    for _, component in ipairs(components) do
        if ComponentGetValue2(component, "name") == name then
            return ComponentGetValue2(
                component,
                "value_int"
            ) or 0
        end
    end

    return 0
end

local wand = get_storage_int("jenga_assigned_wand")
local zone = get_storage_int("jenga_stack_zone")

if wand == 0 or not EntityGetIsAlive(wand) then
    return
end

local inventory = nil

for _, child in ipairs(EntityGetAllChildren(ghost) or {}) do
    if EntityGetName(child) == "inventory_quick" then
        inventory = child
        break
    end
end

-- Der Vanilla-Geist braucht eventuell einige Frames,
-- bis sein Inventar vollständig initialisiert wurde.
if inventory == nil then
    return
end

-- Eventuell vom Vanilla-Geist erzeugte Stäbe entfernen.
for _, item in ipairs(EntityGetAllChildren(inventory) or {}) do
    if item ~= wand then
        local is_wand =
            EntityHasTag(item, "wand")
            or EntityGetFirstComponentIncludingDisabled(
                item,
                "AbilityComponent"
            ) ~= nil

        if is_wand then
            EntityKill(item)
        end
    end
end

local item_component =
    EntityGetFirstComponentIncludingDisabled(
        wand,
        "ItemComponent"
    )

if item_component ~= nil then
    ComponentSetValue2(
        item_component,
        "is_pickable",
        true
    )
end

EntityRemoveTag(wand, "jenga_ghost_pending_wand")
EntityRemoveTag(wand, "jenga_stacked_wand")
EntityAddTag(wand, "jenga_ghost_wand")

GamePickUpInventoryItem(
    ghost,
    wand,
    false
)

-- Erst beenden, wenn der Stab tatsächlich im Geist-Inventar liegt.
if EntityGetParent(wand) == inventory then
    local components = EntityGetComponentIncludingDisabled(
        ghost,
        "LuaComponent"
    ) or {}

    for _, component in ipairs(components) do
        local source = ComponentGetValue2(
            component,
            "script_source_file"
        )

        if source ==
            "mods/jenga/files/enemies/jenga_wand_ghost_assign.lua"
        then
            EntityRemoveComponent(ghost, component)
            break
        end
    end
end
