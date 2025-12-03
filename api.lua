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

--- Converts all entries in the provided item_metadata to the scraptk format
---@param item_metadata table ScrapIndustry.items entry to update
function ScrapIndustry.convert_to_stk(item_metadata)
	local scale = item_metadata.scale or ScrapIndustry.COMMON
	if type(item_metadata.scrap) == "string" then
		local scrap_name = item_metadata.scrap
		item_metadata.scrap = {}
		item_metadata.scrap[scrap_name] = scale
	elseif type(item_metadata.scrap) == "table" then
		-- Convert all entries
		local n = #item_metadata.scrap
		for i=1,n do
			local scrap_name = item_metadata.scrap[i]
			assert(type(scrap_name) == "string", "Invalid use of Scrap Toolkit API")
			item_metadata.scrap[scrap_name] = (item_metadata.scrap[scrap_name] or 0) + scale
			item_metadata.scrap[i] = nil
		end
	else
		assert(false, "Invalid use of Scrap Toolkit API")
		item_metadata = {scrap={}}
	end
end

--- Initializes or converts the item metadata of the given name
---@param ingredient_name string Name of the ingredient (ScrapIndustry.items[ingredient_name])
local function check_item_metadata(ingredient_name)
	if not ScrapIndustry.items[ingredient_name] then
		ScrapIndustry.items[ingredient_name] = {scrap={}}
	else
		ScrapIndustry.convert_to_stk(ScrapIndustry.items[ingredient_name])
	end
end

--- Add a byproducts from recipes that consume an ingredient
---@param ingredient_name string Name of the ingredient (ScrapIndustry.items[ingredient_name])
---@param scrap_name string Name of the byproduct to add (e.g. "iron-scrap")
---@param scale float Scale for the new byproduct (e.g. ScrapIndustry.COMMON) If an entry already exists, the new scale is added to the existing value
function ScrapIndustry.add_byproduct(ingredient_name, scrap_name, scale)
	assert(type(ingredient_name) == "string", "Invalid use of Scrap Toolkit API")
	assert(type(byproduct_name) == "string", "Invalid use of Scrap Toolkit API")
	assert(type(scale) == "number", "Invalid use of Scrap Toolkit API")

	check_item_metadata(ingredient_name)
	local item_metadata = ScrapIndustry.items[ingredient_name]
	item_metadata.scrap[scrap_name] = (item_metadata.scrap[scrap_name] or 0) + scale
end

--- Add a failrate from recipes that consume an ingredient
---@param ingredient_name string Name of the ingredient (ScrapIndustry.items[ingredient_name])
---@param failrate float Failrate for the ingredient (0-1)
function ScrapIndustry.add_failrate(ingredient_name, failrate)
	assert(type(ingredient_name) == "string", "Invalid use of Scrap Toolkit API")
	assert(type(failrate) == "number", "Invalid use of Scrap Toolkit API")

	check_item_metadata(ingredient_name)
	local item_metadata = ScrapIndustry.items[ingredient_name]
	item_metadata.failrate = (item_metadata.failrate or 0) + failrate
end
