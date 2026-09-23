return {
    schema = 1,
    scenarios = {
        {
            id = "cook.transfer.container.success",
            modes = { offline = true, gameSp = true },
            invariants = { "item-conserved", "destination-owns-item", "session-terminal" },
        },
        {
            id = "cook.recipe.replacement.success",
            modes = { offline = true, gameSp = true },
            invariants = { "item-conserved", "replacement-owned", "session-terminal" },
        },
        {
            id = "cook.stove.ownership.success",
            modes = { offline = true, gameSp = true },
            invariants = { "owned-stove-cleanup", "other-dishes-preserved", "session-terminal" },
        },
        {
            id = "cook.stove.preexisting.success",
            modes = { offline = true, gameSp = true },
            invariants = { "preexisting-stove-preserved", "dish-cooked", "session-terminal" },
        },
    },
}
