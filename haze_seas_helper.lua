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
UI.showCursor = true
UI.hideSystemCursor = true
UI.watermark = game.Players.LocalPlayer.Name
UI.showWatermark = true
pcall(function() UI:SetFont("UI") end)

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

local State = {
    autoAccept = false,
    autoFruit = false,
    autoSkill = false,
    skillName = "Sea Rift",
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
    farmClick = false, -- physical mouse1click — keep off so you can use your mouse
    farmMode = "Quest Target", -- or "Selected Enemy"
    farmEnemy = "Holy Soldier",
    farmRange = 25,
    farmSkillCd = 1.2,
    lastFarmSkill = 0,
    lastFarmClick = 0,
    farmHeight = 8,
    useAllSkills = false,
}

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
    return fp:FindFirstChild("Tremor") or fp:GetChildren()[1]
end

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

local function castSkill(name)
    name = name or State.skillName
    local fruit = fruitFolder()
    local ev = fruit and fruit:FindFirstChild("Events")
    local remote = ev and ev:FindFirstChild(name)
    if remote and remote:IsA("RemoteEvent") then
        local ok, err = pcall(function() remote:FireServer() end)
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

-- Current quest target from QuestGui ("Kill 4 Marine Grunts" -> "Marine Grunt")
local function currentQuestTarget()
    local qg = QuestGui
    if not qg then return nil end
    for _, d in ipairs(qg:GetDescendants()) do
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            local t = d.Text or ""
            local m = t:match("[Kk]ill%s+%d+%s+(.+)") or t:match("[Dd]efeat%s+%d+%s+(.+)")
            if m then
                m = m:gsub("%s+$", "")
                -- strip trailing plural s when it's "... Captains" / "... Grunts"
                if m:sub(-1) == "s" and not m:lower():find("boss") then
                    local sing = m:sub(1, -2)
                    if #sing > 3 then m = sing end
                end
                return m
            end
        end
    end
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

-- Name aliases when quest text ≠ live NPC name (e.g. Holy vs Divine)
local QUEST_NPC_ALIASES = {
    ["holy soldier"] = { "holy soldier", "divine soldier" },
    ["divine soldier"] = { "holy soldier", "divine soldier" },
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
        if n == k or n:find(k, 1, true) or k:find(n, 1, true) then
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
  Prefer nearest LIVE npc (Holy quest often has Divine Soldier models nearby).
  Pad fallback uses NEAREST pad to you across aliases — never average / never
  the far upper Holy pads when Divine pads are next to you (that rubberbands).
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
        -- stand a bit above / offset so we don't clip into the NPC
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
        return bestPad.pos + Vector3.new(0, 6, 0), #pads, targetName, "pad:" .. bestPad.name, bestPadDist
    end

    return nil, "no NPCs/pads for " .. targetName
end

--[[
  Fast noclip BV fly — matches working Haze Seas tweens we probed:
  - CanCollide=false on ALL character parts (through walls)
  - BodyVelocity + BodyGyro on HRP (NOT Anchored, NOT CFrame teleport)
]]
local _questFlyToken = 0
local function setNoclip(char, on, cache)
    cache = cache or {}
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            if on then
                if cache[p] == nil then
                    cache[p] = p.CanCollide
                end
                p.CanCollide = false
            elseif cache[p] ~= nil then
                p.CanCollide = cache[p]
            end
        end
    end
    return cache
end

local function bvFlyTo(goal, opts)
    opts = opts or {}
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or typeof(goal) ~= "Vector3" then
        return false, "no character/goal"
    end

    _questFlyToken += 1
    local token = _questFlyToken
    local speed = opts.speed or 900
    local arrive = opts.arrive or 12
    local keepNoclip = opts.keepNoclip == true

    for _, n in ipairs({ "T3tiQuestFly", "T3tiQuestGyro" }) do
        local old = hrp:FindFirstChild(n)
        if old then pcall(function() old:Destroy() end) end
    end

    local collCache = setNoclip(char, true, {})

    local bv = Instance.new("BodyVelocity")
    bv.Name = "T3tiQuestFly"
    bv.MaxForce = Vector3.new(1, 1, 1) * 2e10
    bv.P = 20000
    bv.Velocity = Vector3.zero
    bv.Parent = hrp

    local bg = Instance.new("BodyGyro")
    bg.Name = "T3tiQuestGyro"
    bg.MaxTorque = Vector3.new(1, 1, 1) * 2e10
    bg.P = 10000
    bg.D = 500
    bg.CFrame = hrp.CFrame
    bg.Parent = hrp

    local dist0 = (goal - hrp.Position).Magnitude
    local t0 = tick()
    local maxT = math.clamp(dist0 / speed + 4, 3, 25)
    local okArrive = false

    while token == _questFlyToken and hrp.Parent and UI.alive and (tick() - t0) < maxT do
        if opts.cancel and opts.cancel() then break end
        local pos = hrp.Position
        local delta = goal - pos
        local dist = delta.Magnitude
        if dist <= arrive then
            okArrive = true
            break
        end
        local v = speed
        if dist < 60 then
            v = math.max(80, speed * (dist / 60))
        end
        bv.Velocity = delta.Unit * v
        bg.CFrame = CFrame.lookAt(pos, Vector3.new(goal.X, pos.Y, goal.Z))
        RunService.Heartbeat:Wait()
    end

    pcall(function()
        bv.Velocity = Vector3.zero
        bv:Destroy()
        bg:Destroy()
    end)
    if not keepNoclip then
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
    return currentQuestTarget() or State.farmEnemy
end

local function findNearestEnemyModel(targetName)
    targetName = targetName or farmTargetName()
    if not targetName then return nil end
    local keys = questTargetKeys(targetName)
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    local from = hrp and hrp.Position
    if not from then return nil end

    local best, bestDist, bestPos = nil, math.huge, nil
    local function consider(m)
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
    end

    local zones = workspace:FindFirstChild("NPC Zones")
    if zones then
        for _, zone in ipairs(zones:GetChildren()) do
            local npcs = zone:FindFirstChild("NPCS") or zone:FindFirstChild("NPCs")
            if npcs then
                for _, m in ipairs(npcs:GetChildren()) do
                    consider(m)
                end
            end
        end
    end
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
    -- Physical OS click — avoid while you want free mouse control
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
    if State.useAllSkills then
        local names = skillRemoteNames()
        for _, n in ipairs(names) do
            castSkill(n)
            task.wait(0.05)
        end
    else
        castSkill(State.skillName)
    end
    -- leave Aim.on so brief post-cast scripts still see the hit; cleared when farm off
end

local _farmNoclipCache = nil
local function stopFarmNoclip()
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
    s1:Toggle("Auto Accept", false, function(v)
        State.autoAccept = v
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
    s1:Toggle("Auto Farm", false, function(v)
        State.autoFarm = v
        if not v then
            stopFarmNoclip()
            clearVirtualAim()
            State.status = "farm off"
        else
            State.status = "farm on"
            pcall(installVirtualMouse)
            -- close menu so accidental M1 can't toggle widgets
            UI.uiVisible = false
            pcall(function() UI:PlayUI("close") end)
        end
        notify("Farm", v and "ON (virtual aim)" or "OFF", v and "good" or "bad")
    end)
    s1:Toggle("Skills on Target", true, function(v)
        State.farmSkills = v
    end)
    s1:Toggle("Physical M1 Click", false, function(v)
        State.farmClick = v
        if v then
            notify("Farm", "M1 uses real cursor — leave OFF to free mouse", "bad")
        end
    end)
    s1:Toggle("Auto Accept Quest", true, function(v)
        State.autoAccept = v
    end)
end

-- Specify (what to farm / which skills)
do
    local tab = win:Tab("Specify")
    local enemies = listEnemyNames()
    if not table.find(enemies, State.farmEnemy) then
        State.farmEnemy = enemies[1]
    end
    local skills = skillRemoteNames()
    if #skills == 0 then skills = { "Sea Rift" } end
    if not table.find(skills, State.skillName) then
        State.skillName = skills[1]
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

    local s2 = tab:Section("Skills")
    s2:Dropdown("Skill", skills, State.skillName, function(v)
        State.skillName = v
    end)
    s2:Toggle("Use All Fruit Skills", false, function(v)
        State.useAllSkills = v
    end)
    s2:Slider("Skill CD", 12, 3, 50, "x100ms", function(v)
        State.farmSkillCd = v / 10
    end)
    s2:Slider("Attack Range", 25, 10, 80, "studs", function(v)
        State.farmRange = v
    end)
    s2:Slider("Hover Height", 8, 0, 40, "studs", function(v)
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
    local skills = skillRemoteNames()
    if #skills == 0 then skills = { "Sea Rift" } end
    State.skillName = skills[1]
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

    s1:Toggle("Custom Cursor", true, function(v)
        UI.showCursor = v
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
-- Auto Farm: BV to enemy, virtual Mouse.Hit aim (no OS cursor move), FireServer skills.
-- Leave Physical M1 OFF so you can freely use your mouse while it farms.
task.spawn(function()
    local lastFly = 0
    while UI.alive do
        if State.autoFarm then
            local targetName = farmTargetName()
            if targetName then
                local npc, pos, dist = findNearestEnemyModel(targetName)
                local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if npc and pos and hrp then
                    local hover = pos + Vector3.new(0, State.farmHeight or 8, 0)
                    local range = State.farmRange or 25

                    if dist > range + 8 and tick() - lastFly > 0.35 then
                        lastFly = tick()
                        State.status = "fly · " .. tostring(targetName)
                        local ok, _, cache = bvFlyTo(hover, {
                            speed = 900,
                            arrive = math.max(8, range * 0.45),
                            keepNoclip = true,
                            cancel = function()
                                return not State.autoFarm or not UI.alive
                            end,
                        })
                        if cache then _farmNoclipCache = cache end
                    elseif not _farmNoclipCache and LP.Character then
                        _farmNoclipCache = setNoclip(LP.Character, true, {})
                    end

                    if State.autoFarm then
                        npc, pos, dist = findNearestEnemyModel(targetName)
                        if npc and pos then
                            local aimPos = pos + Vector3.new(0, 2, 0)
                            -- keep virtual aim fresh for skill scripts (never moves OS mouse)
                            setVirtualAim(aimPos, npc)

                            local now = tick()
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
                            State.status = string.format("%s · %dhp · %.0fd", targetName, hp, dist or 0)
                        else
                            clearVirtualAim()
                            State.status = "no " .. tostring(targetName)
                        end
                    end
                elseif not targetName then
                    clearVirtualAim()
                    State.status = "no farm target"
                else
                    clearVirtualAim()
                    State.status = "no " .. tostring(targetName)
                end
            else
                clearVirtualAim()
                State.status = "no farm target"
            end
            task.wait(0.08)
        else
            if Aim.on then clearVirtualAim() end
            task.wait(0.25)
        end
    end
    clearVirtualAim()
    stopFarmNoclip()
end)

task.spawn(function()
    while UI.alive do
        local now = tick()
        if State.autoAccept and now - State.lastAccept >= State.acceptInterval then
            State.lastAccept = now
            local best = bestQuest()
            if best then
                local ok, err = acceptQuest(best)
                if ok then
                    State.status = "auto " .. best.key
                    refreshPanel()
                elseif type(err) == "string" and err ~= "" and not tostring(err):lower():find("already") then
                    State.status = tostring(err):sub(1, 40)
                end
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
    notify("T3ti", "Haze helper ready — RCtrl menu", "good")
    print("[T3ti] Haze Seas helper loaded")
end

if UI.PlayBootIntro and not getgenv().T3TI_NO_INTRO then
    UI:PlayBootIntro(revealUI)
else
    revealUI()
end
