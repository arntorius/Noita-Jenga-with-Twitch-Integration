
dofile_once(
    "mods/jenga/files/bosses/jenga_boss_common.lua"
)

local entity_id =
    GetUpdatedEntityID()

if EntityHasTag(
    entity_id,
    "jenga_large_setup_done"
) then
    return
end

-- The large block inherits Neva-Aave (slimespirit), not Utu-Aave.
-- This preserves the polished spirit death/drop/material behavior while
-- ensuring the large block never carries the Confusion aura.
-- Neva-Aave is used only as a convenient death/drop/material base.
-- Remove its live aura completely from the whole entity tree so the large
-- JENGA block has no Slimy/Confusion-style proximity effect, visually or
-- mechanically.
local function remove_live_spirit_aura(entity)
    if entity == nil
        or entity == 0
        or not EntityGetIsAlive(entity)
    then
        return
    end

    for _, area_effect in ipairs(
        EntityGetComponentIncludingDisabled(
            entity,
            "GameAreaEffectComponent"
        ) or {}
    ) do
        EntityRemoveComponent(
            entity,
            area_effect
        )
    end

    -- Persistent Aave aura visuals are ParticleEmitterComponents. Removing
    -- them from the living entity/children does not remove death scripts or
    -- loot components, which remain inherited from slimespirit.
    for _, emitter in ipairs(
        EntityGetComponentIncludingDisabled(
            entity,
            "ParticleEmitterComponent"
        ) or {}
    ) do
        EntityRemoveComponent(
            entity,
            emitter
        )
    end

    for _, child in ipairs(
        EntityGetAllChildren(entity) or {}
    ) do
        remove_live_spirit_aura(
            child
        )
    end
end

remove_live_spirit_aura(
    entity_id
)

-- Hide the vanilla Neva-Aave body while preserving its death/loot/material behavior.
for _, sprite in ipairs(
    EntityGetComponentIncludingDisabled(
        entity_id,
        "SpriteComponent"
    ) or {}
) do
    EntitySetComponentIsEnabled(
        entity_id,
        sprite,
        false
    )
end

EntityAddComponent2(
    entity_id,
    "SpriteComponent",
    {
        image_file =
            "mods/jenga/files/gfx/jenga_awakened_block_large.png",
        offset_x = 12.5,
        offset_y = 3,
        z_index = 1,
    }
)

local damage_model =
    EntityGetFirstComponentIncludingDisabled(
        entity_id,
        "DamageModelComponent"
    )

if damage_model ~= nil then
    ComponentSetValue2(
        damage_model,
        "max_hp",
        10.0
    )

    ComponentSetValue2(
        damage_model,
        "hp",
        10.0
    )
end

EntityAddTag(entity_id, "hittable")
EntityAddTag(entity_id, "mortal")
EntityAddTag(entity_id, "homing_target")

-- Add the existing JENGA large-block movement/AoE script. The inherited
-- Neva-Aave supplies its vanilla spirit death/drop behavior and Slimy aura.
EntityAddComponent2(
    entity_id,
    "LuaComponent",
    {
        script_source_file =
            "mods/jenga/files/bosses/jenga_block_boss.lua",
        execute_every_n_frame = 1,
        remove_after_executed = false,
    }
)

EntityAddTag(
    entity_id,
    "jenga_large_setup_done"
)
