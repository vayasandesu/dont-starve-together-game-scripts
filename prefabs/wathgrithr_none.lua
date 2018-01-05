-- AUTOGENERATED CODE BY export_accountitems.lua

local assets =
{
	Asset("ANIM", "anim/ghost_wathgrithr_build.zip"),
	Asset("ANIM", "anim/wathgrithr.zip"),
}

return CreatePrefabSkin("wathgrithr_none",
{
	base_prefab = "wathgrithr",
	type = "base",
	assets = assets,
	build_name = "wathgrithr",
	rarity = "Common",
	skin_tags = { "BASE", "CHARACTER", "WATHGRITHR", },
	skins = { ghost_skin = "ghost_wathgrithr_build", normal_skin = "wathgrithr", },
	release_group = 999,
})