-- API structure is still named ScrapIndustry for legacy purposes
assert(ScrapIndustry == nil)
ScrapIndustry = {
	items = {}, -- also fluids
	products = {},
	recipes = {},
	categories = {},
	subgroups = {},
	-- use these constants as values when defining your own scrap byproducts
	FLAVOR = 0.03,
	CHEAP = 0.08,
	COMMON = 0.12,
	PRODUCT = 0.18,
	UNCOMMON = 0.24,
	EXPENSIVE = 0.36,
	RARE = 0.48,
	EPIC = 0.72,
	LEGENDARY = 1.44,
	FLUID_SCALE = 10
}
