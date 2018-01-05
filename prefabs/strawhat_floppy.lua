-- AUTOGENERATED CODE BY export_accountitems.lua

local assets =
{
	Asset("DYNAMIC_ANIM", "anim/dynamic/strawhat_floppy.zip"),
}

return CreatePrefabSkin("strawhat_floppy",
{
	base_prefab = "strawhat",
	type = "item",
	assets = assets,
	build_name = "strawhat_floppy",
	rarity = "Elegant",
	init_fn = function(inst) strawhat_init_fn(inst, "strawhat_floppy") end,
	skin_tags = { "STRAWHAT", "CRAFTABLE", },
	marketable = true,
	release_group = 14,
	granted_items = { "minerhat_floppy", "rainhat_floppy", },
})