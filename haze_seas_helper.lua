--[[
    Haze Seas Helper — T3ti UI
    Requires t3ti_ui.lua / seim_ui.lua in executor workspace.

    Features:
      - Quest: best available, accept anywhere, auto-accept, warp to island then accept
      - Travel: SetSpawnPoint + TeleportToHome
      - Stats: dump free points into Fruit
      - Skills: fire Tremor fruit remotes / SkillUsed
      - Panels: quest status, player info, stat points
]]

local function loadUI()
    if _G.T3TI_UI and _G.T3TI_UI.Window then
        return _G.T3TI_UI
    end
    if _G.SEIM_UI and _G.SEIM_UI.Window then
        return _G.SEIM_UI
    end
    local paths = {
        "t3ti_ui.lua",
        "seim_ui.lua",
        "rscripts/t3ti_ui.lua",
        "rscripts/seim_ui.lua",
        [[C:\Users\v2904\Desktop\rscripts\t3ti_ui.lua]],
        [[C:\Users\v2904\Desktop\rscripts\seim_ui.lua]],
    }
    for _, p in ipairs(paths) do
        local ok, src = pcall(function()
            assert(isfile and isfile(p), "missing")
            return readfile(p)
        end)
        if ok and type(src) == "string" and #src > 100 then
            local ok2, ui = pcall(loadstring(src))
            if ok2 and ui then return ui end
        end
    end
    error("[T3ti] t3ti_ui.lua / seim_ui.lua not found")
end

local UI = loadUI()
UI.showCursor = false
UI.hideSystemCursor = false
UI.watermark = game.Players.LocalPlayer.Name
UI.showWatermark = true
pcall(function() UI:SetFont("UI") end)
pcall(function()
    local UIS = game:GetService("UserInputService")
    UIS.MouseIconEnabled = true
    UIS.MouseBehavior = Enum.MouseBehavior.Default
end)

--------------------------------------------------------------------
-- Services / refs
--------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local LP = Players.LocalPlayer
local PD = LP:WaitForChild("PlayerData")
local Exp = PD:WaitForChild("Experience")
local LevelVal = Exp:WaitForChild("Level")
local PG = LP:WaitForChild("PlayerGui")
local QuestGui = PG:WaitForChild("QuestGui")
local QuestFunction = QuestGui:WaitForChild("QuestFunction")
local CE = game.ReplicatedStorage:WaitForChild("Replication"):WaitForChild("ClientEvents")
local SetSpawnPoint = CE:WaitForChild("SetSpawnPoint")
local TeleportToHome = CE:WaitForChild("TeleportToHome")
local StatsEvent = CE:FindFirstChild("Stats_Event")
local SkillUsed = CE:FindFirstChild("SkillUsed")
local ToggleAutoQuest = CE:FindFirstChild("ToggleAutoQuest")
local VirtualInputManager = game:GetService("VirtualInputManager")

local function readAbilityKey(bindName, fallback)
    local ok, keyName = pcall(function()
        local kb = PD:FindFirstChild("Settings")
        kb = kb and kb:FindFirstChild("Keybinds")
        kb = kb and kb:FindFirstChild("PC")
        kb = kb and kb:FindFirstChild("Ability")
        local v = kb and kb:FindFirstChild(bindName)
        return v and tostring(v.Value) or nil
    end)
    local name = (ok and keyName and keyName ~= "" and keyName) or fallback
    local kc = Enum.KeyCode[name]
    return kc or Enum.KeyCode[fallback]
end

local function pressAbilityKey(keyCode)
    if not keyCode then return false end
    local ok = pcall(function()
        VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
        task.wait(0.04)
        VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
    end)
    return ok
end

local function charHakiFlags(char)
    char = char or LP.Character
    if not char then return nil end
    return {
        buso = char:FindFirstChild("BusoEnabled"),
        obs = char:FindFirstChild("ObservationHaki"),
        haki = char:FindFirstChild("Haki"),
    }
end

local State = {
    autoAccept = true, -- keep best quest for your level accepted
    autoFruit = false,
    autoSkill = false,
    skillName = "Ground Flicker",
    skillCd = 3,
    lastSkill = 0,
    lastAccept = 0,
    acceptInterval = 1.25,
    lastFruit = 0,
    status = "ready",
    bestLabel = "-",
    -- Auto Farm
    autoFarm = false,
    farmSkills = true,
    farmM1 = true, -- in-game tool:Activate — works unfocused, mouse stays free
    farmClick = false, -- OS mouse1click — NEVER needed; clicks outside Roblox
    farmMode = "Quest Target", -- or "Selected Enemy"
    farmEnemy = "Holy Soldier",
    farmRange = 10,
    farmMelee = 6, -- Activate only when this close (Thunder God needs ~5)
    farmSkillCd = 0.85,
    lastFarmSkill = 0,
    lastFarmClick = 0,
    lastFarmM1 = 0,
    farmHeight = 1.5,
    skillEnabled = {},
    m1Tool = "Auto",
    -- Auto Haki / Buso (keybinds from Settings; default J buso / K obs)
    autoBuso = true,
    autoHaki = true, -- Observation Haki
    lastHakiToggle = 0,
}

-- Survive loadstring reloads + allow MCP live tests
local Persist = rawget(getgenv(), "T3TI_Persist")
if type(Persist) ~= "table" then
    Persist = {}
    getgenv().T3TI_Persist = Persist
end
if Persist.autoFarm == true then
    State.autoFarm = true
end
if Persist.autoAccept ~= nil then
    State.autoAccept = Persist.autoAccept and true or false
end
if Persist.autoBuso ~= nil then
    State.autoBuso = Persist.autoBuso and true or false
end
if Persist.autoHaki ~= nil then
    State.autoHaki = Persist.autoHaki and true or false
end
getgenv().T3TI_State = State
getgenv().T3TI_FarmErr = nil

local function savePersist()
    Persist.autoFarm = State.autoFarm and true or false
    Persist.autoAccept = State.autoAccept and true or false
    Persist.autoBuso = State.autoBuso and true or false
    Persist.autoHaki = State.autoHaki and true or false
end

-- MUST be after State (Luau treats earlier refs as a different nil global)
local function ensureAutoHaki(force)
    if not (State.autoBuso or State.autoHaki) then return false end
    if not force and tick() - (State.lastHakiToggle or 0) < 0.35 then
        return false
    end
    local flags = charHakiFlags()
    if not flags then return false end

    local pressed = false
    -- Buso (Armament) — keep ON
    if State.autoBuso and flags.buso and flags.buso.Value ~= true then
        State.lastHakiToggle = tick()
        pressAbilityKey(readAbilityKey("HakiBuso", "J"))
        pressed = true
        task.wait(0.12)
        flags = charHakiFlags() or flags
    end
    -- Observation Haki — keep ON
    if State.autoHaki and flags.obs and flags.obs.Value ~= true then
        State.lastHakiToggle = tick()
        pressAbilityKey(readAbilityKey("HakiObs", "K"))
        pressed = true
    end
    return pressed
end

-- Always-on keeper (not tied to farm). Re-enables after death / knockoff.
task.spawn(function()
    while UI.alive do
        pcall(ensureAutoHaki)
        task.wait(0.4)
    end
end)

LP.CharacterAdded:Connect(function()
    task.delay(1.0, function()
        if UI.alive then
            pcall(function()
                ensureAutoHaki(true)
            end)
        end
    end)
end)

local function notify(t, b, k)
    UI.Notify(t, b or "", 3, k or "good")
end

local function questGivers()
    local root = workspace:FindFirstChild("Npc_Workspace")
        or workspace:FindFirstChild("NPC_Workspace")
    return root and root:FindFirstChild("QuestGivers")
end

local function giverDisplay(g)
    local dn = g:FindFirstChild("DisplayName")
    if dn and dn.Value then
        return tostring(dn.Value):match("^([^|]+)") or tostring(dn.Value)
    end
    local oh = g:FindFirstChild("NPCOverhead")
    if oh then
        for _, d in ipairs(oh:GetDescendants()) do
            if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and #d.Text < 40 then
                return d.Text
            end
        end
    end
    return g.Name
end

local function parseLevelKey(name)
    local n = tostring(name):match("Level%s*(%d+)")
    return n and tonumber(n) or nil
end

local function listQuestOptions(g)
    local out = {}
    local cfg = g:FindFirstChild("Configuration")
    local qf = cfg and cfg:FindFirstChild("Quests")
    if not qf then return out end
    for _, folder in ipairs(qf:GetChildren()) do
        local lvl = parseLevelKey(folder.Name)
        if lvl then
            local target = nil
            for _, sub in ipairs(folder:GetChildren()) do
                if sub:IsA("Folder") and sub.Name ~= "Layout" then
                    target = sub.Name
                    break
                end
            end
            out[#out + 1] = {
                key = folder.Name,
                level = lvl,
                target = target or folder.Name,
                giver = g,
                location = g:GetAttribute("Location"),
                display = giverDisplay(g),
            }
        end
    end
    table.sort(out, function(a, b) return a.level < b.level end)
    return out
end

local function allOptions()
    local qg = questGivers()
    local all = {}
    if not qg then return all end
    for _, g in ipairs(qg:GetChildren()) do
        for _, opt in ipairs(listQuestOptions(g)) do
            all[#all + 1] = opt
        end
    end
    table.sort(all, function(a, b) return a.level < b.level end)
    return all
end

local function bestQuest(level)
    level = level or LevelVal.Value
    local best = nil
    for _, opt in ipairs(allOptions()) do
        if opt.level <= level then
            best = opt
        end
    end
    return best
end

local function nextUnlock(level)
    level = level or LevelVal.Value
    for _, opt in ipairs(allOptions()) do
        if opt.level > level then return opt end
    end
end

local function acceptQuest(opt)
    if not opt then return false, "no quest" end
    local ok, err = pcall(function()
        return QuestFunction:InvokeServer(opt.giver, opt.key)
    end)
    if not ok then return false, tostring(err) end
    -- common failure strings
    if type(err) == "string" and err ~= "" and err:lower():find("already") then
        return false, err
    end
    return true, err
end

-- Set by accept / farm when we need an immediate repath (don't wait for distance gates)
local _forceFarmRepath = false
local function requestFarmRepath()
    _forceFarmRepath = true
end

local function spawnNames()
    local names = {}
    local root = workspace:FindFirstChild("Npc_Workspace")
        or workspace:FindFirstChild("NPC_Workspace")
    local folder = root and root:FindFirstChild("Spawn Setters")
    if folder then
        for _, d in ipairs(folder:GetChildren()) do
            names[#names + 1] = d.Name
        end
    else
        for _, d in ipairs(workspace:GetDescendants()) do
            if d.Parent and d.Parent.Name == "Spawn Setters" then
                names[#names + 1] = d.Name
            end
        end
    end
    table.sort(names)
    return names
end

local function matchSpawn(location)
    if not location then return nil end
    local names = spawnNames()
    local loc = tostring(location):lower()
    for _, n in ipairs(names) do
        if n:lower() == loc then return n end
    end
    for _, n in ipairs(names) do
        local nl = n:lower()
        if nl:find(loc, 1, true) or loc:find(nl, 1, true) then return n end
    end
    -- Skypeia typo variants
    if loc:find("skyp") then
        for _, n in ipairs(names) do
            if n:lower():find("skyp") then return n end
        end
    end
    return nil
end

local function warpTo(spawnName)
    if not spawnName then return false, "no spawn" end
    local ok1, e1 = pcall(function()
        SetSpawnPoint:FireServer(spawnName)
    end)
    if not ok1 then return false, tostring(e1) end
    task.wait(0.4)
    -- TeleportToHome is a RemoteFunction (not RemoteEvent)
    local ok2, e2 = pcall(function()
        if TeleportToHome:IsA("RemoteFunction") then
            return TeleportToHome:InvokeServer()
        end
        return TeleportToHome:FireServer()
    end)
    if not ok2 then return false, tostring(e2) end
    return true, e2
end

local function teleportHomeOnly()
    local ok, err = pcall(function()
        if TeleportToHome:IsA("RemoteFunction") then
            return TeleportToHome:InvokeServer()
        end
        return TeleportToHome:FireServer()
    end)
    return ok, err
end

local function freeStatPoints()
    -- discover common point fields
    for _, name in ipairs({ "StatPoints", "Points", "FreePoints", "SkillPoints", "AttributePoints" }) do
        local v = PD:FindFirstChild(name, true)
        if v and v:IsA("ValueBase") and typeof(v.Value) == "number" and v.Value > 0 then
            return v
        end
    end
    for _, d in ipairs(PD:GetDescendants()) do
        if d:IsA("ValueBase") and d.Name:lower():find("point") and typeof(d.Value) == "number" and d.Value > 0 then
            return d
        end
    end
end

local function dumpFruit(points)
    if not StatsEvent then return false, "Stats_Event missing" end
    points = points or 1
    local ok, err = pcall(function()
        StatsEvent:FireServer("Fruit", points)
    end)
    return ok, err
end

local function fruitFolder()
    local fp = PG:FindFirstChild("FruitPowers")
    if not fp then return nil end
    -- whatever fruit folder is currently loaded (= equipped fruit)
    return fp:GetChildren()[1]
end

local function currentFruitName()
    local f = fruitFolder()
    return f and f.Name or nil
end

-- Combat / fruit / sword tools in Character + Backpack
local function inventoryToolNames()
    local names, seen = {}, {}
    local function add(container)
        if not container then return end
        for _, t in ipairs(container:GetChildren()) do
            if t:IsA("Tool") and not seen[t.Name] then
                seen[t.Name] = true
                names[#names + 1] = t.Name
            end
        end
    end
    add(LP.Character)
    add(LP:FindFirstChild("Backpack"))
    table.sort(names)
    return names
end

local function findToolByName(name)
    if not name or name == "" or name == "Auto" then return nil end
    local char = LP.Character
    local bp = LP:FindFirstChild("Backpack")
    return (char and char:FindFirstChild(name))
        or (bp and bp:FindFirstChild(name))
end

-- M1 tool: Auto → tool named like current fruit, else held tool, else Combat
local function resolveM1Tool()
    local char = LP.Character
    local pick = State.m1Tool
    if pick and pick ~= "Auto" then
        local t = findToolByName(pick)
        if t then return t end
    end
    local fruit = currentFruitName()
    if fruit then
        local t = findToolByName(fruit)
        if t then return t end
    end
    if char then
        local held = char:FindFirstChildOfClass("Tool")
        if held then return held end
    end
    return findToolByName("Combat") or findToolByName("Katana")
end

local function ensureM1ToolEquipped()
    local tool = resolveM1Tool()
    if not tool then return nil end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if char and hum and tool.Parent ~= char then
        pcall(function()
            hum:EquipTool(tool)
        end)
        tool = char:FindFirstChild(tool.Name) or tool
    end
    return tool
end

-- All fruit remotes (minus *2 variants)
local function skillRemoteNames()
    local fruit = fruitFolder()
    local ev = fruit and fruit:FindFirstChild("Events")
    local names = {}
    if not ev then return names end
    for _, r in ipairs(ev:GetChildren()) do
        if r:IsA("RemoteEvent") and not r.Name:match("2$") then
            names[#names + 1] = r.Name
        end
    end
    table.sort(names)
    return names
end

-- Skills on the CURRENT fruit (Configuration = owned/equipped moves)
local function equippedSkillNames()
    local fruit = fruitFolder()
    if not fruit then return {} end
    local ev = fruit:FindFirstChild("Events")
    local names, seen = {}, {}
    for _, c in ipairs(fruit:GetChildren()) do
        if c:IsA("Configuration") then
            local attack = c:FindFirstChild("AttackNameString")
            local name = tostring((attack and attack.Value) or c.Name)
            local remote = ev and ev:FindFirstChild(name)
            if remote and remote:IsA("RemoteEvent") and not seen[name] then
                seen[name] = true
                names[#names + 1] = name
            end
        end
    end
    table.sort(names)
    if #names == 0 then
        return skillRemoteNames()
    end
    return names
end

local function ensureSkillDefaults()
    for _, n in ipairs(equippedSkillNames()) do
        if State.skillEnabled[n] == nil then
            State.skillEnabled[n] = true
        end
    end
end

-- Skills ticked in Specify (new skills default ON)
local function selectedSkillNames()
    ensureSkillDefaults()
    local out = {}
    for _, n in ipairs(equippedSkillNames()) do
        if State.skillEnabled[n] ~= false then
            out[#out + 1] = n
        end
    end
    return out
end

local function castSkill(name)
    name = name or State.skillName
    local fruit = fruitFolder()
    local ev = fruit and fruit:FindFirstChild("Events")
    local remote = ev and ev:FindFirstChild(name)
    local pos = State.aimPos
    local hit = State.aimHit
    if remote and remote:IsA("RemoteEvent") then
        local ok, err = pcall(function()
            if typeof(pos) == "Vector3" then
                remote:FireServer(pos)
            else
                remote:FireServer()
            end
        end)
        if not ok and hit then
            ok, err = pcall(function() remote:FireServer(hit) end)
        end
        if not ok then
            ok, err = pcall(function() remote:FireServer() end)
        end
        if ok and SkillUsed then
            pcall(function() SkillUsed:FireServer(name) end)
        end
        return ok, err
    end
    if SkillUsed then
        local ok, err = pcall(function() SkillUsed:FireServer(name) end)
        return ok, err
    end
    return false, "skill remote missing"
end

-- In-game M1 via fruit/weapon tool Activate — no OS click, mouse stays free
local function doFarmM1()
    -- allow during farm even if menu somehow open
    if UI._booting then
        return false
    end
    local tool = ensureM1ToolEquipped()
    if not tool then
        return false
    end
    -- re-equip if game swapped us to Combat mid-fight
    local char = LP.Character
    if char and tool.Parent ~= char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function()
                hum:EquipTool(tool)
            end)
            tool = char:FindFirstChild(tool.Name) or tool
        end
    end
    return (pcall(function()
        tool:Activate()
    end))
end

-- Normalize quest-option folder names into an NPC search string
local function cleanEnemyName(name)
    local m = tostring(name or ""):gsub("%s+$", ""):gsub("^%s+", "")
    if m == "" then return nil end
    if m:sub(-1) == "s" and not m:lower():find("boss") then
        local sing = m:sub(1, -2)
        if #sing > 3 then m = sing end
    end
    return m
end

-- Active kill quest only ("Kill 5 Holy Soldiers" -> "Holy Soldier").
-- Do NOT use "Quest: Title" — that's the quest name, not the NPC (and shows even when inactive).
local function currentQuestTarget()
    local qg = QuestGui
    if not qg then return nil end
    local function clean(m)
        return cleanEnemyName(m)
    end
    for _, d in ipairs(qg:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local t = d.Text or ""
            local m = t:match("[Kk]ill%s+%d+%s+(.+)")
                or t:match("[Dd]efeat%s+%d+%s+(.+)")
            if m then
                return clean(m)
            end
        end
    end
end

local function gameAutoQuestEnabled()
    local qg = QuestGui
    if not qg then return false end
    for _, d in ipairs(qg:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text then
            local t = tostring(d.Text):lower()
            if t:find("auto quest") and t:find("enabled") then
                return true
            end
        end
    end
    return false
end

local function disableGameAutoQuest()
    if not ToggleAutoQuest then return end
    for _ = 1, 3 do
        if not gameAutoQuestEnabled() then return end
        pcall(function()
            ToggleAutoQuest:FireServer()
        end)
        task.wait(0.2)
    end
end

local function ensureBestQuest()
    disableGameAutoQuest()
    local best = bestQuest()
    if not best then
        local active = currentQuestTarget()
        return active ~= nil, active or "no quest for level"
    end
    local want = cleanEnemyName(best.target) or best.key
    local active = currentQuestTarget()
    -- Game AutoQuest often locks low-level trash (Bandit) at high level — replace it
    if active and tostring(active):lower() == tostring(want):lower() then
        return true, active
    end
    local ok, err = acceptQuest(best)
    if ok then
        requestFarmRepath()
        return true, want
    end
    -- accept failed but we still have something
    if active then
        return true, active
    end
    return false, err or "accept failed"
end

-- Spawn pad parts live under ObservationHaki SpawnPoints
local function findQuestSpawnPads(targetName)
    local key = tostring(targetName or ""):lower()
    if key == "" then return {} end
    local pads = {}
    local root = PG:FindFirstChild("ObservationHaki_Server", true)
    root = root and root:FindFirstChild("SpawnPoints", true)
    if not root then return pads end
    for _, island in ipairs(root:GetChildren()) do
        for _, p in ipairs(island:GetChildren()) do
            if p:IsA("BasePart") and p.Name:lower():find(key, 1, true) then
                pads[#pads + 1] = { part = p, island = island.Name, name = p.Name, pos = p.Position }
            end
        end
    end
    return pads
end

--[[
  Safe stand offsets from spawn-pad center (out of melee, still can aim pad).
  Calibrated: Marine Captain — player's rooftop perch ~276 flat / +162 up.
]]
local SAFE_PAD_OFFSET = {
    ["Marine Captain"] = Vector3.new(-259.4, 161.6, 94.3),
}

local function padCenter(pads)
    if not pads or #pads == 0 then return nil end
    local cx, cy, cz = 0, 0, 0
    for _, p in ipairs(pads) do
        cx += p.pos.X
        cy += p.pos.Y
        cz += p.pos.Z
    end
    return Vector3.new(cx / #pads, cy / #pads, cz / #pads)
end

local function safeStandForPad(pad, targetName)
    local off = SAFE_PAD_OFFSET[targetName]
    if off then
        return pad + off
    end
    -- generic: high + far on a fixed world axis (still out of reach)
    return pad + Vector3.new(-220, 150, 80)
end

-- Name aliases. Holy Soldier ≠ Divine Soldier (different pads/heights).
-- Only alias when names are truly interchangeable.
local QUEST_NPC_ALIASES = {
    -- none for holy/divine — keep them separate
}

local function questTargetKeys(targetName)
    local key = tostring(targetName or ""):lower():gsub("%s+$", "")
    if key == "" then return {} end
    return QUEST_NPC_ALIASES[key] or { key }
end

local function npcNameMatches(instName, keys)
    local n = tostring(instName or ""):lower()
    n = n:gsub("%d+$", ""):gsub("%s+$", "")
    for _, k in ipairs(keys) do
        -- exact / contains key only — avoid k:find(n) which lets "soldier" match everything
        if n == k or n:find(k, 1, true) then
            return true
        end
    end
    return false
end

-- Collect ObservationHaki pads for any alias key
local function allQuestPads(keys)
    local pads = {}
    local seen = {}
    for _, k in ipairs(keys) do
        for _, p in ipairs(findQuestSpawnPads(k)) do
            local id = p.part
            if not seen[id] then
                seen[id] = true
                pads[#pads + 1] = p
            end
        end
    end
    return pads
end

--[[
  Pick stand for current kill quest.
  Prefer nearest LIVE npc matching the quest name exactly (Holy ≠ Divine).
  Else nearest ObservationHaki pad for that name (Holy pads sit higher on Sky Islands).
]]
local function questKillStand(targetName)
    targetName = targetName or currentQuestTarget()
    if not targetName then return nil, "no active kill quest" end

    local keys = questTargetKeys(targetName)
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    local from = hrp and hrp.Position
    if not from then return nil, "no character" end

    local nearest, nearestDist, count, hitName = nil, math.huge, 0, nil

    local function considerModel(m)
        if not m:IsA("Model") then return end
        if not npcNameMatches(m.Name, keys) then return end
        local hum = m:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health <= 0 then return end
        local ok, piv = pcall(function() return m:GetPivot().Position end)
        if not ok or not piv then return end
        count += 1
        local d = (piv - from).Magnitude
        if d < nearestDist then
            nearestDist = d
            nearest = piv
            hitName = m.Name
        end
    end

    local zones = workspace:FindFirstChild("NPC Zones")
    if zones then
        for _, zone in ipairs(zones:GetChildren()) do
            local npcs = zone:FindFirstChild("NPCS") or zone:FindFirstChild("NPCs")
            if npcs then
                for _, m in ipairs(npcs:GetChildren()) do
                    considerModel(m)
                end
            end
        end
    end

    if nearest then
        local stand = nearest + Vector3.new(0, 5, 0)
        return stand, count, targetName, "npc:" .. tostring(hitName), nearestDist
    end

    local pads = allQuestPads(keys)
    local bestPad, bestPadDist = nil, math.huge
    for _, p in ipairs(pads) do
        local d = (p.pos - from).Magnitude
        if d < bestPadDist then
            bestPadDist = d
            bestPad = p
        end
    end
    if bestPad then
        -- Stable wait perch: slightly above pad, fixed offset (no moving goal)
        return bestPad.pos + Vector3.new(8, 6, 8), #pads, targetName, "pad:" .. bestPad.name, bestPadDist
    end

    return nil, "no NPCs/pads for " .. targetName
end

--[[
  Straight-line noclip BV fly.
  Refresh CanCollide=false + PlatformStand.
  Stuck = sideways nudge only — never +Y sky hop.
]]
local _questFlyToken = 0
local _farmNoclipCache = nil

local function setNoclip(char, on, cache)
    cache = cache or {}
    if not char then return cache end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            if on then
                if cache[p] == nil then
                    cache[p] = {
                        collide = p.CanCollide,
                        query = p.CanQuery,
                        touch = p.CanTouch,
                    }
                end
                p.CanCollide = false
                pcall(function()
                    p.CanQuery = false
                    p.CanTouch = false
                end)
            elseif cache[p] ~= nil then
                local c = cache[p]
                if type(c) == "boolean" then
                    p.CanCollide = c
                else
                    p.CanCollide = c.collide ~= false
                    pcall(function()
                        p.CanQuery = c.query ~= false
                        p.CanTouch = c.touch ~= false
                    end)
                end
            end
        end
    end
    return cache
end

local function setFlyHumanoid(hum, on)
    if not hum then return end
    pcall(function()
        if on then
            hum.PlatformStand = true
            hum.AutoRotate = false
            hum:ChangeState(Enum.HumanoidStateType.Physics)
        else
            hum.PlatformStand = false
            hum.AutoRotate = true
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end)
end

local function bvFlyTo(goal, opts)
    opts = opts or {}
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or typeof(goal) ~= "Vector3" then
        return false, "no character/goal"
    end

    _questFlyToken += 1
    local token = _questFlyToken
    local speed = opts.speed or 700
    local arrive = opts.arrive or 12
    local keepNoclip = opts.keepNoclip == true

    for _, n in ipairs({
        "T3tiQuestFly", "T3tiQuestGyro", "T3tiFarmHold", "T3tiFarmGyro",
        "T3tiAF", "T3tiAFG", "T3tiTest", "T3tiTestG", "T3tiRescue",
    }) do
        local old = hrp:FindFirstChild(n)
        if old then pcall(function() old:Destroy() end) end
    end

    local collCache = setNoclip(char, true, {})
    setFlyHumanoid(hum, true)

    local addConn
    addConn = char.DescendantAdded:Connect(function(inst)
        if token ~= _questFlyToken then return end
        if inst:IsA("BasePart") then
            if collCache[inst] == nil then
                collCache[inst] = {
                    collide = inst.CanCollide,
                    query = inst.CanQuery,
                    touch = inst.CanTouch,
                }
            end
            inst.CanCollide = false
            pcall(function()
                inst.CanQuery = false
                inst.CanTouch = false
            end)
        end
    end)

    local bv = Instance.new("BodyVelocity")
    bv.Name = "T3tiQuestFly"
    bv.MaxForce = Vector3.new(1, 1, 1) * 4e10
    bv.P = 40000
    bv.Velocity = Vector3.zero
    bv.Parent = hrp

    local bg = Instance.new("BodyGyro")
    bg.Name = "T3tiQuestGyro"
    bg.MaxTorque = Vector3.new(1, 1, 1) * 4e10
    bg.P = 20000
    bg.D = 800
    bg.CFrame = hrp.CFrame
    bg.Parent = hrp

    local dist0 = (goal - hrp.Position).Magnitude
    local t0 = tick()
    local maxT = math.clamp(dist0 / math.max(200, speed) + 10, 8, 55)
    local okArrive = false
    local lastPos = hrp.Position
    local stuckFor = 0
    local tickN = 0
    local sideSign = 1

    while token == _questFlyToken and hrp.Parent and UI.alive and (tick() - t0) < maxT do
        if opts.cancel and opts.cancel() then break end
        tickN += 1
        if tickN % 2 == 0 then
            setNoclip(char, true, collCache)
            setFlyHumanoid(hum, true)
        end

        local pos = hrp.Position
        -- always aim at goal; if above it, dive (never climb further)
        local target = goal
        local delta = target - pos
        local dist = delta.Magnitude
        if dist <= arrive then
            okArrive = true
            break
        end

        local moved = (pos - lastPos).Magnitude
        if dist > arrive + 4 and moved < 0.4 then
            stuckFor += 1
        else
            stuckFor = math.max(0, stuckFor - 2)
        end
        lastPos = pos

        local dir = delta.Unit
        local v = speed

        -- stuck: sideways around obstacle (XZ), pull Y toward goal only — no sky hop
        if stuckFor >= 6 then
            stuckFor = 0
            sideSign = -sideSign
            local flat = Vector3.new(delta.X, 0, delta.Z)
            local side
            if flat.Magnitude > 1 then
                side = Vector3.new(-flat.Z, 0, flat.X).Unit * sideSign
            else
                side = Vector3.new(sideSign, 0, 0)
            end
            local bypass = pos
                + side * 18
                + Vector3.new(0, math.clamp(goal.Y - pos.Y, -10, 10), 0)
            bypass = bypass:Lerp(goal, 0.45)
            local bd = bypass - pos
            if bd.Magnitude > 1e-3 then
                dir = bd.Unit
            end
            v = math.clamp(speed * 0.85, 220, 650)
        elseif dist < 30 then
            v = math.clamp(speed * (dist / 30), 120, speed)
        end

        -- hard ceiling: never drive upward past goal+25
        if pos.Y > goal.Y + 25 and dir.Y > 0 then
            dir = Vector3.new(dir.X, -0.35, dir.Z)
            if dir.Magnitude > 1e-3 then
                dir = dir.Unit
            else
                dir = Vector3.new(0, -1, 0)
            end
        end

        bv.Velocity = dir * v
        pcall(function()
            hrp.AssemblyLinearVelocity = dir * v
        end)
        bg.CFrame = CFrame.lookAt(pos, Vector3.new(goal.X, pos.Y, goal.Z))
        RunService.Heartbeat:Wait()
    end

    pcall(function()
        if addConn then addConn:Disconnect() end
    end)
    pcall(function()
        bv.Velocity = Vector3.zero
        bv:Destroy()
        bg:Destroy()
    end)
    if not keepNoclip then
        setFlyHumanoid(hum, false)
        setNoclip(char, false, collCache)
    end

    if token ~= _questFlyToken then
        return false, "cancelled", collCache
    end
    local settle = (hrp.Position - goal).Magnitude
    if not okArrive and settle > 40 then
        return false, "timeout", collCache
    end
    return settle <= 50, settle <= 50 and "ok" or "rubberband", collCache
end

-- Keep floating at a FIXED combat stand (stiff — no orbit / chase)
local function farmHoldAt(goal, lookAt)
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or typeof(goal) ~= "Vector3" then return end

    -- kill travel movers so they don't fight the hold
    for _, n in ipairs({ "T3tiQuestFly", "T3tiQuestGyro" }) do
        local o = hrp:FindFirstChild(n)
        if o then pcall(function() o:Destroy() end) end
    end

    local ceilY = goal.Y + 6
    if typeof(lookAt) == "Vector3" then
        ceilY = math.min(ceilY, lookAt.Y + 8)
    end
    if goal.Y > ceilY then
        goal = Vector3.new(goal.X, ceilY, goal.Z)
    end

    _farmNoclipCache = setNoclip(char, true, _farmNoclipCache or {})
    setFlyHumanoid(hum, true)

    local bv = hrp:FindFirstChild("T3tiFarmHold")
    if not bv then
        bv = Instance.new("BodyVelocity")
        bv.Name = "T3tiFarmHold"
        bv.MaxForce = Vector3.new(1, 1, 1) * 4e10
        bv.P = 50000
        bv.Parent = hrp
    end
    local bg = hrp:FindFirstChild("T3tiFarmGyro")
    if not bg then
        bg = Instance.new("BodyGyro")
        bg.Name = "T3tiFarmGyro"
        bg.MaxTorque = Vector3.new(1, 1, 1) * 4e10
        bg.P = 30000
        bg.D = 900
        bg.Parent = hrp
    end

    local delta = goal - hrp.Position
    local dist = delta.Magnitude
    if dist < 1.5 then
        -- stay still — do NOT CFrame-snap every frame (fights server → freeze)
        bv.Velocity = Vector3.zero
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.zero
        end)
    elseif dist < 8 then
        -- soft correct — no flinging
        local spd = math.clamp(dist * 12, 24, 110)
        bv.Velocity = delta.Unit * spd
        pcall(function()
            hrp.AssemblyLinearVelocity = delta.Unit * spd
        end)
    elseif hrp.Position.Y > goal.Y + 14 then
        local spd = math.clamp(dist * 22, 120, 550)
        bv.Velocity = delta.Unit * spd
    else
        local spd = math.clamp(dist * 14, 40, 280)
        bv.Velocity = delta.Unit * spd
    end

    local look = lookAt or goal
    bg.CFrame = CFrame.lookAt(
        Vector3.new(hrp.Position.X, goal.Y, hrp.Position.Z),
        Vector3.new(look.X, goal.Y, look.Z)
    )
end

local function stopFarmHold()
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hrp then
        for _, n in ipairs({ "T3tiFarmHold", "T3tiFarmGyro" }) do
            local o = hrp:FindFirstChild(n)
            if o then pcall(function() o:Destroy() end) end
        end
    end
    if not State.autoFarm then
        setFlyHumanoid(hum, false)
    end
end

local function slowTweenToQuestTarget()
    local stand, countOrErr, targetName, kind, dist0 = questKillStand()
    if not stand then return false, countOrErr end
    local ok, info = bvFlyTo(stand, { speed = 900, arrive = 12 })
    if not ok then return false, tostring(info) .. " · " .. tostring(kind) end
    return true, string.format("%s · BV-noclip · %s · %.0f studs", tostring(targetName), tostring(kind), dist0 or 0)
end

-- Enemy name list from streamed NPC Zones
local function listEnemyNames()
    local seen, names = {}, {}
    local zones = workspace:FindFirstChild("NPC Zones")
    if zones then
        for _, zone in ipairs(zones:GetChildren()) do
            local npcs = zone:FindFirstChild("NPCS") or zone:FindFirstChild("NPCs")
            if npcs then
                for _, m in ipairs(npcs:GetChildren()) do
                    if m:IsA("Model") then
                        local base = m.Name:gsub("%d+$", ""):gsub("%s+$", "")
                        if base ~= "" and not seen[base] then
                            seen[base] = true
                            names[#names + 1] = base
                        end
                    end
                end
            end
        end
    end
    table.sort(names)
    if #names == 0 then
        names = { "Holy Soldier", "Divine Soldier", "Marine Captain", "Marine Grunt" }
    end
    return names
end

local function farmTargetName()
    if State.farmMode == "Selected Enemy" then
        return State.farmEnemy
    end
    -- Active Kill-quest NPC, else best quest for your level (e.g. Holy Soldier @ 1050)
    local fromGui = currentQuestTarget()
    if fromGui then return fromGui end
    local best = bestQuest()
    if best and best.target then
        local cleaned = cleanEnemyName(best.target)
        if cleaned and not tostring(cleaned):lower():find("level") then
            return cleaned
        end
    end
    return State.farmEnemy
end

local function forEachZoneNpc(fn)
    local zones = workspace:FindFirstChild("NPC Zones")
    if not zones then return end
    for _, zone in ipairs(zones:GetChildren()) do
        local npcs = zone:FindFirstChild("NPCS") or zone:FindFirstChild("NPCs")
        if npcs then
            for _, m in ipairs(npcs:GetChildren()) do
                fn(m)
            end
        else
            for _, m in ipairs(zone:GetDescendants()) do
                if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then
                    fn(m)
                end
            end
        end
    end
end

local function findNearestEnemyModel(targetName)
    targetName = targetName or farmTargetName()
    if not targetName then return nil end
    local keys = questTargetKeys(targetName)
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    local from = hrp and hrp.Position
    if not from then return nil end

    local best, bestDist, bestPos = nil, math.huge, nil
    forEachZoneNpc(function(m)
        if not m:IsA("Model") then return end
        if not npcNameMatches(m.Name, keys) then return end
        local hum = m:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        local ok, piv = pcall(function() return m:GetPivot().Position end)
        if not ok or not piv then return end
        local d = (piv - from).Magnitude
        if d < bestDist then
            bestDist = d
            best = m
            bestPos = piv
        end
    end)
    return best, bestPos, bestDist
end

--------------------------------------------------------------------
-- Virtual mouse aim — spoofs Mouse.Hit / GetMouseLocation in-memory.
-- Does NOT move the OS cursor, so you can freely look / click the UI.
--------------------------------------------------------------------
local Aim = {
    on = false,
    hit = nil, -- CFrame
    target = nil, -- Instance?
    screen = Vector2.new(0, 0),
    _hooked = false,
}

local UpdateMousePosition = CE:FindFirstChild("UpdateMousePosition")

local function clearVirtualAim()
    Aim.on = false
    Aim.hit = nil
    Aim.target = nil
    State.aimPos = nil
    State.aimHit = nil
end

local function setVirtualAim(pos, targetInst)
    local cam = workspace.CurrentCamera
    if not cam or typeof(pos) ~= "Vector3" then return false end
    local origin = cam.CFrame.Position
    local dir = pos - origin
    if dir.Magnitude < 1e-4 then return false end
    Aim.hit = CFrame.lookAt(pos, pos + dir.Unit)
    Aim.target = targetInst
    local sx, sy = cam:WorldToViewportPoint(pos)
    Aim.screen = Vector2.new(sx, sy)
    Aim.on = true
    State.aimPos = pos
    State.aimHit = Aim.hit
    -- Some games also listen for a mouse-pos remote
    if UpdateMousePosition and UpdateMousePosition:IsA("RemoteEvent") then
        pcall(function()
            UpdateMousePosition:FireServer(pos)
        end)
    end
    return true
end

local function installVirtualMouse()
    if Aim._hooked then return end
    if type(hookmetamethod) ~= "function" then return end
    Aim._hooked = true

    local mouse = LP:GetMouse()
    local oldIndex
    oldIndex = hookmetamethod(game, "__index", newcclosure and newcclosure(function(self, key)
        if Aim.on and self == mouse then
            if key == "Hit" and Aim.hit then return Aim.hit end
            if key == "Target" then return Aim.target end
            if key == "HitPosition" and Aim.hit then return Aim.hit.Position end
            if key == "UnitRay" and Aim.hit then
                local cam = workspace.CurrentCamera
                local o = cam and cam.CFrame.Position or Vector3.zero
                local p = Aim.hit.Position
                return Ray.new(o, (p - o).Unit * 1000)
            end
            if key == "X" then return Aim.screen.X end
            if key == "Y" then return Aim.screen.Y end
        end
        return oldIndex(self, key)
    end) or function(self, key)
        if Aim.on and self == mouse then
            if key == "Hit" and Aim.hit then return Aim.hit end
            if key == "Target" then return Aim.target end
            if key == "X" then return Aim.screen.X end
            if key == "Y" then return Aim.screen.Y end
        end
        return oldIndex(self, key)
    end)

    if type(getnamecallmethod) == "function" then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure and newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if Aim.on and not UI.uiVisible and self == UserInputService and method == "GetMouseLocation" then
                return Aim.screen
            end
            return oldNamecall(self, ...)
        end) or function(self, ...)
            local method = getnamecallmethod()
            if Aim.on and not UI.uiVisible and self == UserInputService and method == "GetMouseLocation" then
                return Aim.screen
            end
            return oldNamecall(self, ...)
        end)
    end
end

pcall(installVirtualMouse)

-- Face character at target without touching the OS mouse / camera look.
local function faceWorld(pos)
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not hrp or typeof(pos) ~= "Vector3" then return end
    local flat = Vector3.new(pos.X, hrp.Position.Y, pos.Z)
    if (flat - hrp.Position).Magnitude < 0.05 then return end
    pcall(function()
        hrp.CFrame = CFrame.lookAt(hrp.Position, flat)
    end)
end

local function farmClick()
    -- OS-level click — only if user explicitly enables it (clicks outside Roblox too)
    if UI.uiVisible or UI._booting then
        return false
    end
    if UI._ignoreClickUntil and tick() < UI._ignoreClickUntil then
        return false
    end
    if type(mouse1click) == "function" then
        UI._ignoreClickUntil = tick() + 0.08
        pcall(mouse1click)
        return true
    end
    return false
end

local function castFarmSkills(aimPos, aimTarget)
    if aimPos then
        setVirtualAim(aimPos, aimTarget)
        faceWorld(aimPos)
    end
    -- make sure fruit/weapon tool is out so skill remotes register
    ensureM1ToolEquipped()
    local picks = selectedSkillNames()
    if #picks == 0 then
        return
    end
    for _, n in ipairs(picks) do
        castSkill(n)
        task.wait(0.08)
    end
end

local function stopFarmNoclip()
    stopFarmHold()
    local char = LP.Character
    if char and _farmNoclipCache then
        setNoclip(char, false, _farmNoclipCache)
    end
    _farmNoclipCache = nil
end

-- Tween to safe perch, aim mouse at pad center, cast Sea Rift
local function seaRiftPadClear()
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "no character" end

    local target = currentQuestTarget()
    if not target then return false, "no active kill quest" end

    local keys = questTargetKeys(target)
    local pads = allQuestPads(keys)
    local from = hrp.Position
    local best, bestD = nil, math.huge
    for _, p in ipairs(pads) do
        local d = (p.pos - from).Magnitude
        if d < bestD then
            bestD = d
            best = p
        end
    end
    local pad = best and best.pos
    if not pad then return false, "no spawn pad for " .. target end

    local stand = safeStandForPad(pad, target)
    pcall(function()
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    end)

    local lookFlat = Vector3.new(pad.X, stand.Y, pad.Z)
    local goal = CFrame.lookAt(stand, lookFlat)
    local tw = TweenService:Create(
        hrp,
        TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { CFrame = goal }
    )
    tw:Play()
    tw.Completed:Wait()
    hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(pad.X, hrp.Position.Y, pad.Z))
    task.wait(0.12)

    setVirtualAim(pad, nil)
    task.wait(0.05)

    local ok, err = castSkill("Sea Rift")
    clearVirtualAim()
    return ok, err, target, pad, stand
end

--------------------------------------------------------------------
-- UI
--------------------------------------------------------------------
local win = UI:Window({ title = "Haze Seas", x = 80, y = 60, w = 360, visible = false })
pcall(function() UI:AutoScaleFromViewport() end)

-- Quests
do
    local tab = win:Tab("Quests")
    local s1 = tab:Section("Accept")
    s1:Label("Accept uses QuestFunction from anywhere")
    s1:Button("Accept Best Quest", function()
        local best = bestQuest()
        if not best then
            notify("Quests", "no quest for your level", "bad")
            return
        end
        local ok, err = acceptQuest(best)
        State.status = ok and ("accepted " .. best.key) or tostring(err)
        notify("Quests", State.status, ok and "good" or "bad")
        refreshPanel()
    end)
    s1:Button("Warp Island + Accept", function()
        local best = bestQuest()
        if not best then
            notify("Quests", "no quest", "bad")
            return
        end
        local spawn = matchSpawn(best.location)
        if spawn then
            local ok = warpTo(spawn)
            notify("Travel", ok and ("warped " .. spawn) or "warp failed", ok and "good" or "bad")
            task.wait(1.0)
        else
            notify("Travel", "no spawn for " .. tostring(best.location), "bad")
        end
        local ok2, err = acceptQuest(best)
        State.status = ok2 and ("accepted " .. best.key) or tostring(err)
        notify("Quests", State.status, ok2 and "good" or "bad")
        refreshPanel()
    end)
    s1:Toggle("Auto Accept", State.autoAccept, function(v)
        State.autoAccept = v
        savePersist()
        notify("Auto Accept", v and "ON" or "OFF", v and "good" or "bad")
    end)
    s1:Slider("Interval", 125, 50, 400, "x10ms", function(v)
        State.acceptInterval = v / 100
    end)

    local s2 = tab:Section("Info")
    s2:Button("Refresh Status", function()
        refreshPanel()
        notify("Status", "refreshed", "good")
    end)
    if ToggleAutoQuest then
        s2:Button("Toggle Game AutoQuest", function()
            pcall(function() ToggleAutoQuest:FireServer() end)
            notify("AutoQuest", "toggled game remote", "good")
        end)
    end

    local s3 = tab:Section("Sea Rift Clear")
    s3:Label("Safe perch → aim spawn pad → Sea Rift")
    s3:Button("Pad Clear (test)", function()
        task.spawn(function()
            local ok, err, target, pad = seaRiftPadClear()
            if ok then
                notify("Sea Rift", "cleared aim · " .. tostring(target), "good")
            else
                notify("Sea Rift", tostring(err), "bad")
            end
            if pad then
                State.status = string.format("pad %d,%d,%d", pad.X, pad.Y, pad.Z)
            end
        end)
    end)
end

-- Travel
do
    local tab = win:Tab("Travel")
    local names = spawnNames()
    if #names == 0 then names = { "(none)" } end
    local selected = names[1]
    local s1 = tab:Section("Spawn Warp")
    s1:Dropdown("Island", names, selected, function(v) selected = v end)
    s1:Button("Set Spawn + Teleport Home", function()
        if selected == "(none)" then return end
        local ok, err = warpTo(selected)
        notify("Travel", ok and ("OK " .. selected) or tostring(err), ok and "good" or "bad")
    end)
    s1:Button("Teleport Home Only", function()
        local ok, err = teleportHomeOnly()
        notify("Travel", ok and "home" or tostring(err), ok and "good" or "bad")
    end)

    local s2 = tab:Section("Travel to Quest")
    s2:Label("Fast BV-noclip → nearest quest NPC")
    s2:Button("Go to Quest Target", function()
        local t = currentQuestTarget()
        notify("Travel", t and ("fly → " .. t) or "no kill quest", t and "good" or "bad")
        if not t then return end
        task.spawn(function()
            local ok, info = slowTweenToQuestTarget()
            notify("Travel", ok and ("arrived · " .. tostring(info)) or tostring(info), ok and "good" or "bad")
        end)
    end)
end

-- Farm
do
    local tab = win:Tab("Farm")
    local s1 = tab:Section("Auto Farm")
    s1:Label("BV fly + skill remotes (no 1st person)")
    s1:Toggle("Auto Farm", State.autoFarm, function(v)
        State.autoFarm = v
        savePersist()
        if not v then
            stopFarmNoclip()
            clearVirtualAim()
            State.status = "farm off"
        else
            State.status = "farm on"
            requestFarmRepath()
            pcall(installVirtualMouse)
            -- no active kill quest → accept best for your level (Holy Soldier @ ~1050)
            task.spawn(function()
                local ok, info = ensureBestQuest()
                State.status = ok and ("quest · " .. tostring(info)) or ("quest? · " .. tostring(info))
                requestFarmRepath()
                pcall(refreshPanel)
                notify("Quest", tostring(info), ok and "good" or "bad")
            end)
            UI.uiVisible = false
            pcall(function() UI:PlayUI("close") end)
        end
        notify("Farm", v and "ON" or "OFF", v and "good" or "bad")
    end)
    s1:Toggle("Skills on Target", true, function(v)
        State.farmSkills = v
    end)
    s1:Toggle("In-Game M1 (Activate)", true, function(v)
        State.farmM1 = v
        notify("Farm", v and "M1 · tool Activate (mouse free)" or "M1 off", v and "good" or "bad")
    end)
    s1:Toggle("OS Mouse Click (bad)", false, function(v)
        State.farmClick = v
        if v then
            notify("Farm", "OS click steals mouse / clicks outside Roblox", "bad")
        end
    end)
    s1:Toggle("Auto Accept Quest", State.autoAccept, function(v)
        State.autoAccept = v
        savePersist()
    end)
    s1:Toggle("Auto Buso (J)", State.autoBuso, function(v)
        State.autoBuso = v
        savePersist()
        if v then
            task.spawn(function()
                ensureAutoHaki(true)
            end)
        end
        notify("Haki", v and "Buso auto ON" or "Buso auto OFF", v and "good" or "bad")
    end)
    s1:Toggle("Auto Haki / Obs (K)", State.autoHaki, function(v)
        State.autoHaki = v
        savePersist()
        if v then
            task.spawn(function()
                ensureAutoHaki(true)
            end)
        end
        notify("Haki", v and "Obs Haki auto ON" or "Obs Haki auto OFF", v and "good" or "bad")
    end)
end

-- Specify (what to farm / which skills)
do
    local tab = win:Tab("Specify")
    local enemies = listEnemyNames()
    if not table.find(enemies, State.farmEnemy) then
        State.farmEnemy = enemies[1]
    end
    ensureSkillDefaults()
    local skills = equippedSkillNames()
    if #skills == 0 then skills = skillRemoteNames() end
    if #skills == 0 then skills = { "(no fruit skills)" } end
    if not table.find(skills, State.skillName) and skills[1] then
        State.skillName = skills[1]
    end

    local toolNames = inventoryToolNames()
    local m1Choices = { "Auto" }
    for _, n in ipairs(toolNames) do
        m1Choices[#m1Choices + 1] = n
    end
    if not table.find(m1Choices, State.m1Tool) then
        State.m1Tool = "Auto"
    end

    local s1 = tab:Section("Target")
    s1:Dropdown("Farm Mode", { "Quest Target", "Selected Enemy" }, State.farmMode, function(v)
        State.farmMode = v
        notify("Farm", "mode · " .. v, "good")
    end)
    s1:Dropdown("Enemy", enemies, State.farmEnemy, function(v)
        State.farmEnemy = v
    end)
    s1:Button("Refresh Enemy List", function()
        notify("Farm", "re-exec script to refresh dropdown", "good")
    end)

    local sWep = tab:Section("Weapon / Fruit")
    sWep:Label("Fruit: " .. tostring(currentFruitName() or "none"))
    sWep:Dropdown("M1 Tool", m1Choices, State.m1Tool, function(v)
        State.m1Tool = v
        notify("M1", v == "Auto" and ("auto · " .. tostring(currentFruitName() or "?")) or v, "good")
    end)
    sWep:Label("Auto = tool matching your equipped fruit name")

    local s2 = tab:Section("Skill Inventory")
    s2:Label("Tick skills to use while farming")
    s2:Button("Enable All Skills", function()
        for _, n in ipairs(equippedSkillNames()) do
            State.skillEnabled[n] = true
        end
        notify("Skills", "all enabled", "good")
    end)
    s2:Button("Disable All Skills", function()
        for _, n in ipairs(equippedSkillNames()) do
            State.skillEnabled[n] = false
        end
        notify("Skills", "all disabled", "bad")
    end)
    for _, skillName in ipairs(equippedSkillNames()) do
        local sn = skillName
        local on = State.skillEnabled[sn] ~= false
        s2:Toggle(sn, on, function(v)
            State.skillEnabled[sn] = v
        end)
    end
    s2:Slider("Skill CD", 8, 3, 50, "x100ms", function(v)
        State.farmSkillCd = v / 10
    end)
    s2:Slider("Melee Range", 9, 5, 20, "studs", function(v)
        State.farmMelee = v
    end)
    s2:Slider("Attack Range", 14, 8, 40, "studs", function(v)
        State.farmRange = v
    end)
    s2:Slider("Hover Height", 2, 0, 8, "studs", function(v)
        State.farmHeight = v
    end)
end

-- Stats
do
    local tab = win:Tab("Stats")
    local s1 = tab:Section("Fruit")
    s1:Label("Fires Stats_Event Fruit with free points")
    s1:Button("Dump 1 Point → Fruit", function()
        local ok, err = dumpFruit(1)
        notify("Stats", ok and "sent 1" or tostring(err), ok and "good" or "bad")
    end)
    s1:Button("Dump All → Fruit", function()
        local v = freeStatPoints()
        local n = v and math.floor(v.Value) or 0
        if n <= 0 then
            notify("Stats", "no free points found", "bad")
            return
        end
        local ok, err = dumpFruit(n)
        notify("Stats", ok and ("sent " .. n) or tostring(err), ok and "good" or "bad")
    end)
    s1:Toggle("Auto Fruit Stats", false, function(v)
        State.autoFruit = v
        notify("Auto Fruit", v and "ON" or "OFF", v and "good" or "bad")
    end)

    -- Auto skill lives here (manual skill cast UI removed)
    local skills = equippedSkillNames()
    if #skills == 0 then skills = skillRemoteNames() end
    if #skills == 0 then skills = { "Sea Rift" } end
    if not table.find(skills, State.skillName) then
        State.skillName = skills[1]
    end
    local s2 = tab:Section("Auto Skill")
    s2:Dropdown("Skill", skills, State.skillName, function(v) State.skillName = v end)
    s2:Toggle("Auto Skill", false, function(v)
        State.autoSkill = v
        notify("Auto Skill", v and ("ON · " .. State.skillName) or "OFF", v and "good" or "bad")
    end)
    s2:Slider("Cooldown", 30, 5, 100, "x100ms", function(v)
        State.skillCd = v / 10
    end)
end

-- Settings
do
    local tab = win:Tab("Settings")
    local s1 = tab:Section("UI")
    local kb = s1:Keybind("Menu Key", UI.menuKey or 0xA3, function(vk)
        if not UI:SetMenuKey(vk) then
            notify("Bind", "can't use mouse buttons", "bad")
            return
        end
        notify("Menu Key", UI:KeyName(vk), "good")
    end)
    kb.allowNil = false -- Esc cancels, does not wipe menu key

    s1:Toggle("Custom Cursor", false, function(v)
        UI.showCursor = v
        UI.hideSystemCursor = v
        if not v then
            pcall(function()
                UserInputService.MouseIconEnabled = true
            end)
        end
    end)
    s1:Toggle("Fancy UI", true, function(v)
        UI.fx = v
    end)
    s1:Toggle("Watermark", true, function(v)
        UI.showWatermark = v
    end)
    s1:Toggle("UI Sounds", true, function(v)
        UI.soundsEnabled = v
    end)

    local sVis = tab:Section("Readability")
    sVis:Dropdown("Font", UI.FONT_NAMES or { "UI", "System", "Plex", "Monospace" }, UI.fontName or "UI", function(v)
        if UI.SetFont then UI:SetFont(v) end
        notify("UI", "font · " .. tostring(v), "good")
    end)
    sVis:Slider("Text Scale", math.floor((UI.textScale or 1) * 100 + 0.5), 80, 160, "%", function(v)
        if UI.SetTextScale then UI:SetTextScale(v / 100) end
    end)
    sVis:Button("Auto Scale (monitor)", function()
        local sc = UI.AutoScaleFromViewport and UI:AutoScaleFromViewport() or 1
        notify("UI", string.format("scale %.0f%%", sc * 100), "good")
    end)

    local s2 = tab:Section("Session")
    s2:Label("Stops autos + removes Drawing UI")
    s2:Button("Unload / Uninject", function()
        State.autoAccept = false
        State.autoFruit = false
        State.autoSkill = false
        State.autoFarm = false
        stopFarmNoclip()
        clearVirtualAim()
        State.status = "unloaded"
        notify("T3ti", "unloading...", "bad")
        task.defer(function()
            pcall(function()
                if UI and UI.Destroy then
                    UI:Destroy()
                end
            end)
            _G.T3TI_UI = nil
            _G.SEIM_UI = nil
            print("[T3ti] unloaded")
        end)
    end)
end

--------------------------------------------------------------------
-- Panels
--------------------------------------------------------------------
local function fmtNum(n)
    n = tonumber(n) or 0
    local neg = n < 0
    n = math.abs(n)
    local s
    if n >= 1e9 then
        s = string.format("%.2fB", n / 1e9)
    elseif n >= 1e6 then
        s = string.format("%.2fM", n / 1e6)
    elseif n >= 1e4 then
        s = string.format("%.1fk", n / 1e3)
    else
        s = tostring(math.floor(n + 0.5))
    end
    return neg and ("-" .. s) or s
end

local function val(inst, fallback)
    if inst and inst:IsA("ValueBase") then
        return inst.Value
    end
    return fallback
end

local function currentFruit()
    local fp = PG:FindFirstChild("FruitPowers")
    if not fp then return "-" end
    for _, c in ipairs(fp:GetChildren()) do
        if c:IsA("Folder") or c:IsA("Frame") or c:IsA("ScreenGui") or c.ClassName == "Folder" then
            return c.Name
        end
        return c.Name
    end
    return "-"
end

local function staminaText()
    local char = LP.Character
    if char then
        local cur = char:FindFirstChild("CurrFly")
        local mx = char:FindFirstChild("MaxFly")
        if cur and mx then
            return tostring(math.floor(cur.Value)) .. "/" .. tostring(math.floor(mx.Value))
        end
    end
    return "-"
end

local function bountyValue()
    local ls = LP:FindFirstChild("leaderstats")
    local b = ls and (ls:FindFirstChild("Bounty/Respect") or ls:FindFirstChild("Bounty"))
    return b and b.Value or 0
end

local userName = LP.Name
local questPanel = UI:Panel({ title = "(" .. userName .. ") Quest", x = 20, y = 70, w = 260, visible = false })
local playerPanel = UI:Panel({ title = "(" .. userName .. ") Player", x = 20, y = 320, w = 260, visible = false })
local statsPanel = UI:Panel({ title = "(" .. userName .. ") Stats", x = 20, y = 560, w = 260, visible = false })

function refreshPanel()
    local lvl = LevelVal.Value
    local best = bestQuest(lvl)
    local nxt = nextUnlock(lvl)
    local xp = val(Exp:FindFirstChild("Experience"), 0)
    local points = val(Exp:FindFirstChild("Points"), 0)
    local combat = val(Exp:FindFirstChild("Combat"), 0)
    local defense = val(Exp:FindFirstChild("Defense"), 0)
    local fruitStat = val(Exp:FindFirstChild("Fruit"), 0)
    local swordStat = val(Exp:FindFirstChild("Sword"), 0)
    local cash = val(PD:FindFirstChild("Currency"), 0)
    local gems = val(PD:FindFirstChild("Gems"), 0)
    local sword = val(PD:FindFirstChild("Sword") and PD.Sword:FindFirstChild("CurrentSword"), "-")
    local style = val(PD:FindFirstChild("FightingStyle"), "-")
    local race = val(PD:FindFirstChild("Race"), "-")
    local fruit = currentFruit()
    local bestLabel = best and (best.key .. " · " .. tostring(best.display)) or "none"
    State.bestLabel = bestLabel

    questPanel:Set({
        { left = "Level", right = tostring(lvl), color = UI.Theme.text },
        { left = "Best Quest", right = best and best.key or "-", color = UI.Theme.good },
        { left = "NPC", right = best and best.display or "-", color = UI.Theme.label },
        { left = "Island", right = best and tostring(best.location or "?") or "-", color = UI.Theme.label },
        { left = "Target", right = best and tostring(best.target or "-") or "-", color = UI.Theme.textDim },
        { left = "Next", right = nxt and nxt.key or "-", color = UI.Theme.textDim },
        { left = "AutoAcc", right = State.autoAccept and "ON" or "OFF",
          color = State.autoAccept and UI.Theme.good or UI.Theme.bad },
        { left = "Farm", right = State.autoFarm and "ON" or "OFF",
          color = State.autoFarm and UI.Theme.good or UI.Theme.bad },
        { left = "Status", right = tostring(State.status):sub(1, 20), color = UI.Theme.accent },
    })
    questPanel.title = "(" .. userName .. ") Quest"
    if questPanel.titleT then questPanel.titleT.Text = questPanel.title end

    playerPanel:Set({
        { left = "Level", right = tostring(lvl), color = UI.Theme.text },
        { left = "EXP", right = fmtNum(xp), color = UI.Theme.label },
        { left = "Cash", right = fmtNum(cash), color = UI.Theme.good },
        { left = "Gems", right = fmtNum(gems), color = Color3.fromRGB(120, 200, 255) },
        { left = "Bounty", right = fmtNum(bountyValue()), color = UI.Theme.bad },
        { left = "Stamina", right = staminaText(), color = UI.Theme.accent },
        { left = "Sword", right = tostring(sword), color = UI.Theme.text },
        { left = "Fruit", right = tostring(fruit), color = UI.Theme.accent },
        { left = "Style", right = tostring(style), color = UI.Theme.label },
        { left = "Race", right = tostring(race), color = UI.Theme.label },
    })
    playerPanel.title = "(" .. userName .. ") Player"
    if playerPanel.titleT then playerPanel.titleT.Text = playerPanel.title end

    statsPanel:Set({
        { left = "Free Pts", right = tostring(points), color = points > 0 and UI.Theme.good or UI.Theme.textDim },
        { left = "Combat", right = tostring(combat), color = UI.Theme.text },
        { left = "Defense", right = tostring(defense), color = UI.Theme.text },
        { left = "Fruit", right = tostring(fruitStat), color = UI.Theme.accent },
        { left = "Sword", right = tostring(swordStat), color = UI.Theme.label },
        { left = "Refund", right = tostring(val(PD:FindFirstChild("RefundPoints"), 0)), color = UI.Theme.textDim },
    })
    statsPanel.title = "(" .. userName .. ") Stats"
    if statsPanel.titleT then statsPanel.titleT.Text = statsPanel.title end
end

refreshPanel()

--------------------------------------------------------------------
-- Loops
--------------------------------------------------------------------
-- Combat stand BESIDE the NPC (same height). Stacking on their head = 0 damage.
local function flatDist(a, b)
    local d = a - b
    return Vector3.new(d.X, 0, d.Z).Magnitude
end

-- Locked side vector so the stand doesn't orbit as you / NPC micro-move
local _farmLockNpc = nil
local _farmLockSide = nil -- Unit Vector3 XZ

local function clearFarmLock()
    _farmLockNpc = nil
    _farmLockSide = nil
end

local function farmStandPos(npcPos, npc, fromPos)
    local side = tonumber(State.farmMelee) or 6
    local h = math.clamp(tonumber(State.farmHeight) or 1.5, 0, 2.5)

    if npc and npc == _farmLockNpc and _farmLockSide then
        return npcPos + _farmLockSide * side + Vector3.new(0, h, 0)
    end

    local from = fromPos
    if typeof(from) ~= "Vector3" then
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        from = hrp and hrp.Position or (npcPos + Vector3.new(side, 0, 0))
    end
    local flat = Vector3.new(from.X - npcPos.X, 0, from.Z - npcPos.Z)
    if flat.Magnitude < 0.15 then
        flat = Vector3.new(1, 0, 0)
    end
    _farmLockNpc = npc
    _farmLockSide = flat.Unit
    return npcPos + _farmLockSide * side + Vector3.new(0, h, 0)
end

local function resolveFarmTarget(targetName, hrp)
    -- Stick to the same NPC until dead / too far — but ONLY if it still matches the quest
    if _farmLockNpc and _farmLockNpc.Parent then
        local keys = questTargetKeys(targetName)
        local hum = _farmLockNpc:FindFirstChildOfClass("Humanoid")
        local nameOk = npcNameMatches(_farmLockNpc.Name, keys)
        if hum and hum.Health > 0 and nameOk then
            local ok, piv = pcall(function()
                return _farmLockNpc:GetPivot().Position
            end)
            if ok and piv and (piv - hrp.Position).Magnitude < 90 then
                return _farmLockNpc, piv, (piv - hrp.Position).Magnitude
            end
        end
    end
    clearFarmLock()
    return findNearestEnemyModel(targetName)
end

-- Auto Farm: fly in once → HOLD stiff beside target → M1
task.spawn(function()
    local lastFly = 0
    local lastPanel = 0
    while UI.alive do
        local okIter, errIter = pcall(function()
            getgenv().T3TI_FarmBeat = tick()
            if State.autoFarm then
                ensureAutoHaki()
                local targetName = farmTargetName()
                local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if targetName and hrp then
                    local npc, pos, dist = resolveFarmTarget(targetName, hrp)
                    if npc and pos then
                        local stand = farmStandPos(pos, npc, hrp.Position)
                        local melee = State.farmMelee or 6
                        local fdist = flatDist(hrp.Position, pos)
                        local dy = hrp.Position.Y - pos.Y
                        local standDist = (hrp.Position - stand).Magnitude

                        local needFly = _forceFarmRepath
                            or standDist > 16
                            or fdist > (melee + 8)
                            or math.abs(dy) > 12
                        if needFly and tick() - lastFly > 0.8 then
                            lastFly = tick()
                            _forceFarmRepath = false
                            State.status = string.format("close · flat%.0f · dy%.0f", fdist, dy)
                            local ok, _, cache = bvFlyTo(stand, {
                                speed = 700,
                                arrive = math.max(3.5, melee * 0.45),
                                keepNoclip = true,
                                cancel = function()
                                    return not State.autoFarm or not UI.alive
                                end,
                            })
                            if cache then _farmNoclipCache = cache end
                        end

                        if State.autoFarm then
                            npc, pos, dist = resolveFarmTarget(targetName, hrp)
                            if npc and pos then
                                stand = farmStandPos(pos, npc, hrp.Position)
                                farmHoldAt(stand, pos)
                                fdist = flatDist(hrp.Position, pos)

                                local aimPos = pos + Vector3.new(0, 2, 0)
                                setVirtualAim(aimPos, npc)
                                faceWorld(pos)

                                local now = tick()
                                local yOk = math.abs(hrp.Position.Y - pos.Y) <= 8
                                if State.farmM1 and fdist <= (melee + 2) and yOk and now - State.lastFarmM1 >= 0.09 then
                                    State.lastFarmM1 = now
                                    doFarmM1()
                                end
                                if State.farmClick and now - State.lastFarmClick >= 0.12 then
                                    State.lastFarmClick = now
                                    farmClick()
                                end
                                if State.farmSkills and now - State.lastFarmSkill >= (State.farmSkillCd or 1.2) then
                                    State.lastFarmSkill = now
                                    castFarmSkills(aimPos, npc)
                                end

                                local hum = npc:FindFirstChildOfClass("Humanoid")
                                local hp = hum and math.floor(hum.Health) or 0
                                local fruit = currentFruitName() or "?"
                                local tool = LP.Character and LP.Character:FindFirstChildOfClass("Tool")
                                State.status = string.format(
                                    "%s · %s · %dhp · flat%.0f · %s",
                                    fruit,
                                    targetName,
                                    hp,
                                    fdist or 0,
                                    tool and tool.Name or "no tool"
                                )
                            else
                                clearFarmLock()
                            end
                        end
                    else
                        clearFarmLock()
                        -- No live NPC: fly to Observation pad / hold. Never block on TeleportToHome.
                        clearVirtualAim()
                        local waitStand, err, _, kind, dist0 = questKillStand(targetName)
                        if waitStand then
                            local wf = flatDist(hrp.Position, waitStand)
                            local dy = hrp.Position.Y - waitStand.Y
                            if _forceFarmRepath or wf > 16 or math.abs(dy) > 20 then
                                if tick() - lastFly > 0.9 then
                                    lastFly = tick()
                                    _forceFarmRepath = false
                                    State.status = string.format(
                                        "goto · %s · %.0fd",
                                        tostring(kind or "pad"),
                                        dist0 or 0
                                    )
                                    local ok, _, cache = bvFlyTo(waitStand, {
                                        speed = 700,
                                        arrive = 12,
                                        keepNoclip = true,
                                        cancel = function()
                                            return not State.autoFarm or not UI.alive
                                        end,
                                    })
                                    if cache then _farmNoclipCache = cache end
                                    if not ok then
                                        State.status = "travel fail · " .. tostring(targetName)
                                    end
                                else
                                    State.status = "seek · " .. tostring(targetName)
                                end
                            else
                                farmHoldAt(waitStand, waitStand)
                                State.status = string.format(
                                    "wait · %s · %s",
                                    tostring(targetName),
                                    tostring(kind or "pad")
                                )
                            end
                        else
                            stopFarmHold()
                            State.status = "no pad · " .. tostring(targetName)
                        end
                    end
                elseif not targetName then
                    clearFarmLock()
                    stopFarmHold()
                    clearVirtualAim()
                    State.status = "no farm target"
                else
                    clearFarmLock()
                    stopFarmHold()
                    clearVirtualAim()
                    State.status = "no character"
                end
                if tick() - lastPanel > 1.0 then
                    lastPanel = tick()
                    pcall(refreshPanel)
                end
                task.wait(0.08)
            else
                clearFarmLock()
                stopFarmHold()
                if Aim.on then clearVirtualAim() end
                ensureAutoHaki()
                task.wait(0.25)
            end
        end)
        if not okIter then
            State.status = "farm err · " .. tostring(errIter):sub(1, 40)
            getgenv().T3TI_FarmErr = tostring(errIter)
            task.wait(0.5)
        end
    end
    clearVirtualAim()
    stopFarmNoclip()
    clearFarmLock()
end)

task.spawn(function()
    while UI.alive do
        local now = tick()
        if State.autoAccept and now - State.lastAccept >= State.acceptInterval then
            State.lastAccept = now
            local ok, info = ensureBestQuest()
            if ok and type(info) == "string" then
                -- only refresh status when we actually changed something meaningful
                if State.status == "ready" or tostring(State.status):find("quest") or tostring(State.status):find("auto") then
                    State.status = "quest · " .. info
                end
            elseif type(info) == "string" and info ~= "" and not tostring(info):lower():find("already") then
                -- keep quiet on routine failures
            end
        end
        if State.autoFruit and now - State.lastFruit >= 2 then
            State.lastFruit = now
            local v = freeStatPoints()
            if v and v.Value > 0 then
                dumpFruit(math.min(5, math.floor(v.Value)))
            end
        end
        if State.autoSkill and not State.autoFarm and now - State.lastSkill >= State.skillCd then
            State.lastSkill = now
            castSkill(State.skillName)
        end
        task.wait(0.2)
    end
end)

task.spawn(function()
    while UI.alive do
        if UI.uiVisible and not UI._booting then
            refreshPanel()
        end
        task.wait(1.5)
    end
end)

-- Boot intro once, then reveal UI
UI.uiVisible = false
UI.showWatermark = false
for _, p in ipairs(UI.panels) do
    p.visible = false
    p.want = false
end

local function revealUI()
    UI.uiVisible = true
    UI.showWatermark = true
    for _, w in ipairs(UI.windows) do
        w.visible = true
    end
    for _, p in ipairs(UI.panels) do
        p.visible = true
        p.want = true
    end
    refreshPanel()
    UI:PlayUI("open")
    if State.autoFarm then
        requestFarmRepath()
        notify("T3ti", "Auto Farm resumed — RCtrl menu", "good")
    else
        notify("T3ti", "Haze helper ready — enable Auto Farm to move", "good")
    end
    print("[T3ti] Haze Seas helper loaded · autoFarm=" .. tostring(State.autoFarm))
end

-- MCP / executor helpers for live tests
getgenv().T3TI_SetFarm = function(on)
    State.autoFarm = on and true or false
    savePersist()
    if State.autoFarm then
        requestFarmRepath()
        task.spawn(function()
            ensureBestQuest()
            requestFarmRepath()
        end)
    else
        stopFarmNoclip()
        clearVirtualAim()
    end
    return State.autoFarm
end
getgenv().T3TI_Status = function()
    return {
        autoFarm = State.autoFarm,
        autoAccept = State.autoAccept,
        status = State.status,
        target = farmTargetName(),
        quest = currentQuestTarget(),
    }
end

if UI.PlayBootIntro and not getgenv().T3TI_NO_INTRO then
    UI:PlayBootIntro(revealUI)
else
    revealUI()
end
