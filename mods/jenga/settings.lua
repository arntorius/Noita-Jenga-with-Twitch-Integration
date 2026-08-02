dofile("data/scripts/lib/mod_settings.lua")

local mod_id = "jenga"
mod_settings_version = 2

local gameplay_mode_values = {
    { "random", "Random" },
    { "normal", "Normal" },
    { "twitch", "Twitch" },
}

local gameplay_mode_description =
    "Random chooses automatically. Normal lets you choose. Twitch requires the optional JENGA Twitch Bridge and connector."

mod_settings = {
    {
        id = "spell_inspector_heading",
        ui_name = "Wand spell inspector:",
        value_default = "",
        scope = MOD_SETTING_SCOPE_RUNTIME,
        not_setting = true,
    },
    {
        id = "spell_inspector_instructions",
        ui_name = "Open inventory, select a wand, then hold Left Alt.",
        value_default = "",
        scope = MOD_SETTING_SCOPE_RUNTIME,
        not_setting = true,
    },

    {
        id = "mode",
        ui_name = "Gameplay mode",
        ui_description = gameplay_mode_description,
        value_default = "normal",
        values = gameplay_mode_values,
        scope = MOD_SETTING_SCOPE_RUNTIME,
    },
}

function ModSettingsUpdate(init_scope)
    mod_settings_update(
        mod_id,
        mod_settings,
        init_scope
    )
end

function ModSettingsGuiCount()
    return mod_settings_gui_count(mod_id, mod_settings)
end

function ModSettingsGui(gui, in_main_menu)
    mod_settings_gui(mod_id, mod_settings, gui, in_main_menu)
end
