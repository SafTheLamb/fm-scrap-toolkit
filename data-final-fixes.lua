local global_byproduct_scale = settings.startup["scraptk-byproduct-scale"].value
local global_failrate_scale = settings.startup["scraptk-failrate-scale"].value
local global_failrate_min = settings.startup["scraptk-failrate-min"].value

for _,item_metadata in pairs(ScrapIndustry.items) do
	ScrapIndustry.convert_to_stk(item_metadata)
end

local function get_ingredient_scrap(ingredient, out)
	local item_metadata = ScrapIndustry.items[ingredient.name]
	if item_metadata then
		for scrap_name,scale in pairs(item_metadata.scrap or {}) do
			-- Don't add byproducts that are already a result
			if out.recipe_results[scrap_name] then
				goto continue
			end
			-- If we're in fluid mode, only accept byproducts from fluid inputs OR fluid byproducts
			if out.fluid_mode then
				if ingredient.type ~= "fluid" then
					local product_metadata = ScrapIndustry.products[scrap_name]
					if not (product_metadata and product_metadata.type == "fluid") then
						goto continue
					end
				end
			end
			-- Calculate how much scrap
			local amount = scale * (ingredient.amount or ((ingredient.amount_min + ingredient.amount_max)/2))
			if ingredient.type == "fluid" then
				amount = amount / ScrapIndustry.FLUID_SCALE
			end
			amount = global_byproduct_scale * amount
			amount = math.floor(100 * amount + 0.5) / 100
			-- Accumulate the scrap
			out.byproducts[scrap_name] = (out.byproducts[scrap_name] or 0) + amount
			out.total_scrap = out.total_scrap + amount
			::continue::
		end
		-- Failrate is still calculated per ingredient, not per byproduct
		if item_metadata.failrate then
			out.success_penalty = (out.success_penalty or 0) + item_metadata.failrate
		end
	end
end


local function can_modify_recipe(recipe)
	if recipe.si_ignore then
		recipe.si_ignore = nil
		return false
	end

	if not recipe.results or #recipe.results == 0 then
		return false
	end

	local recipe_metadata = ScrapIndustry.recipes[recipe.name] or {}
	if recipe_metadata.ignore then
		return false
	end
	if recipe_metadata.force or recipe_metadata.self_scrap then
		return true
	end

	if recipe.category then
		local category_metadata = ScrapIndustry.categories[recipe.category] or {}
		if category_metadata.ignore then
			return false
		end
	end

	local subgroup_metadata = ScrapIndustry.subgroups[recipe.subgroup]
	if subgroup_metadata and subgroup_metadata.ignore then
		return false
	end

	for _,result in pairs(recipe.results) do
		local product_metadata = ScrapIndustry.products[result.name]
		if product_metadata and product_metadata.ignore then
			return false
		end
	end
	return true
end

-- if a recipe has an ingredient whose recipe was modified to have a % failrate, it can't be considered as an intermediate for the hand-crafting queue
-- to resolve this, we create hidden duplicates for these recipes
local handcraft_recipes = {}
local handcraft_categories = {}
local handcraft_recipe_map = {}
if settings.startup["scraptk-handcraft"].value then
	for _,category in pairs(data.raw.character.character.crafting_categories) do
		handcraft_categories[category] = true
	end
end

local function should_duplicate_for_hand_crafting(recipe, recipe_metadata, out)
	if not settings.startup["scraptk-handcraft"].value then
		return false
	end
	if recipe.allow_as_intermediate == false then
		return false
	end
	if recipe.hide_from_player_crafting then
		return false
	end
	if recipe_metadata and type(recipe_metadata.force_handcraft) == "boolean" then
		return recipe_metadata.force_handcraft
	end
	if out.success_penalty == 0 then
		return false
	end
	local category = recipe.category or "crafting"
	return handcraft_categories[category] == true
end

-- copied from recycling.lua
local function get_prototype(base_type, name)
	for type_name in pairs(defines.prototypes[base_type]) do
		local prototypes = data.raw[type_name]
		if prototypes and prototypes[name] then
			return prototypes[name]
		end
	end
end

local function get_item_localised_name(name)
	local item = get_prototype("item", name)
	if not item then return {"item-name."..name} end
	if item.localised_name then
		return item.localised_name
	end
	local prototype
	local type_name = "item"
	if item.place_result then
		prototype = get_prototype("entity", item.place_result)
		type_name = "entity"
	elseif item.place_as_equipment_result then
		prototype = get_prototype("equipment", item.place_as_equipment_result)
		type_name = "equipment"
	elseif item.place_as_tile then
		-- Tiles with variations don't have a localised name
		local tile_prototype = data.raw.tile[item.place_as_tile.result]
		if tile_prototype and tile_prototype.localised_name then
			prototype = tile_prototype
			type_name = "tile"
		end
	end
	return prototype and prototype.localised_name or {type_name.."-name."..name}
end

local function duplicate_for_hand_crafting(recipe)
	local duplicate_recipe = util.table.deepcopy(recipe)
	duplicate_recipe.name = recipe.name.."-hand-crafted"
	
	if not duplicate_recipe.localised_name then
		local main_product = util.get_recipe_main_product(recipe)
		if main_product then
			duplicate_recipe.localised_name = get_item_localised_name(main_product.name)
			for _,result in pairs(duplicate_recipe.results) do
				if result.name == main_product.name then
					result.probability = nil
				end
			end
		else
			duplicate_recipe.localised_name = {"recipe-name."..recipe.name}
		end
	end
	duplicate_recipe.localised_name = {"recipe-name.hand-crafted", duplicate_recipe.localised_name}
	duplicate_recipe.category = "hand-crafting"
	duplicate_recipe.hidden = true
	table.insert(handcraft_recipes, duplicate_recipe)
	handcraft_recipe_map[recipe.name] = duplicate_recipe.name
	duplicate_recipe.si_ignore = true
	return duplicate_recipe
end

--------------------------------------------------------------------------------------------------

-- Before replacing, figure out the maximum fluid amount a recipe can produce with and respect that before modifying
local category_max_fluids = {}
for _,entity in pairs(data.raw["assembling-machine"]) do
  local fluid_box_count = 0
  for _,fluid_box in pairs(entity.fluid_boxes or {}) do
    -- Don't need to check input-output for the production_type, since that's only for boilers
    if fluid_box.production_type == "output" then
      fluid_box_count = fluid_box_count + 1
    end
  end

  -- Update categories the entity can craft, ESPECIALLY if the machine can't accept any fluids
  for _,category_name in pairs(entity.crafting_categories or {}) do
    if category_name ~= "crafting" then
      -- Get the smallest of the max fluid inputs
      if not category_max_fluids[category_name] then
        category_max_fluids[category_name] = fluid_box_count
      else
        category_max_fluids[category_name] = math.min(fluid_box_count, category_max_fluids[category_name])
      end
    end
  end
end

-- If a recipe has no item products, then only calculate byproducts from fluids or are themselves fluids
local function check_fluid_mode(recipe, out)
	local fluid_mode = true
	for _,result in pairs(recipe.results) do
		if result.type == "item" then
			fluid_mode = false
		end
	end
	if fluid_mode then
		out.fluid_mode = true
	end
end

local function check_fluid_count(recipe, out)
	-- If we haven't initialized the maximum number of fluids, then do so
	if out.max_fluids == nil then
		out.max_fluids = category_max_fluids[recipe.category]
		for _,category in pairs(recipe.additional_categories or {}) do
			if category_max_fluids[category] then
				out.max_fluids = math.min(category_max_fluids[category], out.max_fluids)
			end
		end
		if out.max_fluids == nil then
			out.max_fluids = 0
		end
	end

	-- If we haven't initialized the current number of fluid results, then do so
	if out.fluid_count == nil then
		out.fluid_count = 0
		for _, result in pairs(recipe.results) do
			if result.type == "fluid" then
				out.fluid_count = out.fluid_count + 1
			end
		end
	end

	return out.fluid_count + 1 <= out.max_fluids
end

local function get_fluidbox_index(recipe, out)
	if out.fluidbox_indices ~= nil then
		-- If we haven't initialized the mapping of fluidbox indices, then do so
		if next(out.fluidbox_indices) == nil then
			for _,result in pairs(recipe.results) do
				if result.fluidbox_index then
					out.fluidbox_indices[result.fluidbox_index] = true
				end
			end
			-- If we didn't find any fluidbox indices, then we don't need to set one
			if next(out.fluidbox_indices) == nil then
				out.fluidbox_indices = nil
				return
			end
		end

		-- Find the first fluidbox index that isn't set
		for i=1,out.max_fluids do
			if not out.fluidbox_indices[i] then
				out.fluidbox_indices[i] = true
				return i
			end
		end
	else
		-- We've checked the results and fluidbox indices aren't set
		return nil
	end
end

--------------------------------------------------------------------------------------------------

-- exclude science packs
local science_packs = {}
for _,lab in pairs(data.raw.lab) do
	if lab.inputs then
		for i=1,#lab.inputs do
			science_packs[lab.inputs[i]] = true
		end
	end
end

for recipe_name,recipe in pairs(data.raw.recipe) do
	if recipe.results and not ScrapIndustry.recipes[recipe_name] then
		for _,result in pairs(recipe.results) do
			if science_packs[result.name] then
				ScrapIndustry.recipes[recipe_name] = {ignore=true}
				break
			end
		end
	end
end

--------------------------------------------------------------------------------------------------

for _,recipe in pairs(data.raw.recipe) do
	if can_modify_recipe(recipe) then
		local out = {
			byproducts = {},
			recipe_results = {},
			fluidbox_indices = {},
			total_scrap = 0,
			success_penalty = 0
		}
		check_fluid_mode(recipe, out)

		local recipe_metadata = ScrapIndustry.recipes[recipe.name] or {}
		local category_metadata = ScrapIndustry.categories[recipe.category or "crafting"] or {}
		if recipe_metadata.self_scrap or category_metadata.self_scrap then
			for _,result in pairs(recipe.results) do
				get_ingredient_scrap(result, out)
			end
		elseif recipe_metadata.fake_ingredients then
			for _,result in pairs(recipe_metadata.fake_ingredients) do
				get_ingredient_scrap(result, out)
			end
		else
			for _,result in pairs(recipe.results) do
				out.recipe_results[result.name] = true
			end
			for _,ingredient in pairs(recipe.ingredients or {}) do
				get_ingredient_scrap(ingredient, out)
			end
		end

		if type(recipe_metadata.failrate) == "number" then
			out.success_penalty = recipe_metadata.failrate
		elseif out.total_scrap > 0 then
			local failrate_scale = 1 / (out.total_scrap / (2*ScrapIndustry.LEGENDARY))
			if failrate_scale < 1 then
				out.success_penalty = math.max(math.ceil(failrate_scale * out.success_penalty * 100) / 100, global_failrate_min)
			end
			out.success_penalty = math.max(global_failrate_scale * out.success_penalty, global_failrate_min)
		end
	
		local cancel_gen = false
		for _,result in pairs(recipe.results) do
			if result.si_modified then
				cancel_gen = true
				break
			elseif result.type == "item" then
				local probability_scale = 1 - (out.success_penalty or 0)
				if probability_scale < 1 then
					if result.probability then
						result.probability = result.probability * probability_scale
					else
						result.probability = probability_scale
					end
					result.si_modified = true
				end
			elseif out.fluid_mode and result.type == "fluid" then
				local min_scale = 1 - (out.success_penalty or 0)
				if min_scale < 1 then
					result.amount_max = result.amount_max or result.amount
					result.amount_min = min_scale * (result.amount_min or result.amount)
					result.amount = nil
					result.si_modified = true
				end
			end
		end

		if (not cancel_gen and next(out.byproducts) ~= nil) then
			local excluded_result = ""
			if table_size(out.byproducts) > 3 then
				-- if there are a lot of scrap results, get rid of the least important one (biased by scrap amount)
				local lowest_priority = 1
				for scrap_name,scrap_amount in pairs(out.byproducts) do
					local product_metadata = ScrapIndustry.products[scrap_name]
					local priority = (product_metadata and product_metadata.priority or 1) + scrap_amount
					if priority < lowest_priority then
						lowest_priority = priority
						excluded_result = scrap_name
					end
				end
			end
			if not recipe.main_product then
				local main_product = util.get_recipe_main_product(recipe)
				if main_product then
					recipe.main_product = main_product.name
				end
			end
			for scrap_name,scrap_amount in pairs(out.byproducts) do
				if scrap_name ~= excluded_result and scrap_amount > 0 then
					local product_metadata = ScrapIndustry.products[scrap_name]
					local product_type = product_metadata and product_metadata.type or "item"
					local halved_amount = scrap_amount / 0.5
					local random_scale = 1 + 0.12 * (1 - 2 * math.random())
					local probability = math.floor(100 * random_scale * scrap_amount / math.ceil(halved_amount)) / 100
					local final_amount = halved_amount / 0.5
					local fluidbox_index = nil
					if product_type == "fluid" then
						final_amount = ScrapIndustry.FLUID_SCALE * final_amount
						if not recipe.category or recipe.category == "crafting" then
							recipe.category = "crafting-with-fluid"
						end
						-- Check if the recipe can support more fluid results
						if not check_fluid_count(recipe, out) then
							goto continue
						end
						-- Check for fluidbox indices in the results
						fluidbox_index = get_fluidbox_index(recipe, out)
						out.fluid_count = out.fluid_count + 1
					end
					if final_amount > 1 then final_amount = math.sqrt(final_amount) end
					local amount_min = math.max(1, math.floor(0.9 * final_amount + 0.5))
					local amount_max = math.max(1, math.floor(1.1 * final_amount + 0.5))
					local result = {type=product_type, name=scrap_name, probability=probability, show_details_in_recipe_tooltip=false}
					if amount_min ~= amount_max then
						result.amount_min = amount_min
						result.amount_max = amount_max
						result.ignored_by_productivity=amount_max
					else
						result.amount = math.ceil(final_amount)
						result.ignored_by_productivity=result.amount
					end
					result.si_modified = true
					result.fluidbox_index = fluidbox_index
					table.insert(recipe.results, result)
				end
				::continue::
			end
		end

		if should_duplicate_for_hand_crafting(recipe, recipe_metadata, out) then
			duplicate_for_hand_crafting(recipe)
		end
	end
end

--------------------------------------------------------------------------------------------------

if table_size(handcraft_recipes) > 0 then
	if not handcraft_categories["hand-crafting"] then
		data:extend({
			{
				type = "recipe-category",
				name = "hand-crafting"
			}
		})
		for _,character in pairs(data.raw.character) do
			if character.crafting_categories then
				table.insert(character.crafting_categories, "hand-crafting")
			end
		end
		table.insert(data.raw["god-controller"].default.crafting_categories, "hand-crafting")
	end
	for _,tech in pairs(data.raw.technology) do
		for _,effect in pairs(tech.effects or {}) do
			local new_recipe = effect.type == "unlock-recipe" and handcraft_recipe_map[effect.recipe]
			if new_recipe then
				table.insert(tech.effects, {type="unlock-recipe", recipe=new_recipe, hidden=true})
			end
		end
	end
	data:extend(handcraft_recipes)
end

-------------------------------------------------------------------------- Recycling recipe overrides

local default_machine_tints = {primary = {0.125,0.125,0.125,0.125}, secondary = {0.125,0.125,0.125,0.125}, tertiary = {0.125,0.125,0.125,0.125}, quaternary = {0.125,0.125,0.125,0.125}}

if mods["quality"] then
	for item_name,item_metadata in pairs(ScrapIndustry.items) do
		local item = data.raw.item[item_name]
		if item and item_metadata.recycle then
			-- Find the main byproduct
			local main_byproduct = nil
			local highest_scale = 0
			for scrap_name,scale in pairs(item_metadata.scrap) do
				if scale > highest_scale then
					main_byproduct = scrap_name
					highest_scale = scale
				end
			end
			if main_byproduct then
				local icons = generate_recycling_recipe_icons_from_item(item)
				local crafting_machine_tint = data.raw.recipe[item.name] and data.raw.recipe[item.name].crafting_machine_tint or default_machine_tints
				local amount = math.ceil(item_metadata.recycle/4)
				local probability = 0.5*(item_metadata.recycle/4)/amount
				probability = math.ceil(probability*1000)/1000
				data:extend({
					{
						type = "recipe",
						name = item.name.."-recycling",
						localised_name = {"recipe-name.recycling", get_item_localised_name(item.name)},
						icons = icons,
						category = "recycling",
						subgroup = item.subgroup,
						hidden = true,
						enabled = true,
						unlock_results = false,
						allow_decomposition = false,
						ingredients = {{type="item", name=item_name, amount=1, ignored_by_stats=1}},
						results = {{type="item", name=main_byproduct, amount=amount, probability=probability, ignored_by_stats=amount}},
						energy_required = (data.raw.recipe[item_name] and data.raw.recipe[item_name].energy_required or 0.5)/16,
						crafting_machine_tint = crafting_machine_tint
					},
				})
			end
		end
	end
end
