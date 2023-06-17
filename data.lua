data:extend{
    {
        type = "item-subgroup",
        name = "train-control-signals",
        group = "signals",
        order = "f"
    },
    {
        type = "virtual-signal",
        name = "refuel-signal",
        localised_name = {"refuel-signal"},
        localised_description = {"refuel-signal-description"},
        icon = "__More_Train_Control_Signals__/graphics/refuel-icon.png",
        icon_size = 64,
        icon_mipmaps = 1,
        subgroup = "train-control-signals",
        order = "aa"
    },
    {
        type = "virtual-signal",
        name = "depot-signal",
        localised_name = {"depot-signal"},
        localised_description = {"depot-signal-description"},
        icon = "__More_Train_Control_Signals__/graphics/depot-icon.png",
        icon_size = 64,
        icon_mipmaps = 1,
        subgroup = "train-control-signals",
        order = "ba"
    },
    {
        type = "virtual-signal",
        name = "skip-signal",
        localised_name = {"skip-signal"},
        localised_description = {"skip-signal-description"},
        icon = "__More_Train_Control_Signals__/graphics/skip-icon.png",
        icon_size = 64,
        icon_mipmaps = 1,
        subgroup = "train-control-signals",
        order = "ca"
    },
    {
        type = "virtual-signal",
        name = "load-signal",
        localised_name = {"load-signal"},
        localised_description = {"load-signal-description"},
        icons = {
            {
                icon = "__base__/graphics/icons/locomotive.png"
            },
            {
                icon = "__More_Train_Control_Signals__/graphics/load-icon.png",
            }
        },
        icon_size = 64,
        icon_mipmaps = 1,
        subgroup = "train-control-signals",
        order = "da"
    },
    {
        type = "virtual-signal",
        name = "unload-signal",
        localised_name = {"unload-signal"},
        localised_description = {"unload-signal-description"},
        icons = {
            {
                icon = "__base__/graphics/icons/locomotive.png"
            },
            {
                icon = "__More_Train_Control_Signals__/graphics/unload-icon.png",
            }
        }, 
        icon_size = 64,
        icon_mipmaps = 1,
        subgroup = "train-control-signals",
        order = "ea"
    },
    {
        type = "virtual-signal",
        name = "priority-signal",
        localised_name = {"priority-signal"},
        localised_description = {"priority-signal-description"},
        icon = "__More_Train_Control_Signals__/graphics/priority-icon.png",
        icon_size = 64,
        icon_mipmaps = 1,
        subgroup = "train-control-signals",
        order = "fa"
    },
    {
        type = "virtual-signal",
        name = "optional-signal",
        localised_name = {"optional-signal"},
        localised_description = {"optional-signal-description"},
        icon = "__More_Train_Control_Signals__/graphics/optional-icon.png", 
        icon_size = 64,
        icon_mipmaps = 1,
        subgroup = "train-control-signals",
        order = "ga"
    },
}