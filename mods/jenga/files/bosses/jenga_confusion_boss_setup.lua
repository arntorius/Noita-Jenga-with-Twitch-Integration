
dofile_once(
    "mods/jenga/files/bosses/jenga_boss_common.lua"
)

local entity_id =
    GetUpdatedEntityID()

if EntityHasTag(
    entity_id,
    "jenga_confusion_setup_done"
) then
    return
end

-- Hide vanilla Utu-Aave body sprites while keeping all of its actual AI,
-- particle effects and confusion aura components/scripts alive.
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
            "mods/jenga/files/gfx/jenga_awakened_block_small.png",
        offset_x = 4.5,
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
        3.0
    )

    ComponentSetValue2(
        damage_model,
        "hp",
        3.0
    )
end


-- Keep the real vanilla Utu-Aave confusion behavior, but shrink both the
-- gameplay area and its persistent visual aura across the complete vanilla
-- entity tree. Some Aave visuals live on child entities rather than the root.
local function shrink_utu_aura(entity, factor)
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
        local radius =
            ComponentGetValue2(
                area_effect,
                "radius"
            )

        if radius ~= nil
            and radius > 0
        then
            ComponentSetValue2(
                area_effect,
                "radius",
                radius * factor
            )
        end
    end

    for _, emitter in ipairs(
        EntityGetComponentIncludingDisabled(
            entity,
            "ParticleEmitterComponent"
        ) or {}
    ) do
        pcall(
            function()
                local x_min =
                    ComponentGetValue2(
                        emitter,
                        "x_pos_offset_min"
                    )

                local x_max =
                    ComponentGetValue2(
                        emitter,
                        "x_pos_offset_max"
                    )

                local y_min =
                    ComponentGetValue2(
                        emitter,
                        "y_pos_offset_min"
                    )

                local y_max =
                    ComponentGetValue2(
                        emitter,
                        "y_pos_offset_max"
                    )

                if x_min ~= nil then
                    ComponentSetValue2(
                        emitter,
                        "x_pos_offset_min",
                        x_min * factor
                    )
                end

                if x_max ~= nil then
                    ComponentSetValue2(
                        emitter,
                        "x_pos_offset_max",
                        x_max * factor
                    )
                end

                if y_min ~= nil then
                    ComponentSetValue2(
                        emitter,
                        "y_pos_offset_min",
                        y_min * factor
                    )
                end

                if y_max ~= nil then
                    ComponentSetValue2(
                        emitter,
                        "y_pos_offset_max",
                        y_max * factor
                    )
                end
            end
        )

        pcall(
            function()
                local radius_min =
                    ComponentObjectGetValue2(
                        emitter,
                        "area_circle_radius",
                        "min"
                    )

                local radius_max =
                    ComponentObjectGetValue2(
                        emitter,
                        "area_circle_radius",
                        "max"
                    )

                if radius_min ~= nil then
                    ComponentObjectSetValue2(
                        emitter,
                        "area_circle_radius",
                        "min",
                        radius_min * factor
                    )
                end

                if radius_max ~= nil then
                    ComponentObjectSetValue2(
                        emitter,
                        "area_circle_radius",
                        "max",
                        radius_max * factor
                    )
                end
            end
        )
    end

    for _, child in ipairs(
        EntityGetAllChildren(entity) or {}
    ) do
        shrink_utu_aura(
            child,
            factor
        )
    end
end

-- Use 0.5 again, but now on the complete vanilla hierarchy rather than only
-- the root entity.
shrink_utu_aura(
    entity_id,
    0.5
)

EntityAddTag(
    entity_id,
    "hittable"
)

EntityAddTag(
    entity_id,
    "mortal"
)

EntityAddTag(
    entity_id,
    "homing_target"
)

-- Add our movement script in parallel. Vanilla confusespirit behavior remains,
-- but our 50/50 movement mode can steer the JENGA body.
EntityAddComponent2(
    entity_id,
    "LuaComponent",
    {
        script_source_file =
            "mods/jenga/files/bosses/jenga_confusion_boss_move.lua",
        execute_every_n_frame = 1,
        remove_after_executed = false,
    }
)

EntityAddTag(
    entity_id,
    "jenga_confusion_setup_done"
)
