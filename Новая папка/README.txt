--[[
=============================================================================
    CONFIGURATION & EXPANSION GUIDE
=============================================================================

Welcome to your Simulator framework! This guide explains how to easily add
new items, configure lucky blocks, set up zones with NPC guards, expand
player plots, and manage monetization.

-----------------------------------------------------------------------------
1. ADDING NEW ITEMS (PASSIVE INCOME OBJECTS)
-----------------------------------------------------------------------------
Step A: Configure the Stats
- Go to ReplicatedStorage > Modules > ItemConfigurations.
- Add your new item to the 'Items.Main' table using the exact format:
  ["My New Item"] = { Rarity = "Epic", Income = 100, ImageId = "rbxassetid://12345" },

Step B: Add the 3D Model
- Place the 3D Model of your item inside: 
  ReplicatedStorage > Items > Main > Normal
- (If you are adding specific mutations like "Neon", place it in the "Neon" folder).
- The model's name must be EXACTLY the same as the name in the config.

-----------------------------------------------------------------------------
2. ADDING NEW WEIGHTS (TRAINING TOOLS)
-----------------------------------------------------------------------------
Step A: Configure the Stats
- Go to ReplicatedStorage > Modules > WeightConfigurations.
- Add to the 'Weights' table:
  ["Huge Dumbbell"] = { Power = 50, Price = 50000, ProductId = 0, ImageId = "rbxassetid://12345" },
  (Note: Leave ProductId as nil or 0 if it costs in-game cash. Provide a real ProductId if it costs Robux).

Step B: Add the 3D Model
- Place the 3D Tool inside ReplicatedStorage > Weights.
- Name it EXACTLY "Huge Dumbbell".

-----------------------------------------------------------------------------
3. ADDING LUCKY BLOCKS
-----------------------------------------------------------------------------
Step A: Configure the Drops & Despawn
- Go to ReplicatedStorage > Modules > LuckyBlockConfigurations.
- Add your block to the 'Blocks' table:
  ["GodlyLuckyBlock"] = {
      DisplayName = "Godly Lucky Block",
      Rarity = "Legendary",
      DespawnTime = 30, -- seconds it stays on the map
      Drops = {"Item1", "Item2", "Item3"} -- MUST be valid items from ItemConfigurations
  },

Step B: Add the 3D Model
- Place the block model inside ReplicatedStorage > Items > LuckyBlocks > Normal.
- The model MUST have a PrimaryPart assigned so the pulling rope can attach to it!

-----------------------------------------------------------------------------
4. ZONES, SPAWNERS & NPC GUARDS
-----------------------------------------------------------------------------
Step A: Configure the Zone
- Go to ReplicatedStorage > Modules > ZoneConfigurations.
- Add or modify a zone number (e.g., ["7"]):
  ["7"] = {
      PowerRequirement = 1000,
      Guard = { NPCName = "Enemy7", WalkSpeed = 45 },
      LuckyBlockSpawner = {
          SpawnInterval = 10, MaxSpawnedBlocks = 5,
          Blocks = { "GodlyLuckyBlock", "AnotherBlock" }
      }
  },

Step B: Map Setup & Guard Model
- Go to Workspace > Zones. Duplicate an existing zone part and name it "7". This part acts as the spawner boundary and NPC detection zone.
- Go to ReplicatedStorage > NPCs. Add your guard model and name it EXACTLY "Enemy7" (matching the NPCName in the config).
- Ensure the NPC model has an Animator inside its Humanoid and a HumanoidRootPart.

-----------------------------------------------------------------------------
5. PLOT EXPANSION
-----------------------------------------------------------------------------
Adding New Base Floors (Upgrades):
- Go to ReplicatedStorage > Templates > Plot.
- Duplicate the highest floor (e.g., "Floor3") and rename it to "Floor4".
- Go to ServerScriptService > PlotManager and add the upgrade cost to the UPGRADE_PRICES table. Increase MAX_LEVEL.

Adding New Player Plots (More Max Players):
- Go to Workspace > Plots.
- Duplicate an existing locator part (e.g., "1") and rename it to the next number. The game automatically assigns players to free numbers.

-----------------------------------------------------------------------------
6. MONETIZATION (DEV PRODUCTS, GAMEPASSES & LIMITEDS)
-----------------------------------------------------------------------------
- Go to ReplicatedStorage > Modules > ProductConfigurations.
- Update the IDs for your products:
  > Products (SkipRebirth, RandomItem, Revive, SpinsX3, TeleportToBase)
  > GamePasses (VIP, StarterPack, ProPack)
  > LimitedItem (Configure MaxStock, StockKey, and the specific Reward).

Daily Spin Rewards:
- Go to ReplicatedStorage > Modules > DailySpinConfiguration.
- Adjust "Chance" (weight-based odds) and Reward Types ("Cash", "Spins", or "Item").

-----------------------------------------------------------------------------
REMINDERS & TROUBLESHOOTING:
- EXACT MATCHING: Always ensure your 3D Model names perfectly match the string names inside your Configuration modules.
- PRIMARY PARTS: Items, Weights, and Lucky Blocks MUST have a PrimaryPart so the scripts know how to position, weld, or attach ropes to them.
- MISSING INDEX/UI: If a UI isn't updating or the Index is blank, ensure the 3D model exists in the exact path (Items > Main > Normal) and isn't just a 2D config entry.
=============================================================================
]]