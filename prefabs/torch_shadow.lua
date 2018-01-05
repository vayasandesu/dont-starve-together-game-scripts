-- AUTOGENERATED CODE BY export_accountitems.lua

local assets =
{
	Asset("DYNAMIC_ANIM", "anim/dynamic/torch_shadow.zip"),
}

return CreatePrefabSkin("torch_shadow",
{
	base_prefab = "torch",
	type = "item",
	assets = assets,
	build_name = "torch_shadow",
	rarity = "Timeless",
	prefabs = { "torchfire_shadow", },
	init_fn = function(inst) torch_init_fn(inst, "torch_shadow") end,
	skin_tags = { "TORCH", "SHADOW", "CRAFTABLE", },
	fx_prefab = { "torchfire_shadow", },
	release_group = 6,
})