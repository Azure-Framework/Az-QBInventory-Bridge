local C = AzInventoryBridge or {}
local RESOURCE = GetCurrentResourceName()

local function dprint(...)
    if not C.Debug then return end
    print(('^3[%s][CLIENT]^7 '):format(RESOURCE), ...)
end

local function started(res)
    return GetResourceState(res) == 'started'
end

local function callOx(name, ...)
    if not started('ox_inventory') then return nil end
    local okExports, resourceExports = pcall(function() return exports.ox_inventory end)
    if not okExports or not resourceExports then return nil end
    local okFn, fn = pcall(function() return resourceExports[name] end)
    if not okFn or type(fn) ~= 'function' then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    ok, a, b, c = pcall(fn, resourceExports, ...)
    if ok then return a, b, c end
    return nil
end

local function oxItemToQB(item)
    if type(item) ~= 'table' then return item end
    local out = {}
    for k, v in pairs(item) do out[k] = v end
    out.amount = tonumber(out.amount or out.count or 0) or 0
    out.count = out.amount
    out.info = out.info or out.metadata or {}
    out.metadata = out.metadata or out.info or {}
    out.type = out.type or 'item'
    return out
end

local function OpenInventory(invType, data)
    if invType == nil or invType == '' then
        callOx('openInventory', 'player')
        return true
    end

    if invType == 'stash' or invType == 'shop' or invType == 'player' or invType == 'trunk' or invType == 'glovebox' then
        callOx('openInventory', invType, data)
    else
        callOx('openInventory', 'stash', invType)
    end
    return true
end

local function CloseInventory()
    TriggerServerEvent('qb-inventory:server:closeInventory')
    TriggerEvent('ox_inventory:closeInventory')
    return true
end

local function GetItemCount(itemName, amount)
    return tonumber(callOx('GetItemCount', itemName)) or tonumber(callOx('Search', 'count', itemName)) or 0
end

local function HasItem(itemName, amount)
    if type(itemName) == 'table' then
        amount = math.max(1, tonumber(amount) or 1)
        for _, name in pairs(itemName) do
            if GetItemCount(name) < amount then return false end
        end
        return true
    end
    return GetItemCount(itemName) >= math.max(1, tonumber(amount) or 1)
end

local function GetItemByName(itemName)
    local slot = callOx('GetSlotWithItem', itemName)
    if type(slot) == 'table' then return oxItemToQB(slot) end
    local slots = callOx('Search', 'slots', itemName)
    if type(slots) == 'table' then
        for _, item in pairs(slots) do return oxItemToQB(item) end
    end
    return nil
end

local function GetItemsByName(itemName)
    local slots = callOx('GetSlotsWithItem', itemName) or callOx('Search', 'slots', itemName) or {}
    local out = {}
    for _, item in pairs(slots) do out[#out + 1] = oxItemToQB(item) end
    return out
end

local function GetItemBySlot(slot)
    return oxItemToQB(callOx('GetSlot', tonumber(slot)))
end

RegisterNetEvent('qb-inventory:client:openInventory', function(invType, data)
    OpenInventory(invType, data)
end)

RegisterNetEvent('inventory:client:ItemBox', function(itemData, type, amount)
    dprint('ItemBox', itemData and itemData.name, type, amount)
end)

RegisterNetEvent('qb-inventory:client:closeInventory', function()
    CloseInventory()
end)

exports('OpenInventory', OpenInventory)
exports('CloseInventory', CloseInventory)
exports('HasItem', HasItem)
exports('GetItemCount', GetItemCount)
exports('GetItemByName', GetItemByName)
exports('GetItemsByName', GetItemsByName)
exports('GetItemBySlot', GetItemBySlot)
