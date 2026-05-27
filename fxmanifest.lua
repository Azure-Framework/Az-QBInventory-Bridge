fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'MadeByAzure'
description 'qb-inventory compatibility shim backed by ox_inventory / Az-Framework'
version '1.0.0'

shared_scripts {
    'config.lua'
}

server_scripts {
    'server.lua'
}

client_scripts {
    'client.lua'
}

server_exports {
    'LoadInventory',
    'SaveInventory',
    'ClearInventory',
    'ClearStash',
    'CloseInventory',
    'OpenInventory',
    'OpenInventoryById',
    'CreateInventory',
    'RemoveInventory',
    'CreateShop',
    'OpenShop',
    'CanAddItem',
    'AddItem',
    'RemoveItem',
    'SetInventory',
    'SetItemData',
    'UseItem',
    'HasItem',
    'GetFreeWeight',
    'GetTotalWeight',
    'GetSlots',
    'GetSlotsByItem',
    'GetFirstSlotByItem',
    'GetItemBySlot',
    'GetItemByName',
    'GetItemsByName',
    'GetItemCount',
    'GetInventory'
}

client_exports {
    'OpenInventory',
    'CloseInventory',
    'HasItem',
    'GetItemCount',
    'GetItemByName',
    'GetItemsByName',
    'GetItemBySlot'
}
