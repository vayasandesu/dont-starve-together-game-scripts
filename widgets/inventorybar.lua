require "class"
local InvSlot = require "widgets/invslot"
local TileBG = require "widgets/tilebg"
local Image = require "widgets/image"
local Widget = require "widgets/widget"
local EquipSlot = require "widgets/equipslot"
local ItemTile = require "widgets/itemtile"
local Text = require "widgets/text"
local ThreeSlice = require "widgets/threeslice"
local HudCompass = require "widgets/hudcompass"

local TEMPLATES = require "widgets/templates"

local HUD_ATLAS = "images/hud.xml"
local W = 68
local SEP = 12
local YSEP = 8
local INTERSEP = 28

local CURSOR_STRING_DELAY = 10
local TIP_YFUDGE = 16
local HINT_UPDATE_INTERVAL = 2.0 -- once per second

local Inv = Class(Widget, function(self, owner)
    Widget._ctor(self, "Inventory")
    self.owner = owner

    self.out_pos = Vector3(0,W,0)
    self.in_pos = Vector3(0,W*1.5,0)

    self.base_scale = .6
    self.selected_scale = .8

    self:SetScale(self.base_scale)
    self:SetPosition(0,-16,0)

    self.inv = {}
    self.backpackinv = {}
    self.equip = {}
    self.equipslotinfo = {}

    self.root = self:AddChild(Widget("root"))

    self.hudcompass = self.root:AddChild(HudCompass(owner, true))
    self.hudcompass:SetScale(1.5, 1.5)
    self.hudcompass:SetMaster()

	if TheNet:GetServerGameMode() == "lavaarena" then
	    self.base_scale = .55
		self:SetScale(self.base_scale)
	    self:SetPosition(0,0,0)

		self.bg = self.root:AddChild(Image("images/lavaarena_hud.xml", "lavaarena_inventorybar.tex"))
		self.bgcover = self.root:AddChild(Widget("dummy"))
		self.in_pos = Vector3(41,W*1.5,0)
	elseif TheNet:GetServerGameMode() == "quagmire" then
		self.bg = self.root:AddChild(Image("images/quagmire_hud.xml", "inventory_bg.tex"))
		self.bgcover = self.root:AddChild(Widget("dummy"))
		self.in_pos = Vector3(0,72,0)
	    self.base_scale = .75
		self.selected_scale = .8
	    self:SetScale(self.base_scale)
	else
		self.bg = self.root:AddChild(Image(HUD_ATLAS, "inventory_bg.tex"))
		self.bgcover = self.root:AddChild(Image(HUD_ATLAS, "inventory_bg_cover.tex"))
	end
	
    self.hovertile = nil
    self.cursortile = nil

    self.repeat_time = .2

    --this is for the keyboard / controller inventory controls
    self.actionstring = self.root:AddChild(Widget("actionstring"))
    self.actionstring:SetScaleMode(SCALEMODE_PROPORTIONAL)

    self.actionstringtitle = self.actionstring:AddChild(Text(TALKINGFONT, 35))
    self.actionstringtitle:SetColour(204/255, 180/255, 154/255, 1)

    self.actionstringbody = self.actionstring:AddChild(Text(TALKINGFONT, 25))
    self.actionstringbody:EnableWordWrap(true)
    self.actionstring:Hide()

    --default equip slots
	if TheNet:GetServerGameMode() == "quagmire" then
		self:AddEquipSlot(EQUIPSLOTS.HANDS, HUD_ATLAS, "equip_slot.tex")
	else
		self:AddEquipSlot(EQUIPSLOTS.HANDS, HUD_ATLAS, "equip_slot.tex")
		self:AddEquipSlot(EQUIPSLOTS.BODY, HUD_ATLAS, "equip_slot_body.tex")
		self:AddEquipSlot(EQUIPSLOTS.HEAD, HUD_ATLAS, "equip_slot_head.tex")
	end

    self.inst:ListenForEvent("builditem", function(inst, data) self:OnBuild() end, self.owner)
    self.inst:ListenForEvent("itemget", function(inst, data) self:OnItemGet(data.item, self.inv[data.slot], data.src_pos, data.ignore_stacksize_anim) end, self.owner)
    self.inst:ListenForEvent("equip", function(inst, data) self:OnItemEquip(data.item, data.eslot) end, self.owner)
    self.inst:ListenForEvent("unequip", function(inst, data) self:OnItemUnequip(data.item, data.eslot) end, self.owner)
    self.inst:ListenForEvent("newactiveitem", function(inst, data) self:OnNewActiveItem(data.item) end, self.owner)
    self.inst:ListenForEvent("itemlose", function(inst, data) self:OnItemLose(self.inv[data.slot]) end, self.owner)
    self.inst:ListenForEvent("refreshinventory", function() self:Refresh() end, self.owner)

    self.root:SetPosition(self.in_pos)
    self:StartUpdating()

    self.actionstringtime = CURSOR_STRING_DELAY

    self.openhint = self:AddChild(Text(UIFONT, 52))
    self.openhint:SetRegionSize(300, 60)
    self.openhint:SetHAlign(ANCHOR_LEFT)
	if TheNet:GetServerGameMode() == "quagmire" then
	    self.openhint:SetPosition(400, 70, 0)
	else
	    self.openhint:SetPosition(940, 70, 0)
	end

    self.hint_update_check = HINT_UPDATE_INTERVAL

    self.controller_build = nil
    self.force_single_drop = false
end)

function Inv:AddEquipSlot(slot, atlas, image, sortkey)
    sortkey = sortkey or #self.equipslotinfo
    table.insert(self.equipslotinfo, {slot = slot, atlas = atlas, image = image, sortkey = sortkey})
    table.sort(self.equipslotinfo, function(a,b) return a.sortkey < b.sortkey end)
    self.rebuild_pending = true
end

local function BackpackGet(inst, data)
    local owner = ThePlayer
    if owner ~= nil and owner.HUD ~= nil and owner.replica.inventory:IsHolding(inst) then
        local inv = owner.HUD.controls.inv
        if inv ~= nil then
            inv:OnItemGet(data.item, inv.backpackinv[data.slot], data.src_pos, data.ignore_stacksize_anim)
        end
    end
end

local function BackpackLose(inst, data)
    local owner = ThePlayer
    if owner ~= nil and owner.HUD ~= nil and owner.replica.inventory:IsHolding(inst) then
        local inv = owner.HUD.controls.inv
        if inv ~= nil then
            inv:OnItemLose(inv.backpackinv[data.slot])
        end
    end
end


local function RebuildLayout_Quagmire(self, inventory, overflow, do_integrated_backpack, do_self_inspect)
	local inv_scale = 1
	local inv_w = 68 * inv_scale
	local inv_sep = 10 * inv_scale
	local inv_y = -77
	local inv_tip_y = inv_w + inv_sep + (30 * inv_scale)

    local num_slots = inventory:GetNumSlots()
    local x = -165
    for k = 1, num_slots do
        self.inv[k] = InvSlot(k, HUD_ATLAS, "inv_slot.tex", self.owner, self.owner.replica.inventory)
		local slot = self.toprow:AddChild(Widget("slot_scaler"..k))
		slot:AddChild(self.inv[k])
        slot:SetPosition(x, inv_y)
		slot:SetScale(inv_scale)
        slot.top_align_tip = inv_w + inv_sep + 30 -- tooltip text offset when using cursors

        local item = inventory:GetItemInSlot(k)
        if item ~= nil then
            self.inv[k]:SetTile(ItemTile(item))
        end

        x = x + 83
    end


	x = x 

	local equip_scale = 0.8
	local equip_y = -74

    local hand_slot = self.equipslotinfo[1]
    local slot = EquipSlot(hand_slot.slot, hand_slot.atlas, hand_slot.image, self.owner)
    slot:SetPosition(x, equip_y)
	slot.highlight_scale = 1
	slot.base_scale = equip_scale
	slot:SetScale(equip_scale)


    self.equip[hand_slot.slot] = self.toprow:AddChild(slot)

    local item = inventory:GetEquippedItem(hand_slot.slot)
    if item ~= nil then
        slot:SetTile(ItemTile(item))
    end


    self.toprow:SetPosition(0, 75)
    self.bg:SetPosition(0, 15)

    self.root:SetPosition(self.in_pos)
    self:UpdatePosition()
end

local function RebuildLayout(self, inventory, overflow, do_integrated_backpack, do_self_inspect)
    local y = overflow ~= nil and ((W + YSEP) / 2) or 0
    local eslot_order = {}

    local num_slots = inventory:GetNumSlots()
    local num_equip = #self.equipslotinfo
    local num_buttons = do_self_inspect and 1 or 0
    local num_slotintersep = math.ceil(num_slots / 5)
    local num_equipintersep = num_buttons > 0 and 1 or 0
    local total_w = (num_slots + num_equip + num_buttons) * W + (num_slots + num_equip + num_buttons - num_slotintersep - num_equipintersep - 1) * SEP + (num_slotintersep + num_equipintersep) * INTERSEP

	local x = (W - total_w) * .5 + num_slots * W + (num_slots - num_slotintersep) * SEP + num_slotintersep * INTERSEP
    for k, v in ipairs(self.equipslotinfo) do
        local slot = EquipSlot(v.slot, v.atlas, v.image, self.owner)
        self.equip[v.slot] = self.toprow:AddChild(slot)
        slot:SetPosition(x, 0, 0)
        table.insert(eslot_order, slot)

        local item = inventory:GetEquippedItem(v.slot)
        if item ~= nil then
            slot:SetTile(ItemTile(item))
        end

        if v.slot == EQUIPSLOTS.HANDS then
            self.hudcompass:SetPosition(x, do_integrated_backpack and 80 or 40, 0)
        end

        x = x + W + SEP
    end

    x = (W - total_w) * .5
    for k = 1, num_slots do
        local slot = InvSlot(k, HUD_ATLAS, "inv_slot.tex", self.owner, self.owner.replica.inventory)
        self.inv[k] = self.toprow:AddChild(slot)
        slot:SetPosition(x, 0, 0)
        slot.top_align_tip = W * .5 + YSEP

        local item = inventory:GetItemInSlot(k)
        if item ~= nil then
            slot:SetTile(ItemTile(item))
        end

        x = x + W + (k % 5 == 0 and INTERSEP or SEP)
    end

    local image_name = "self_inspect_"..self.owner.prefab..".tex"
    local atlas_name = "images/avatars/self_inspect_"..self.owner.prefab..".xml"
    if softresolvefilepath(atlas_name) == nil then
        atlas_name = "images/hud.xml"
    end

    if do_self_inspect then
        self.bg:SetScale(1.22, 1, 1)
        self.bgcover:SetScale(1.22, 1, 1)

        self.inspectcontrol = self.root:AddChild(TEMPLATES.IconButton(atlas_name, image_name, STRINGS.UI.HUD.INSPECT_SELF, false, false, function() self.owner.HUD:InspectSelf() end, nil, "self_inspect_mod.tex"))
        self.inspectcontrol.icon:SetScale(.7)
        self.inspectcontrol.icon:SetPosition(-4, 6)
        self.inspectcontrol:SetScale(1.25)
        self.inspectcontrol:SetPosition((total_w - W) * .5 + 3, -6, 0)
    else
        self.bg:SetScale(1.15, 1, 1)
        self.bgcover:SetScale(1.15, 1, 1)

        if self.inspectcontrol ~= nil then
            self.inspectcontrol:Kill()
            self.inspectcontrol = nil
        end
    end

    local hadbackpack = self.backpack ~= nil
    if hadbackpack then
        self.inst:RemoveEventCallback("itemget", BackpackGet, self.backpack)
        self.inst:RemoveEventCallback("itemlose", BackpackLose, self.backpack)
        self.backpack = nil
    end

    if do_integrated_backpack then
        local num = overflow:GetNumSlots()

        local x = - (num * (W+SEP) / 2)
        --local offset = #self.inv >= num and 1 or 0 --math.ceil((#self.inv - num)/2)
        local offset = 1 + #self.inv - num

        for k = 1, num do
            local slot = InvSlot(k, HUD_ATLAS, "inv_slot.tex", self.owner, overflow)
            self.backpackinv[k] = self.bottomrow:AddChild(slot)

            slot.top_align_tip = W*1.5 + YSEP*2

            if offset > 0 then
                slot:SetPosition(self.inv[offset+k-1]:GetPosition().x,0,0)
            else
                slot:SetPosition(x,0,0)
                x = x + W + SEP
            end

            local item = overflow:GetItemInSlot(k)
            if item ~= nil then
                slot:SetTile(ItemTile(item))
            end
        end

        self.backpack = overflow.inst
        self.inst:ListenForEvent("itemget", BackpackGet, self.backpack)
        self.inst:ListenForEvent("itemlose", BackpackLose, self.backpack)
    end

    if hadbackpack and self.backpack == nil then
        self:SelectDefaultSlot()
        self.current_list = self.inv
    end

    if self.bg.Flow ~= nil then
        -- note: Flow is a 3-slice function
        self.bg:Flow(total_w + 60, 256, true)
    end

    if TheNet:GetServerGameMode() == "lavaarena" then
        self.bg:SetPosition(15, 0)
        self.bg:SetScale(1)
        self.toprow:SetPosition(0, 3)
        self.root:SetPosition(self.in_pos)
    elseif do_integrated_backpack then
        self.bg:SetPosition(0, -24)
        self.bgcover:SetPosition(0, -135)
        self.toprow:SetPosition(0, .5 * (W + YSEP))
        self.bottomrow:SetPosition(0, -.5 * (W + YSEP))

        if self.rebuild_snapping then
            self.root:SetPosition(self.in_pos)
            self:UpdatePosition()
        else
            self.root:MoveTo(self.out_pos, self.in_pos, .5)
        end
    else
        self.bg:SetPosition(0, -64)
        self.bgcover:SetPosition(0, -100)
        self.toprow:SetPosition(0, 0)
        self.bottomrow:SetPosition(0, 0)

        if self.controller_build and not self.rebuild_snapping then
            self.root:MoveTo(self.in_pos, self.out_pos, .2)
        else
            self.root:SetPosition(self.out_pos)
            self:UpdatePosition()
        end
    end
end

function Inv:Rebuild()
    if self.cursor ~= nil then
        self.cursor:Kill()
        self.cursor = nil
    end

    if self.toprow ~= nil then
        self.toprow:Kill()
    end

    if self.bottomrow ~= nil then
        self.bottomrow:Kill()
    end

    self.toprow = self.root:AddChild(Widget("toprow"))
    self.bottomrow = self.root:AddChild(Widget("toprow"))

    self.inv = {}
    self.equip = {}
    self.backpackinv = {}

    self.controller_build = TheInput:ControllerAttached()

    local inventory = self.owner.replica.inventory
    local overflow = inventory:GetOverflowContainer()
    local do_integrated_backpack = overflow ~= nil and self.controller_build
    local do_self_inspect = not (self.controller_build or GetGameModeProperty("no_avatar_popup"))

	if TheNet:GetServerGameMode() == "quagmire" then
		RebuildLayout_Quagmire(self, inventory, overflow, do_integrated_backpack, do_self_inspect)
	else
		RebuildLayout(self, inventory, overflow, do_integrated_backpack, do_self_inspect)
	end

    self.actionstring:MoveToFront()

    self:SelectDefaultSlot()
    self.current_list = self.inv
    self:UpdateCursor()

    if self.cursor ~= nil then
        self.cursor:MoveToFront()
    end

    self.rebuild_pending = nil
    self.rebuild_snapping = nil
end

function Inv:OnUpdate(dt)
    self:UpdatePosition()

    self.hint_update_check = self.hint_update_check - dt
    if 0 > self.hint_update_check then
        if #self.inv <= 0 or not TheInput:ControllerAttached() then
            self.openhint:Hide()
        else
            self.openhint:Show()
            self.openhint:SetString(TheInput:GetLocalizedControl(TheInput:GetControllerID(), CONTROL_OPEN_INVENTORY))
        end
        self.hint_update_check = HINT_UPDATE_INTERVAL
    end

    if not ThePlayer.HUD.shown or ThePlayer.HUD ~= TheFrontEnd:GetActiveScreen() then
        return
    end

    if self.rebuild_pending then
        self:Rebuild()
        self:Refresh()
    end

    --V2C: Don't set pause in multiplayer, all it does is change the
    --     audio settings, which we don't want to do now
    --if self.open and TheInput:ControllerAttached() then
    --    SetPause(true, "inv")
    --end

    if not self.open and self.actionstring and self.actionstringtime and self.actionstringtime > 0 then
        self.actionstringtime = self.actionstringtime - dt
        if self.actionstringtime <= 0 then
            self.actionstring:Hide()
        end
    end

    if self.repeat_time > 0 then
        self.repeat_time = self.repeat_time - dt
    end

    if self.active_slot ~= nil and not self.active_slot.inst:IsValid() then
        self:SelectDefaultSlot()

        self.current_list = self.inv

        if self.cursor ~= nil then
            self.cursor:Kill()
            self.cursor = nil
        end
    end

    self:UpdateCursor()

    if self.shown then
        --this is intentionally unaware of focus
        if self.repeat_time <= 0 then
            if TheInput:IsControlPressed(CONTROL_INVENTORY_LEFT) or (self.open and TheInput:IsControlPressed(CONTROL_MOVE_LEFT)) then
                self:CursorLeft()
            elseif TheInput:IsControlPressed(CONTROL_INVENTORY_RIGHT) or (self.open and TheInput:IsControlPressed(CONTROL_MOVE_RIGHT)) then
                self:CursorRight()
            elseif TheInput:IsControlPressed(CONTROL_INVENTORY_UP) or (self.open and TheInput:IsControlPressed(CONTROL_MOVE_UP)) then
                self:CursorUp()
            elseif TheInput:IsControlPressed(CONTROL_INVENTORY_DOWN) or (self.open and TheInput:IsControlPressed(CONTROL_MOVE_DOWN)) then
                self:CursorDown()
            else
                self.repeat_time = 0
                self.reps = 0
                return
            end

            self.reps = self.reps and (self.reps + 1) or 1

            if self.reps <= 1 then
                self.repeat_time = 5/30
            elseif self.reps < 4 then
                self.repeat_time = 2/30
            else
                self.repeat_time = 1/30
            end
        end
    end
end

function Inv:OffsetCursor(offset, val, minval, maxval, slot_is_valid_fn)
    if val == nil then
        val = minval
    else
        local idx = val
        local start_idx = idx

        repeat
            idx = idx + offset

            if idx < minval then idx = maxval end
            if idx > maxval then idx = minval end

            if slot_is_valid_fn(idx) then
                val = idx
                break
            end

        until start_idx == idx
    end

    return val
end

function Inv:GetInventoryLists(same_container_only)
    if same_container_only then
        local lists = {self.current_list}

        if self.current_list == self.inv then
            table.insert(lists, self.equip)
        elseif self.current_list == self.equip then
            table.insert(lists, self.inv)
        end

        return lists
    else
        local lists = {self.inv, self.equip, self.backpackinv}

        local bp = self.owner.HUD:GetFirstOpenContainerWidget()
        if bp then
            table.insert(lists, bp.inv)
        end

        return lists
    end
end

function Inv:CursorNav(dir, same_container_only)
    ThePlayer.components.playercontroller:CancelDeployPlacement()

    if self:GetCursorItem() ~= nil then
        self.actionstringtime = CURSOR_STRING_DELAY
        self.actionstring:Show()
    end

    if self.active_slot and not self.active_slot.inst:IsValid() then
        self.current_list = self.inv
        return self:SelectDefaultSlot()
    end

    local lists = self:GetInventoryLists(same_container_only)
    local slot, list = self:GetClosestWidget(lists, self.active_slot:GetWorldPosition(), dir)
    if slot and list then
        self.current_list = list
        return self:SelectSlot(slot)
    end
end

function Inv:CursorLeft()
    if self:CursorNav(Vector3(-1,0,0), true) then
        TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
    end
end

function Inv:CursorRight()
    if self:CursorNav(Vector3(1,0,0), true) then
        TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
    end
end

function Inv:CursorUp()
    if self:CursorNav(Vector3(0,1,0)) then
        TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
    end
end

function Inv:CursorDown()
    if self:CursorNav(Vector3(0,-1,0)) then
        TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
    end
end

function Inv:GetClosestWidget(lists, pos, dir)
    local closest = nil
    local closest_score = nil
    local closest_list = nil

    for kk, vv in pairs(lists) do
        for k,v in pairs(vv) do
            if v ~= self.active_slot then
                local world_pos = v:GetWorldPosition()
                local dst = pos:DistSq(world_pos)
                local local_dir = (world_pos - pos):GetNormalized()
                local dot = local_dir:Dot(dir)

                if dot > 0 then
                    local score = dot/dst

                    if not closest or score > closest_score then
                        closest = v
                        closest_score = score
                        closest_list = vv
                    end
                end
            end
        end
    end

    return closest, closest_list
end

function Inv:GetCursorItem()
    return self.active_slot ~= nil and self.active_slot.tile ~= nil and self.active_slot.tile.item or nil
end

function Inv:GetCursorSlot()
    if self.active_slot ~= nil then
        return self.active_slot.num, self.active_slot.container
    end
end

function Inv:OnControl(control, down)
    if Inv._base.OnControl(self, control, down) then
        return true
    elseif not self.open then
        return
    end

    local was_force_single_drop = self.force_single_drop
    if was_force_single_drop and not TheInput:IsControlPressed(CONTROL_PUTSTACK) then
        self.force_single_drop = false
    end

    if down then
        return
    end

    local active_item = self.owner.replica.inventory:GetActiveItem()
    local inv_item = self:GetCursorItem()
    if inv_item ~= nil and inv_item.replica.inventoryitem == nil then
        inv_item = nil
    end

    if control == CONTROL_ACCEPT then
        if inv_item ~= nil and active_item == nil and
            (   (GetGameModeProperty("non_item_equips") and inv_item.replica.equippable ~= nil) or
                not inv_item.replica.inventoryitem:CanGoInContainer()
            ) then
            self.owner.replica.inventory:DropItemFromInvTile(inv_item)
            self:CloseControllerInventory()
            return true
        elseif self.active_slot ~= nil then
            self.active_slot:Click()
            return true
        end
    elseif control == CONTROL_PUTSTACK then
        if self.active_slot ~= nil then
            if not was_force_single_drop then
                self.active_slot:Click(true)
            end
            return true
        end
    elseif control == CONTROL_INVENTORY_DROP then
        if inv_item ~= nil and active_item == nil then
            if not was_force_single_drop and TheInput:IsControlPressed(CONTROL_PUTSTACK) then
                self.force_single_drop = true
            end
            self.owner.replica.inventory:DropItemFromInvTile(inv_item, self.force_single_drop)
            return true
        end
    elseif control == CONTROL_USE_ITEM_ON_ITEM then
        if inv_item ~= nil and active_item ~= nil then
            self.owner.replica.inventory:ControllerUseItemOnItemFromInvTile(inv_item, active_item)
            return true
        end
    end
end

function Inv:OpenControllerInventory()
    if not self.open then
        self.owner.HUD.controls:SetDark(true)
        --V2C: Don't set pause in multiplayer, all it does is change the
        --     audio settings, which we don't want to do now
        --SetPause(true, "inv")
        self.open = true
        self.force_single_drop = false --reset the flag

        self:UpdateCursor()
        self:ScaleTo(self.base_scale,self.selected_scale,.2)

        local bp = self.owner.HUD:GetFirstOpenContainerWidget()
        if bp ~= nil then
            bp:ScaleTo(self.base_scale,self.selected_scale,.2)
        end

        TheFrontEnd:LockFocus(true)
        self:SetFocus()
    end
end

function Inv:OnEnable()
    self:UpdateCursor()
end

function Inv:OnDisable()
    self.actionstring:Hide()
end

function Inv:CloseControllerInventory()
    if self.open then
        self.open = false
        --V2C: Don't set pause in multiplayer, all it does is change the
        --     audio settings, which we don't want to do now
        --SetPause(false)
        self.owner.HUD.controls:SetDark(false)

        self.owner.replica.inventory:ReturnActiveItem()

        self:UpdateCursor()

        if self.active_slot ~= nil then
            self.active_slot:DeHighlight()
        end

        self:ScaleTo(self.selected_scale, self.base_scale,.1)

        local bp = self.owner.HUD:GetFirstOpenContainerWidget()
        if bp ~= nil then
            bp:ScaleTo(self.selected_scale,self.base_scale,.1)
        end

        TheFrontEnd:LockFocus(false)
    end
end

function Inv:GetDescriptionString(item)
    local str = nil
    local in_equip_slot = item and item.components.equippable and item.components.equippable:IsEquipped()
    if item and item.replica.inventoryitem then
        local adjective = item:GetAdjective()
        if adjective then
            str = adjective .. " " .. item:GetDisplayName()
        else
            str = item:GetDisplayName()
        end
    end
    
    return str or ""
end

function Inv:SetTooltipColour(r,g,b,a)
   self.actionstringtitle:SetColour(r,g,b,a)
end

function Inv:UpdateCursorText()
    local inv_item = self:GetCursorItem()
    local active_item = self.cursortile ~= nil and self.cursortile.item or nil
    if inv_item ~= nil and inv_item.replica.inventoryitem == nil then
        inv_item = nil
    end
    if active_item ~= nil and active_item.replica.inventoryitem == nil then
        active_item = nil
    end
    if active_item ~= nil or inv_item ~= nil then
        local controller_id = TheInput:GetControllerID()

        if inv_item ~= nil then
            local itemname = self:GetDescriptionString(inv_item)
            self.actionstringtitle:SetString(itemname)
            if inv_item:GetIsWet() then
                self:SetTooltipColour(unpack(WET_TEXT_COLOUR))
            else
                self:SetTooltipColour(unpack(NORMAL_TEXT_COLOUR))
            end
        elseif active_item ~= nil then
            local itemname = self:GetDescriptionString(active_item)
            self.actionstringtitle:SetString(itemname)
            if active_item:GetIsWet() then
                self:SetTooltipColour(unpack(WET_TEXT_COLOUR))
            else
                self:SetTooltipColour(unpack(NORMAL_TEXT_COLOUR))
            end
        end


        local is_equip_slot = self.active_slot and self.active_slot.equipslot
        local str = {}

        if not self.open then
            if inv_item ~= nil then
                table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_INVENTORY_EXAMINE) .. " " .. STRINGS.UI.HUD.INSPECT)

                if not is_equip_slot then
                    if not inv_item.replica.inventoryitem:IsGrandOwner(self.owner) then
                        table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_INVENTORY_USEONSCENE) .. " " .. STRINGS.UI.HUD.TAKE)
                    else
                        local scene_action = self.owner.components.playercontroller:GetItemUseAction(inv_item)
                        if scene_action ~= nil then
                            table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_INVENTORY_USEONSCENE) .. " " .. scene_action:GetActionString())
                        end
                    end
                    local self_action = self.owner.components.playercontroller:GetItemSelfAction(inv_item)
                    if self_action ~= nil then
                        table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_INVENTORY_USEONSELF) .. " " .. self_action:GetActionString())
                    end
                else
                    local self_action = self.owner.components.playercontroller:GetItemSelfAction(inv_item)
                    if self_action ~= nil and self_action.action ~= ACTIONS.UNEQUIP then
                        table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_INVENTORY_USEONSCENE) .. " " .. self_action:GetActionString())
                    end
                    if #self.inv > 0 and not (inv_item:HasTag("heavy") or GetGameModeProperty("non_item_equips")) then
                        table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_INVENTORY_USEONSELF) .. " " .. STRINGS.UI.HUD.UNEQUIP)
                    end
                end

                table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_INVENTORY_DROP) .. " " .. STRINGS.UI.HUD.DROP)
            end
        else 
            if is_equip_slot then
                --handle the quip slot stuff as a special case because not every item can go there
                if active_item ~= nil and active_item.replica.equippable ~= nil and active_item.replica.equippable:EquipSlot() == self.active_slot.equipslot then
                    if inv_item and active_item then
                        table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_ACCEPT) .. " " .. STRINGS.UI.HUD.SWAP)
                    elseif not inv_item and active_item then
                        table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_ACCEPT) .. " " .. STRINGS.UI.HUD.EQUIP)
                    end
                elseif active_item == nil and inv_item ~= nil then
                    if not (GetGameModeProperty("non_item_equips") and inv_item.replica.equippable ~= nil) and
                        inv_item.replica.inventoryitem:CanGoInContainer() then
                        table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_ACCEPT) .. " " .. STRINGS.UI.HUD.UNEQUIP)
                    else
                        table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_ACCEPT) .. " " .. STRINGS.UI.HUD.DROP)
                    end
                end
            else
                local can_take_active_item = active_item ~= nil and self.active_slot.container.CanTakeItemInSlot == nil or self.active_slot.container:CanTakeItemInSlot(active_item, self.active_slot.num)

                if active_item ~= nil and active_item.replica.stackable ~= nil and
                    ((inv_item ~= nil and inv_item.prefab == active_item.prefab) or (inv_item == nil and can_take_active_item)) then
                    table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_PUTSTACK) .. " " .. STRINGS.UI.HUD.PUTONE)
                end

                if active_item == nil and inv_item ~= nil and inv_item.replica.stackable ~= nil and inv_item.replica.stackable:IsStack() then
                    table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_PUTSTACK) .. " " .. STRINGS.UI.HUD.GETHALF)
                end

                if inv_item ~= nil and active_item == nil then
                    table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_ACCEPT) .. " " .. STRINGS.UI.HUD.SELECT)
                    table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_INVENTORY_DROP) .. " " .. STRINGS.UI.HUD.DROP)
                elseif inv_item ~= nil and active_item ~= nil then
                    if inv_item.prefab == active_item.prefab and active_item.replica.stackable ~= nil then
                        table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_ACCEPT) .. " " .. STRINGS.UI.HUD.PUT)
                    elseif can_take_active_item then
                        table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_ACCEPT) .. " " .. STRINGS.UI.HUD.SWAP)
                    else
                        table.insert(str, " ")
                    end
                elseif inv_item == nil and active_item ~= nil and can_take_active_item then
                    table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_ACCEPT) .. " " .. STRINGS.UI.HUD.PUT)
                else
                    table.insert(str, " ")
                end
            end

            if active_item ~= nil and inv_item ~= nil then
                local use_action = self.owner.components.playercontroller:GetItemUseAction(active_item, inv_item)
                if use_action ~= nil then
                    table.insert(str, TheInput:GetLocalizedControl(controller_id, CONTROL_USE_ITEM_ON_ITEM) .. " " .. use_action:GetActionString())
                end
            end
        end

        local was_shown = self.actionstring.shown
        local old_string = self.actionstringbody:GetString()
        local new_string = table.concat(str, '\n')
        if old_string ~= new_string then
            self.actionstringbody:SetString(new_string)
            self.actionstringtime = CURSOR_STRING_DELAY
            self.actionstring:Show()
        end

        local w0, h0 = self.actionstringtitle:GetRegionSize()
        local w1, h1 = self.actionstringbody:GetRegionSize()

        local wmax = math.max(w0, w1)

        local dest_pos = self.active_slot:GetWorldPosition()

        local xscale, yscale, zscale = self.root:GetScale():Get()

        if self.active_slot.side_align_tip then
            -- in-game containers, chests, fridge
            self.actionstringtitle:SetPosition(wmax/2, h0/2)
            self.actionstringbody:SetPosition(wmax/2, -h1/2)

            dest_pos.x = dest_pos.x + self.active_slot.side_align_tip * xscale
        elseif self.active_slot.top_align_tip then
            -- main inventory
            self.actionstringtitle:SetPosition(0, h0/2 + h1)
            self.actionstringbody:SetPosition(0, h1/2)

            dest_pos.y = dest_pos.y + (self.active_slot.top_align_tip + TIP_YFUDGE) * yscale
        else
            -- old default as fallback ?
            self.actionstringtitle:SetPosition(0, h0/2 + h1)
            self.actionstringbody:SetPosition(0, h1/2)

            dest_pos.y = dest_pos.y + (W/2 + TIP_YFUDGE) * yscale
        end

        -- print("self.active_slot:GetWorldPosition()", self.active_slot:GetWorldPosition())
        -- print("h0", h0)
        -- print("w0", w0)
        -- print("h1", h1)
        -- print("w1", h1)
        -- print("dest_pos", dest_pos)

        if dest_pos:DistSq(self.actionstring:GetPosition()) > 1 then
            self.actionstringtime = CURSOR_STRING_DELAY
            if was_shown then
                self.actionstring:MoveTo(self.actionstring:GetPosition(), dest_pos, .1)
            else
                self.actionstring:SetPosition(dest_pos)
                self.actionstring:Show()
            end
        end
    else
        self.actionstringbody:SetString("")
        self.actionstring:Hide()
    end
end

function Inv:SelectSlot(slot)
    if slot and slot ~= self.active_slot then
        if self.active_slot and self.active_slot ~= slot then
            self.active_slot:DeHighlight()
        end
        self.active_slot = slot
        return true
    end
end

function Inv:SelectDefaultSlot()
    self:SelectSlot(self.inv[1] or self.equip[self.equipslotinfo[1].slot])
end

function Inv:UpdateCursor()
    if not TheInput:ControllerAttached() then
        self.actionstring:Hide()
        if self.cursor ~= nil then
            self.cursor:Hide()
        end

        if self.cursortile ~= nil then
            self.cursortile:Kill()
            self.cursortile = nil
        end
        return
    end

    if self.hovertile ~= nil then
        self.hovertile:Kill()
        self.hovertile = nil
    end

    if self.active_slot == nil then
        self:SelectDefaultSlot()
    end

    if self.active_slot ~= nil and self.cursortile ~= nil then
        self.cursortile:SetPosition(self.active_slot:GetWorldPosition())
    end

    if self.active_slot ~= nil then
        if self.cursor ~= nil then
            self.cursor:Kill()
        end
        self.cursor = self.root:AddChild(Image(HUD_ATLAS, "slot_select.tex"))

        if self.active_slot.tile ~= nil and self.active_slot.tile:HasSpoilage() then
            self.cursor:Show()
            self.active_slot.tile:AddChild(self.cursor)
            self.active_slot:Highlight()

            self.cursor:MoveToBack()
            self.active_slot.tile.spoilage:MoveToBack()
            self.active_slot.tile.bg:MoveToBack()
        else
            self.cursor:Show()
            self.active_slot:AddChild(self.cursor)
            self.active_slot:Highlight()

            self.cursor:MoveToBack()
            self.active_slot.bgimage:MoveToBack()
        end
    else
        self.cursor:Hide()
    end

    --if self.open then
    local active_item = self.owner.replica.inventory:GetActiveItem()
    if active_item ~= nil then
        if self.cursortile == nil or active_item ~= self.cursortile.item then
            if self.cursortile ~= nil then
                self.cursortile:Kill()
            end
            self.cursortile = self.root:AddChild(ItemTile(active_item))
            self.cursortile.isactivetile = true
            self.cursortile.image:SetScale(1.3)
            self.cursortile:SetScaleMode(SCALEMODE_PROPORTIONAL)
            self.cursortile:StartDrag()
            self.cursortile:SetPosition(self.active_slot:GetWorldPosition())
        end
    elseif self.cursortile ~= nil then
        self.cursortile:Kill()
        self.cursortile = nil
    end

    self:UpdateCursorText()
end

function Inv:Refresh()
    local inventory = self.owner.replica.inventory
    local items = inventory:GetItems()
    local equips = inventory:GetEquips()
    local activeitem = inventory:GetActiveItem()

    for i, v in ipairs(self.inv) do
        local item = items[i]
        if item == nil then
            if v.tile ~= nil then
                v:SetTile(nil)
            end
        elseif v.tile == nil or v.tile.item ~= item then
            v:SetTile(ItemTile(item))
        else
            v.tile:Refresh()
        end
    end

    for k, v in pairs(self.equip) do
        local item = equips[k]
        if item == nil then
            if v.tile ~= nil then
                v:SetTile(nil)
            end
        elseif v.tile == nil or v.tile.item ~= item then
            v:SetTile(ItemTile(item))
        else
            v.tile:Refresh()
        end
    end

    if #self.backpackinv > 0 then
        local overflow = inventory:GetOverflowContainer()
        if overflow ~= nil then
            for i, v in ipairs(self.backpackinv) do
                local item = overflow:GetItemInSlot(i)
                if item == nil then
                    if v.tile ~= nil then
                        v:SetTile(nil)
                    end
                elseif v.tile == nil or v.tile.item ~= item then
                    v:SetTile(ItemTile(item))
                else
                    v.tile:Refresh()
                end
            end
        end
    end

    self:OnNewActiveItem(activeitem)
end

function Inv:Cancel()
    local inventory = self.owner.replica.inventory
    local active_item = inventory:GetActiveItem()
    if active_item ~= nil then
        inventory:ReturnActiveItem()
    end
end

function Inv:OnItemLose(slot)
    if slot then
        slot:SetTile(nil)
    end
    
    --self:UpdateCursor()
end

function Inv:OnBuild()
    if self.hovertile then
        self.hovertile:ScaleTo(3, 1, .5)
    end
end

function Inv:OnNewActiveItem(item)
    if TheInput:ControllerAttached() then
        if item == nil or self.owner.HUD.controls == nil then
            if self.cursortile ~= nil then
                self.cursortile:Kill()
                self.cursortile = nil
                self:UpdateCursorText()
            end
        elseif self.cursortile ~= nil and self.cursortile.item == item then
            self.cursortile:Refresh()
            self:UpdateCursorText()
        elseif self.active_slot ~= nil then
            if self.cursortile ~= nil then
                self.cursortile:Kill()
            end
            self.cursortile = self.root:AddChild(ItemTile(item))
            self.cursortile.isactivetile = true
            self.cursortile.image:SetScale(1.3)
            self.cursortile:SetScaleMode(SCALEMODE_PROPORTIONAL)
            self.cursortile:StartDrag()
            self.cursortile:SetPosition(self.active_slot:GetWorldPosition())
            self:UpdateCursorText()
        end
    elseif item == nil or self.owner.HUD.controls == nil then
        if self.hovertile ~= nil then
            self.hovertile:Kill()
            self.hovertile = nil
        end
    elseif self.hovertile ~= nil and self.hovertile.item == item then
        self.hovertile:Refresh()
    else
        if self.hovertile ~= nil then
            self.hovertile:Kill()
        end
        self.hovertile = self.owner.HUD.controls.mousefollow:AddChild(ItemTile(item))
        self.hovertile.isactivetile = true
        self.hovertile:StartDrag()
    end
end

function Inv:OnItemGet(item, slot, source_pos, ignore_stacksize_anim)
    if slot ~= nil then
        local tile = ItemTile(item)
        slot:SetTile(tile)
        tile:Hide()
        tile.ignore_stacksize_anim = ignore_stacksize_anim

        if source_pos ~= nil then
            local dest_pos = slot:GetWorldPosition()
            local im = Image(item.replica.inventoryitem:GetAtlas(), item.replica.inventoryitem:GetImage())
            if GetGameModeProperty("icons_use_cc") then
                im:SetEffect("shaders/ui_cc.ksh")
            end
            if item.inv_image_bg ~= nil then
                local bg = Image(item.inv_image_bg.atlas, item.inv_image_bg.image)
                bg:AddChild(im)
                im = bg
                if GetGameModeProperty("icons_use_cc") then
                    im:SetEffect("shaders/ui_cc.ksh")
                end
            end
            im:MoveTo(Vector3(TheSim:GetScreenPos(source_pos:Get())), dest_pos, .3, function() tile:Show() tile:ScaleTo(2, 1, .25) im:Kill() end)
        else
            tile:Show() 
            --tile:ScaleTo(2, 1, .25)
        end
    end
end

function Inv:OnItemEquip(item, slot)
    if slot ~= nil and self.equip[slot] ~= nil then
        self.equip[slot]:SetTile(ItemTile(item))
    end
end

function Inv:OnItemUnequip(item, slot)
    if slot ~= nil and self.equip[slot] ~= nil then
        self.equip[slot]:SetTile(nil)
    end
end

--Extended to autoposition world reset timer

function Inv:UpdatePosition()
    self.autoanchor:SetPosition(0, self:IsVisible() and (self.root:GetPosition().y - 10) or 0)
end

Inv.OnShow = Inv.UpdatePosition
Inv.OnHide = Inv.UpdatePosition

return Inv
