# Az-QBInventory-Bridge for Az-Framework

Az-QBInventory-Bridge is an Az-Framework compatibility bridge. It provides the expected resource name and API surface for resources written around QBCore, qb-inventory, qb-target, ESX, or ND_Core.

[Framework Docs](https://madebyazure.com/framework/) | [Discord Support](https://discord.gg/tBg2U6CTHE)

## Quick Install

``cfg
ensure oxmysql
ensure ox_lib
ensure Az-Framework
 qb-inventory
``

<details>
<summary>What this resource does</summary>

- Uses Az-Framework as the core player, character, money, job, and metadata source.
- Keeps startup order predictable for large FiveM servers.
- Keeps configuration local to this resource when a config file is present.
- Uses the Az support/docs path for setup and troubleshooting.

</details>

<details>
<summary>Configuration guide</summary>

1. Put the resource folder in your server resources folder.
2. Start dependencies before this resource.
3. Review `config.lua` or `shared/config.lua` when present.
4. Restart the resource after config changes.

</details>

<details>
<summary>Bridge and export notes</summary>

Use Az-Framework exports for framework-facing logic:

``lua
local Az = exports['Az-Framework']:GetObject()
local player = exports['Az-Framework']:GetPlayer(source)
local snapshot = exports['Az-Framework']:GetBridgePlayerSnapshot(source)
``

Bridge resources from KSRP-Core are published as Az-Framework compatibility bridges and should be started before legacy resources that expect those framework names.

</details>

<details>
<summary>Support</summary>

- Docs: https://madebyazure.com/framework/
- Discord: https://discord.gg/tBg2U6CTHE

</details>
