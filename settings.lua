data:extend({
	{
		type = "double-setting",
		name = "scraptk-byproduct-scale",
		setting_type = "startup",
		default_value = 1,
		minimum_value = 0.1,
		maximum_value = 2,
		order = "a[byproduct]-b[scale]"
	},
	{
		type = "bool-setting",
		name = "scraptk-byproduct-rounding",
		setting_type = "startup",
		default_value = false,
		order = "a[byproduct]-b[rounding]"
	},
	{
		type = "bool-setting",
		name = "scraptk-handcraft",
		setting_type = "startup",
		default_value = true,
		order = "c[misc]-b[handcraft]"
	},
	{
		type = "bool-setting",
		name = "scraptk-failrate-enable",
		setting_type = "startup",
		default_value = true,
		order = "b[failrate]-a[enabled]"
	},
	{
		type = "double-setting",
		name = "scraptk-failrate-scale",
		setting_type = "startup",
		default_value = 1,
		minimum_value = 0.1,
		maximum_value = 5,
		order = "b[failrate]-b[scale]"
	},
	{
		type = "double-setting",
		name = "scraptk-failrate-min",
		setting_type = "startup",
		default_value = 0.01,
		minimum_value = 0,
		maximum_value = 0.2,
		order = "b[failrate]-c[min]"
	}
})
