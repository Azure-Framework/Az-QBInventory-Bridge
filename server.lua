local C = AzInventoryBridge or {}
local RESOURCE = GetCurrentResourceName()
local createdShops = {}

local function dprint(...)
    if not C.Debug then return end
    print(('^3[%s][DEBUG]^7 '):format(RESOURCE), ...)
end

local function warn(...)
    print(('^1[%s][WARN]^7 '):format(RESOURCE), ...)
end

local function started(res)
    return GetResourceState(res) == 'started'
end

local function backend()
    if C.Backend and C.Backend ~= 'auto' then
        return started(C.Backend) and C.Backend or nil
    end

    if started('ox_inventory') then return 'ox_inventory' end
    if started('Az-Framework') then return 'Az-Framework' end
    return nil
end

local function callExport(res, name, ...)
    if not res or not started(res) then return nil, ('resource_not_started:%s'):format(tostring(res)) end

    local okExports, resourceExports = pcall(function() return exports[res] end)
    if not okExports or not resourceExports then return nil, 'exports_unavailable' end

    local okFn, fn = pcall(function() return resourceExports[name] end)
    if not okFn or type(fn) ~= 'function' then return nil, ('missing_export:%s'):format(name) end

    local okCall, a, b, c = pcall(fn, ...)
    if okCall then return a, b, c end

    okCall, a, b, c = pcall(fn, resourceExports, ...)
    if okCall then return a, b, c end

    return nil, tostring(a or 'export_call_failed')
end

local function callBackend(name, ...)
    local res = backend()
    if not res then return nil, 'no_backend_inventory_started' end
    dprint('calling backend', res, name)
    return callExport(res, name, ...)
end

local function isArray(t)
    if type(t) ~= 'table' then return false end
    local i = 0
    for k in pairs(t) do
        if type(k) ~= 'number' then return false end
        if k > i then i = k end
    end
    return i > 0
end

local function copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end
    return out
end

local function oxItemToQB(item)
    if type(item) ~= 'table' then return item end
    local out = copy(item)
    out.name = tostring(out.name or out.item or '')
    out.amount = tonumber(out.amount or out.count or out.quantity or 0) or 0
    out.count = out.amount
    out.info = copy(out.info or out.metadata or {})
    out.metadata = copy(out.metadata or out.info or {})
    out.slot = tonumber(out.slot) or out.slot
    out.type = out.type or 'item'
    out.useable = out.useable or out.usable or false
    return out
end

local function qbItemsToOx(items)
    local out = {}
    for _, item in pairs(items or {}) do
        if type(item) == 'table' and item.name then
            out[#out + 1] = {
                name = item.name,
                count = tonumber(item.count or item.amount or 1) or 1,
                metadata = copy(item.metadata or item.info or {}),
                slot = tonumber(item.slot) or nil,
            }
        end
    end
    return out
end

local function oxSlots(identifier, item, metadata)
    local slots, err = callBackend('Search', identifier, 'slots', item, metadata)
    if type(slots) == 'table' then return slots end
    dprint('oxSlots failed', err or 'nil')
    return {}
end

local function oxCount(identifier, item, metadata)
    local count = callBackend('GetItemCount', identifier, item, metadata)
    if count ~= nil then return tonumber(count) or 0 end
    count = callBackend('Search', identifier, 'count', item, metadata)
    return tonumber(count) or 0
end

local function qbHasItem(identifier, items, amount)
    identifier = tonumber(identifier) or identifier

    if type(items) == 'table' and not isArray(items) then
        for itemName, needed in pairs(items) do
            if oxCount(identifier, itemName) < (tonumber(needed) or 1) then return false end
        end
        return true
    end

    if type(items) == 'table' then
        amount = math.max(1, tonumber(amount) or 1)
        for _, itemName in ipairs(items) do
            if oxCount(identifier, itemName) < amount then return false end
        end
        return true
    end

    return oxCount(identifier, items) >= math.max(1, tonumber(amount) or 1)
end

local function normalizeInventoryId(identifier)
    return tonumber(identifier) or identifier
end

local function unsupported(name)
    if C.NotifyOnUnsupported then warn(name .. ' is a compatibility no-op in this shim') end
    return false
end

local function LoadInventory(source, citizenid)
    local identifier = normalizeInventoryId(source or citizenid)
    local items = callBackend('GetInventoryItems', identifier)
    if type(items) ~= 'table' then return {} end

    local out = {}
    for slot, item in pairs(items) do
        local converted = oxItemToQB(item)
        converted.slot = tonumber(converted.slot or slot) or converted.slot
        out[converted.slot or (#out + 1)] = converted
    end
    return out
end

local function SaveInventory(source, offline)
    dprint('SaveInventory requested; ox_inventory persists itself', source, offline)
    return true
end

local function ClearInventory(source, filterItems)
    local keep = filterItems
    local ok, err = callBackend('ClearInventory', normalizeInventoryId(source), keep)
    if ok == nil and err then dprint('ClearInventory backend response', err) end
    return ok ~= nil and ok ~= false
end

local function ClearStash(identifier)
    return ClearInventory(identifier)
end

local function CloseInventory(source, identifier)
    source = tonumber(source) or source
    if type(source) == 'number' then
        TriggerClientEvent('qb-inventory:client:closeInventory', source)
        TriggerClientEvent('ox_inventory:closeInventory', source)
        Player(source).state.inv_busy = false
    end
    return true
end

local function OpenInventory(source, identifier, data)
    source = tonumber(source) or source
    if type(source) ~= 'number' then return false end

    if identifier == nil or identifier == '' or identifier == source then
        TriggerClientEvent('qb-inventory:client:openInventory', source)
        return true
    end

    if type(identifier) == 'number' or tostring(identifier):find('otherplayer') then
        local target = tonumber(identifier) or tonumber(tostring(identifier):match('(%d+)'))
        if target then
            local ok = callBackend('forceOpenInventory', source, 'player', target)
            return ok ~= nil and ok ~= false
        end
    end

    local invType = 'stash'
    local invData = identifier

    if type(data) == 'table' then
        invData = data.name or data.id or data.identifier or identifier
        if data.type then invType = data.type end
        if invType == 'shop' then invData = data.name or identifier end
    end

    local ok = callBackend('forceOpenInventory', source, invType, invData)
    if ok == nil or ok == false then
        TriggerClientEvent('ox_inventory:openInventory', source, invType, invData)
    end
    return true
end

local function OpenInventoryById(source, targetId)
    return OpenInventory(source, tonumber(targetId) or targetId)
end

local function CreateInventory(identifier, data)
    if type(data) ~= 'table' then data = {} end
    local id = data.name or data.id or identifier
    local label = data.label or data.name or tostring(id)
    local slots = tonumber(data.slots or data.maxslots or C.DefaultSlots) or C.DefaultSlots
    local weight = tonumber(data.maxweight or data.maxWeight or data.weight or C.DefaultWeight) or C.DefaultWeight
    local owner = data.owner
    local groups = data.groups or data.jobs
    local coords = data.coords

    local ok, err = callBackend('RegisterStash', id, label, slots, weight, owner, groups, coords)
    if ok == nil and err then dprint('RegisterStash response', err) end
    return true
end

local function RemoveInventory(identifier)
    local ok = callBackend('RemoveInventory', identifier)
    return ok ~= nil and ok ~= false
end

local function CreateShop(shopData)
    if type(shopData) ~= 'table' then return false end
    local name = shopData.name or shopData.id
    if not name then return false end
    createdShops[name] = copy(shopData)
    dprint('registered shop mapping', name)
    return true
end

local function OpenShop(source, name)
    source = tonumber(source) or source
    if type(source) ~= 'number' then return false end
    local ok = callBackend('forceOpenInventory', source, 'shop', name)
    if ok == nil or ok == false then TriggerClientEvent('ox_inventory:openInventory', source, 'shop', name) end
    return true
end

local function CanAddItem(identifier, item, amount)
    local ok, reason = callBackend('CanCarryItem', normalizeInventoryId(identifier), item, tonumber(amount) or 1)
    if ok == nil then return false, reason or 'backend_unavailable' end
    return ok == true, reason
end

local function AddItem(identifier, item, amount, slot, info, reason)
    identifier = normalizeInventoryId(identifier)
    amount = tonumber(amount) or 1
    if slot == false then slot = nil end
    if info == false then info = nil end

    local ok, response = callBackend('AddItem', identifier, item, amount, info, slot)
    dprint('AddItem', identifier, item, amount, 'slot', slot, 'ok', ok, 'response', response)
    return ok == true
end

local function RemoveItem(identifier, item, amount, slot, reason)
    identifier = normalizeInventoryId(identifier)
    amount = tonumber(amount) or 1
    if slot == false then slot = nil end

    local ok, response = callBackend('RemoveItem', identifier, item, amount, nil, slot)
    dprint('RemoveItem', identifier, item, amount, 'slot', slot, 'ok', ok, 'response', response)
    return ok == true
end

local function SetInventory(source, items)
    source = normalizeInventoryId(source)
    ClearInventory(source)
    for _, item in pairs(qbItemsToOx(items)) do
        callBackend('AddItem', source, item.name, item.count, item.metadata, item.slot)
    end
    return true
end

local function SetItemData(source, itemName, key, val, slot)
    source = normalizeInventoryId(source)
    local target = nil
    if slot then
        target = callBackend('GetSlot', source, tonumber(slot))
    else
        local slots = oxSlots(source, itemName)
        target = slots[1]
    end
    if type(target) ~= 'table' or not target.slot then return false end
    local metadata = copy(target.metadata or {})
    metadata[key] = val
    local ok = callBackend('SetMetadata', source, target.slot, metadata)
    return ok ~= nil and ok ~= false
end

local usableItems = {}
local function UseItem(itemName, cb)
    usableItems[itemName] = cb
    dprint('registered usable item callback for', itemName)
    return true
end

local function HasItem(source, items, amount)
    return qbHasItem(source, items, amount)
end

local function GetFreeWeight(source)
    local max = callBackend('GetPlayerMaxWeight', tonumber(source) or source) or C.DefaultWeight
    local cur = callBackend('GetPlayerWeight', tonumber(source) or source) or 0
    return math.max(0, (tonumber(max) or 0) - (tonumber(cur) or 0))
end

local function GetTotalWeight(itemsOrSource)
    if type(itemsOrSource) == 'number' or type(itemsOrSource) == 'string' then
        return tonumber(callBackend('GetPlayerWeight', normalizeInventoryId(itemsOrSource))) or 0
    end

    local total = 0
    for _, item in pairs(itemsOrSource or {}) do
        if type(item) == 'table' then
            total = total + ((tonumber(item.weight) or 0) * (tonumber(item.amount or item.count) or 1))
        end
    end
    return total
end

local function GetSlots(source)
    local items = LoadInventory(source)
    local highest = 0
    for slot in pairs(items or {}) do
        if type(slot) == 'number' and slot > highest then highest = slot end
    end
    return highest > 0 and highest or C.DefaultSlots
end

local function GetSlotsByItem(items, itemName)
    local slots = {}
    for slot, item in pairs(items or {}) do
        if type(item) == 'table' and item.name == itemName then slots[#slots + 1] = tonumber(item.slot or slot) or slot end
    end
    return slots
end

local function GetFirstSlotByItem(items, itemName)
    local slots = GetSlotsByItem(items, itemName)
    return slots[1]
end

local function GetItemBySlot(source, slot)
    local item = callBackend('GetSlot', normalizeInventoryId(source), tonumber(slot))
    return oxItemToQB(item)
end

local function GetItemByName(source, item)
    local slots = oxSlots(normalizeInventoryId(source), item)
    if type(slots[1]) == 'table' then return oxItemToQB(slots[1]) end
    local generic = callBackend('GetItem', normalizeInventoryId(source), item, nil, false)
    if type(generic) == 'table' and (tonumber(generic.count or 0) or 0) > 0 then return oxItemToQB(generic) end
    return nil
end

local function GetItemsByName(source, item)
    local slots = oxSlots(normalizeInventoryId(source), item)
    local out = {}
    for _, slotData in pairs(slots or {}) do out[#out + 1] = oxItemToQB(slotData) end
    return out
end

local function GetItemCount(source, items)
    if type(items) == 'table' then
        local counts = {}
        for _, itemName in pairs(items) do counts[itemName] = oxCount(normalizeInventoryId(source), itemName) end
        return counts
    end
    return oxCount(normalizeInventoryId(source), items)
end

local function GetInventory(identifier)
    local inv = callBackend('GetInventory', identifier, false)
    if inv ~= nil then return inv end
    return LoadInventory(identifier)
end

RegisterNetEvent('qb-inventory:server:closeInventory', function(inventory)
    CloseInventory(source, inventory)
end)

RegisterNetEvent('qb-inventory:server:OpenInventory', function(identifier, data)
    OpenInventory(source, identifier, data)
end)

RegisterNetEvent('inventory:server:OpenInventory', function(invType, identifier, data)
    if invType == 'stash' then
        OpenInventory(source, identifier, data)
    elseif invType == 'player' then
        OpenInventory(source, tonumber(identifier) or identifier, data)
    elseif invType == 'shop' then
        OpenShop(source, identifier)
    else
        OpenInventory(source, identifier or invType, data)
    end
end)

RegisterNetEvent('inventory:server:UseItemSlot', function(slot)
    local item = GetItemBySlot(source, slot)
    if not item or not item.name then return end
    local cb = usableItems[item.name]
    if type(cb) == 'function' then cb(source, item) end
end)

if C.EnableDebugCommand then
    RegisterCommand('azinvtest', function(source, args)
        local src = source
        if src <= 0 then return print('Run this in-game.') end
        local action = tostring(args[1] or 'count')
        local item = tostring(args[2] or 'water')
        local amount = tonumber(args[3] or '1') or 1
        if action == 'add' then
            print('AddItem:', AddItem(src, item, amount, false, false, 'azinvtest'))
        elseif action == 'remove' then
            print('RemoveItem:', RemoveItem(src, item, amount, false, 'azinvtest'))
        elseif action == 'has' then
            print('HasItem:', HasItem(src, item, amount))
        else
            print('Count:', GetItemCount(src, item))
        end
    end, false)
end

exports('LoadInventory', LoadInventory)
exports('SaveInventory', SaveInventory)
exports('ClearInventory', ClearInventory)
exports('ClearStash', ClearStash)
exports('CloseInventory', CloseInventory)
exports('OpenInventory', OpenInventory)
exports('OpenInventoryById', OpenInventoryById)
exports('CreateInventory', CreateInventory)
exports('RemoveInventory', RemoveInventory)
exports('CreateShop', CreateShop)
exports('OpenShop', OpenShop)
exports('CanAddItem', CanAddItem)
exports('AddItem', AddItem)
exports('RemoveItem', RemoveItem)
exports('SetInventory', SetInventory)
exports('SetItemData', SetItemData)
exports('UseItem', UseItem)
exports('HasItem', HasItem)
exports('GetFreeWeight', GetFreeWeight)
exports('GetTotalWeight', GetTotalWeight)
exports('GetSlots', GetSlots)
exports('GetSlotsByItem', GetSlotsByItem)
exports('GetFirstSlotByItem', GetFirstSlotByItem)
exports('GetItemBySlot', GetItemBySlot)
exports('GetItemByName', GetItemByName)
exports('GetItemsByName', GetItemsByName)
exports('GetItemCount', GetItemCount)
exports('GetInventory', GetInventory)

CreateThread(function()
    Wait(500)
    dprint('started. backend=' .. tostring(backend()))
    if started('qb-inventory') and RESOURCE ~= 'qb-inventory' then warn('real qb-inventory appears to be running; do not run duplicate shims') end
end)
