--[[
    T3ti UI — Drawing API menu framework
    Standalone: no ESP / aimbot / game logic.

    Usage:
        local UI = loadstring(readfile("t3ti_ui.lua"))()  -- or seim_ui.lua
        local win = UI:Window({ title = "Demo", x = 100, y = 100, w = 296 })
        local tab = win:Tab("Main")
        local sec = tab:Section("Stuff")
        sec:Toggle("Example", false, function(v) print(v) end)
        -- UI loop is started automatically
]]

for _, key in ipairs({ "T3TI_UI", "SEIM_UI" }) do
    local old = _G[key]
    if old and old.Destroy then
        pcall(function() old:Destroy() end)
    end
    _G[key] = nil
end

local S = {
    alive = true,
    drawings = {},
    connections = {},
    windows = {},
    panels = {},
    widgets = {},
    widgetOrder = {},
    fx = true,
    neon = false,
    dimOn = true,
    dimAmt = 0.45,
    dimAnim = 0,
    uiText = true,
    textScale = 1,
    fontName = "UI",
    showCursor = true,
    rainbow = false,
    rainbowSpeed = 40,
    watermark = "t3ti",
    showWatermark = true,
    soundsEnabled = true,
}
_G.T3TI_UI = S
_G.SEIM_UI = S -- compat alias

--------------------------------------------------------------------
-- Keys / helpers
--------------------------------------------------------------------
S.VK = {
    [0x01] = "M1", [0x02] = "M2", [0x04] = "M3", [0x05] = "M4", [0x06] = "M5",
    [0x08] = "Bksp", [0x09] = "Tab", [0x0D] = "Enter", [0x1B] = "Esc", [0x20] = "Space",
    [0x2E] = "Del", [0x2D] = "Ins", [0x24] = "Home", [0x23] = "End",
    [0x21] = "PgUp", [0x22] = "PgDn", [0x14] = "Caps",
    [0xA0] = "LShift", [0xA1] = "RShift", [0xA2] = "LCtrl", [0xA3] = "RCtrl",
    [0xA4] = "LAlt", [0xA5] = "RAlt",
    [0x25] = "Left", [0x26] = "Up", [0x27] = "Right", [0x28] = "Down",
    [0x30] = "0", [0x31] = "1", [0x32] = "2", [0x33] = "3", [0x34] = "4",
    [0x35] = "5", [0x36] = "6", [0x37] = "7", [0x38] = "8", [0x39] = "9",
    [0x41] = "A", [0x42] = "B", [0x43] = "C", [0x44] = "D", [0x45] = "E", [0x46] = "F",
    [0x47] = "G", [0x48] = "H", [0x49] = "I", [0x4A] = "J", [0x4B] = "K", [0x4C] = "L",
    [0x4D] = "M", [0x4E] = "N", [0x4F] = "O", [0x50] = "P", [0x51] = "Q", [0x52] = "R",
    [0x53] = "S", [0x54] = "T", [0x55] = "U", [0x56] = "V", [0x57] = "W", [0x58] = "X",
    [0x59] = "Y", [0x5A] = "Z",
    [0x70] = "F1", [0x71] = "F2", [0x72] = "F3", [0x73] = "F4", [0x74] = "F5", [0x75] = "F6",
    [0x76] = "F7", [0x77] = "F8", [0x78] = "F9", [0x79] = "F10", [0x7A] = "F11", [0x7B] = "F12",
}

function S:Fit(str, px, size)
    str = tostring(str or "")
    local perChar = (size or 11) * 0.58
    local maxChars = math.floor(px / perChar)
    if maxChars < 3 then maxChars = 3 end
    if #str <= maxChars then return str end
    return str:sub(1, maxChars - 2) .. ".."
end

function S:CenterY(boxY, boxH, fontSize)
    local h = (fontSize or 10) * (self.textScale or 1)
    return boxY + (boxH - h) * 0.5
end

function S:KeyName(vk)
    if not vk then return "None" end
    return self.VK[vk] or ("VK" .. tostring(vk))
end

-- Mouse buttons / XButtons — never allow as menu or keybind
S.MOUSE_VKS = {
    [0x01] = true, -- LMB
    [0x02] = true, -- RMB
    [0x04] = true, -- MMB
    [0x05] = true, -- X1
    [0x06] = true, -- X2
}

function S:IsMouseVk(vk)
    return vk ~= nil and self.MOUSE_VKS[vk] == true
end

function S:IsValidBind(vk)
    if vk == nil then return true end -- None / cleared
    if self:IsMouseVk(vk) then return false end
    return self.VK[vk] ~= nil or self.VK_TO_KEYCODE[vk] ~= nil
end

function S:SetMenuKey(vk)
    if not self:IsValidBind(vk) or vk == nil then
        return false
    end
    self.menuKey = vk
    return true
end

-- Win32 VK -> Roblox KeyCode
-- Potassium/Volt Input Library has NO iskeypressed — use UserInputService.
S.VK_TO_KEYCODE = {}
do
    local function map(vk, name)
        local ok, kc = pcall(function() return Enum.KeyCode[name] end)
        if ok and typeof(kc) == "EnumItem" then
            S.VK_TO_KEYCODE[vk] = kc
        end
    end
    map(0x08, "Backspace"); map(0x09, "Tab")
    map(0x0D, "Return"); map(0x1B, "Escape")
    map(0x20, "Space"); map(0x2E, "Delete")
    map(0x2D, "Insert"); map(0x24, "Home")
    map(0x23, "End"); map(0x21, "PageUp")
    map(0x22, "PageDown"); map(0x14, "CapsLock")
    map(0xA0, "LeftShift"); map(0xA1, "RightShift")
    map(0xA2, "LeftControl"); map(0xA3, "RightControl")
    map(0xA4, "LeftAlt"); map(0xA5, "RightAlt")
    map(0x25, "Left"); map(0x26, "Up")
    map(0x27, "Right"); map(0x28, "Down")
    local digits = { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
    for i = 0, 9 do map(0x30 + i, digits[i + 1]) end
    for i = 0, 25 do map(0x41 + i, string.char(65 + i)) end
    for i = 1, 12 do map(0x6F + i, "F" .. i) end
end

function S:KeyHeld(vk)
    if not vk then return false end
    local UIS = game:GetService("UserInputService")
    local r = false
    if vk == 0x01 then
        pcall(function() r = UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) end)
    elseif vk == 0x02 then
        pcall(function() r = UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) end)
    else
        -- optional UNC helpers if present; Potassium docs do not provide these
        if type(iskeypressed) == "function" then
            pcall(function() r = iskeypressed(vk) end)
        end
        if not r then
            local kc = self.VK_TO_KEYCODE[vk]
            if kc then
                pcall(function() r = UIS:IsKeyDown(kc) end)
            end
        end
    end
    return r and true or false
end

function S:Reg(key, wd)
    if self.widgets[key] then
        key = key .. "#" .. tostring(#self.widgetOrder)
    end
    wd._key = key
    self.widgets[key] = wd
    self.widgetOrder[#self.widgetOrder + 1] = key
    return wd
end

function S:Track(d)
    self.drawings[#self.drawings + 1] = d
    return d
end

function S:Connect(sig, fn)
    local ok, c = pcall(function() return sig:Connect(fn) end)
    if ok and c then
        self.connections[#self.connections + 1] = c
    end
    return c
end

function S:Destroy()
    self.alive = false
    pcall(function()
        if self._menuUnlocked and UserInputService then
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            UserInputService.MouseIconEnabled = true
        end
        self._menuUnlocked = false
        self._prevMouseBehavior = nil
    end)
    pcall(function()
        if self.hideSystemCursor and UserInputService then
            UserInputService.MouseIconEnabled = true
        end
    end)
    for _, c in ipairs(self.connections) do
        pcall(function() c:Disconnect() end)
    end
    for _, d in ipairs(self.drawings) do
        pcall(function() d:Remove() end)
    end
    self.connections, self.drawings, self.windows, self.panels = {}, {}, {}, {}
    self.widgets, self.widgetOrder = {}, {}
    pcall(function()
        if self._soundFolder then self._soundFolder:Destroy() end
    end)
    self._soundFolder, self._soundPool = nil, nil
    if _G.T3TI_UI == self then _G.T3TI_UI = nil end
    if _G.SEIM_UI == self then _G.SEIM_UI = nil end
end

--------------------------------------------------------------------
-- Services / math
--------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")
local LocalPlayer = Players.LocalPlayer
local Mouse = nil
pcall(function() Mouse = LocalPlayer:GetMouse() end)

local floor, abs = math.floor, math.abs
local clamp, maxf, minf = math.clamp, math.max, math.min

--------------------------------------------------------------------
-- UI sounds (click / toggle / open / close)
--------------------------------------------------------------------
S.SOUNDS = {
    click  = "rbxassetid://6895079853",
    toggle = "rbxassetid://9113889752",
    tab    = "rbxassetid://6026984224",
    hover  = "rbxassetid://10066991788",
    open   = "rbxassetid://6042053626",
    close  = "rbxassetid://6042053626",
    use    = "rbxassetid://6895079853",
    notify = "rbxassetid://6026984224",
}
S._soundPool = {}
S._lastSoundAt = {}

local function ensureSoundFolder()
    if S._soundFolder and S._soundFolder.Parent then return S._soundFolder end
    local folder = Instance.new("Folder")
    folder.Name = "T3tiUISounds"
    folder.Parent = SoundService
    S._soundFolder = folder
    return folder
end

function S:PlayUI(kind, vol)
    if self.soundsEnabled == false then return end
    kind = kind or "click"
    local id = self.SOUNDS[kind] or self.SOUNDS.click
    if not id then return end
    local now = tick()
    local last = self._lastSoundAt[kind] or 0
    if now - last < 0.04 then return end -- debounce spam
    self._lastSoundAt[kind] = now
    pcall(function()
        local folder = ensureSoundFolder()
        local snd = Instance.new("Sound")
        snd.Name = "T3ti_" .. kind
        snd.SoundId = id
        snd.Volume = vol or (kind == "hover" and 0.15 or 0.35)
        snd.PlaybackSpeed = kind == "toggle" and 1.05 or (kind == "open" and 1.1 or 1)
        snd.Parent = folder
        snd:Play()
        task.delay(2, function()
            pcall(function() snd:Destroy() end)
        end)
    end)
end

--------------------------------------------------------------------
-- Theme
--------------------------------------------------------------------
local T = {
    bg = Color3.fromRGB(17, 16, 19),
    bgAlpha = 0.95,
    header = Color3.fromRGB(23, 22, 26),
    border = Color3.fromRGB(48, 45, 53),
    accent = Color3.fromRGB(255, 110, 190),
    accentDim = Color3.fromRGB(150, 60, 115),
    text = Color3.fromRGB(226, 224, 230),
    label = Color3.fromRGB(178, 175, 186),
    textDim = Color3.fromRGB(124, 121, 132),
    section = Color3.fromRGB(168, 120, 150),
    trackOff = Color3.fromRGB(44, 42, 49),
    knob = Color3.fromRGB(240, 238, 244),
    knobOff = Color3.fromRGB(120, 117, 127),
    rowHover = Color3.fromRGB(31, 29, 35),
    valueBox = Color3.fromRGB(27, 26, 31),
    good = Color3.fromRGB(120, 210, 145),
    bad = Color3.fromRGB(240, 100, 105),
    rowH = 36,
    pad = 18,
    corner = 8,
}
S.Theme = T
S._baseProp = { rowH = 36, pad = 18 }

S.FONT_NAMES = { "UI", "System", "Plex", "Monospace" }
do
    local F = Drawing.Fonts
    S.FONTS = {
        UI = (F and (F.UI or F.System or F.Monospace)) or nil,
        System = (F and (F.System or F.UI or F.Monospace)) or nil,
        Plex = (F and (F.Plex or F.UI or F.Monospace)) or nil,
        Monospace = (F and (F.Monospace or F.UI or F.System)) or nil,
    }
    S.font = S.FONTS.UI
end

local COLOR_PALETTE = {
    Blue = Color3.fromRGB(80, 220, 255),
    Red = Color3.fromRGB(255, 80, 80),
    Gold = Color3.fromRGB(255, 200, 0),
    Green = Color3.fromRGB(80, 230, 130),
    Purple = Color3.fromRGB(190, 100, 255),
    Orange = Color3.fromRGB(255, 150, 60),
    Pink = Color3.fromRGB(255, 110, 180),
    Cyan = Color3.fromRGB(70, 230, 230),
    White = Color3.fromRGB(245, 245, 245),
}
S.COLOR_PALETTE = COLOR_PALETTE
S.COLOR_NAMES = { "Blue", "Red", "Gold", "Green", "Purple", "Orange", "Pink", "Cyan", "White" }

local function prop(d, k, v)
    pcall(function() d[k] = v end)
end

S.rectPt = function(x, y, w, h, t, r)
    r = r or 0
    local sw, sh = maxf(1, w - 2 * r), maxf(1, h - 2 * r)
    local d = (t % 1) * (2 * (sw + sh))
    if d < sw then return x + r + d, y, 1 end
    d = d - sw
    if d < sh then return x + w, y + r + d, 2 end
    d = d - sh
    if d < sw then return x + w - r - d, y + h, 3 end
    return x, y + h - r - (d - sw), 4
end

local allTexts = {}

local function mkSquare(filled, col, corner, alpha)
    local d = S:Track(Drawing.new("Square"))
    d.Filled = filled and true or false
    d.Color = col or T.bg
    d.Transparency = alpha or 1
    prop(d, "Corner", corner or 0)
    prop(d, "Thickness", 1)
    d.Visible = false
    return d
end

local function mkText(str, size, col, center)
    local d = S:Track(Drawing.new("Text"))
    local base = size or 13
    d.Text = str or ""
    d.Color = col or T.text
    d.Center = center and true or false
    -- Outline = sharp readable text on busy game backgrounds (was false → looked blurry)
    d.Outline = true
    prop(d, "OutlineColor", Color3.fromRGB(0, 0, 0))
    prop(d, "Font", S.font or Drawing.Fonts.UI or Drawing.Fonts.Monospace)
    local sz = math.max(10, math.floor(base * (S.textScale or 1) + 0.5))
    prop(d, "Size", sz)
    d.Visible = false
    allTexts[#allTexts + 1] = { d = d, s = base }
    return d
end

local DT = 1 / 60
local function lerp(a, b, t)
    return a + (b - a) * t
end
local function approach(cur, target, speed)
    local t = 1 - math.exp(-(speed or 12) * DT)
    local v = lerp(cur or 0, target, t)
    if abs(v - target) < 0.001 then return target end
    return v
end
local function cLerp(a, b, t)
    return Color3.fromRGB(
        floor(lerp(a.R * 255, b.R * 255, t)),
        floor(lerp(a.G * 255, b.G * 255, t)),
        floor(lerp(a.B * 255, b.B * 255, t))
    )
end
local function mkCircle(col, radius, filled)
    local d = S:Track(Drawing.new("Circle"))
    d.Color = col or T.knob
    d.Radius = radius or 5
    d.Filled = filled ~= false
    d.NumSides = 24
    prop(d, "Thickness", 1)
    d.Visible = false
    return d
end
local function mkLine(col, thick)
    local d = S:Track(Drawing.new("Line"))
    d.Color = col or T.text
    d.Thickness = thick or 1
    d.Visible = false
    return d
end
local function mkTri(col)
    local d = S:Track(Drawing.new("Triangle"))
    d.Color = col or T.textDim
    d.Filled = true
    d.Visible = false
    return d
end
local function setText(d, cache, key, str)
    if cache[key] ~= str then
        d.Text = str
        cache[key] = str
    end
end
local function inRect(mx, my, x, y, w, h)
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end
local function viewport()
    local cam = Workspace.CurrentCamera
    local vp
    pcall(function() vp = cam and cam.ViewportSize end)
    if vp and vp.X and vp.X > 0 then return vp.X, vp.Y end
    return 1920, 1080
end

--------------------------------------------------------------------
-- Mouse (UIS — this executor has no ismouse1pressed / iskeypressed)
--------------------------------------------------------------------
local M = {
    x = 0, y = 0,
    down = false, pressed = false,
    _edge = false, _held = false,
}
S.hideSystemCursor = true
S._prevMouseBehavior = nil
S._menuUnlocked = false

local function unlockMouseForMenu(want)
    if want then
        pcall(function()
            if not S._menuUnlocked then
                S._prevMouseBehavior = UserInputService.MouseBehavior
                S._menuUnlocked = true
            end
            -- game combat scripts re-lock every frame — keep forcing Default while open
            if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
                UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            end
        end)
    elseif S._menuUnlocked then
        -- Don't force Lock* back — that soft-locks the cursor after close.
        -- Leave Default; the game re-applies its own lock next frame if needed.
        pcall(function()
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
            UserInputService.MouseIconEnabled = true
        end)
        S._prevMouseBehavior = nil
        S._menuUnlocked = false
    end
end

S:Connect(UserInputService.InputBegan, function(input, _gp)
    if not S.alive then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        M._held = true
        M._edge = true
    end
end)

S:Connect(UserInputService.InputEnded, function(input)
    if not S.alive then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        M._held = false
    end
end)

local function updateMouse()
    -- Drawing API = absolute screen space = GetMouseLocation (includes topbar inset)
    local got = false
    pcall(function()
        local loc = UserInputService:GetMouseLocation()
        if loc then
            M.x, M.y = loc.X, loc.Y
            got = true
        end
    end)
    if not got and Mouse then
        pcall(function()
            local inset = GuiService:GetGuiInset()
            M.x = Mouse.X + (inset and inset.X or 0)
            M.y = Mouse.Y + (inset and inset.Y or 0)
        end)
    end

    local nowDown = M._held
    if not nowDown then
        pcall(function()
            nowDown = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        end)
    end
    if type(ismouse1pressed) == "function" and not nowDown then
        pcall(function() nowDown = ismouse1pressed() end)
    end

    local active = true
    if type(isrbxactive) == "function" then
        pcall(function() active = isrbxactive() end)
    end
    if not active then
        nowDown = false
        M._edge = false
        M._held = false
    end

    M.pressed = M._edge or (nowDown and not M.down)
    M._edge = false
    M.down = nowDown
end
S.Mouse = M

--------------------------------------------------------------------
-- Notifications
--------------------------------------------------------------------
local NOTE_MAX = 6
local notes = {}
local noteSlots = {}
for i = 1, NOTE_MAX do
    noteSlots[i] = {
        bg = mkSquare(true, T.header, 5, 0.95),
        bar = mkSquare(true, T.accent, 2, 1),
        t1 = mkText("", 11, T.text, false),
        t2 = mkText("", 10, T.textDim, false),
        cache = {},
    }
end

local function notify(title, body, dur, kind)
    local col = T.accent
    if kind == "good" then
        col = T.good
    elseif kind == "bad" then
        col = T.bad
    end
    table.insert(notes, 1, {
        title = title,
        body = body or "",
        until_ = tick() + (dur or 4),
        col = col,
    })
    while #notes > NOTE_MAX do
        table.remove(notes)
    end
    S:PlayUI("notify", 0.22)
end
S.Notify = notify

local function drawNotes()
    local vpX = viewport()
    local now = tick()
    for i = #notes, 1, -1 do
        if now > notes[i].until_ then table.remove(notes, i) end
    end
    for i = 1, NOTE_MAX do
        local sl = noteSlots[i]
        local n = notes[i]
        if n then
            n.anim = approach(n.anim or 0, 1, 15)
            n.slot = approach(n.slot or i, i, 12)
            local left = n.until_ - now
            local A = n.anim
            if left < 0.4 then A = A * maxf(0, left / 0.4) end
            local w, h = 240, 40
            local x = vpX - w - 14 + (1 - n.anim) * (w + 20)
            local y = 60 + (n.slot - 1) * (h + 6)
            sl.bg.Position = Vector2.new(x, y)
            sl.bg.Size = Vector2.new(w, h)
            sl.bg.Transparency = 0.95 * A
            sl.bg.Visible = true
            sl.bg.ZIndex = 900
            sl.bar.Position = Vector2.new(x, y)
            sl.bar.Size = Vector2.new(3, h)
            sl.bar.Color = n.col
            sl.bar.Transparency = A
            sl.bar.Visible = true
            sl.bar.ZIndex = 901
            setText(sl.t1, sl.cache, "a", n.title)
            sl.t1.Position = Vector2.new(x + 10, y + 5)
            sl.t1.Color = n.col
            sl.t1.Transparency = A
            sl.t1.Visible = true
            sl.t1.ZIndex = 902
            setText(sl.t2, sl.cache, "b", n.body)
            sl.t2.Position = Vector2.new(x + 10, y + 22)
            sl.t2.Transparency = A
            sl.t2.Visible = true
            sl.t2.ZIndex = 902
        else
            sl.bg.Visible = false
            sl.bar.Visible = false
            sl.t1.Visible = false
            sl.t2.Visible = false
        end
    end
end

S.dimSq = mkSquare(true, Color3.fromRGB(0, 0, 0), 0, 1)

--------------------------------------------------------------------
-- Window
--------------------------------------------------------------------
local topZ = 100
local Window = {}
Window.__index = Window

function S:Window(opts)
    opts = opts or {}
    local vis0 = opts.visible ~= false
    local w = setmetatable({
        title = opts.title or "Window",
        x = opts.x or 100,
        y = opts.y or 100,
        w = opts.w or 296,
        h = 60,
        visible = vis0,
        tabs = {},
        activeTab = 1,
        z = topZ,
        cache = {},
        dragging = false,
        dragDX = 0,
        dragDY = 0,
        anim = vis0 and 1 or 0,
        animT = vis0 and 1 or 0,
        collapsed = false,
        colAnim = 1,
    }, Window)
    topZ = topZ + 20
    w.bg = mkSquare(true, T.bg, T.corner, T.bgAlpha)
    w.outline = mkSquare(false, T.border, T.corner, 1)
    w.barBg = mkSquare(true, T.header, T.corner, 1)
    w.shadow = {}
    for i = 1, 4 do
        w.shadow[i] = mkSquare(true, Color3.fromRGB(0, 0, 0), T.corner + i * 2, 1)
    end
    w.inner = mkSquare(false, T.text, maxf(1, T.corner - 1), 1)
    w.grad = {}
    for i = 1, 12 do
        w.grad[i] = mkLine(T.accent, 1)
    end
    w.tabInd = mkSquare(true, T.accent, 2, 1)
    w.edge, w.edgeOk = {}, {}
    for i = 1, 32 do
        w.edge[i] = mkLine(T.accent, 2)
        w.edgeOk[i] = true
    end
    w.chev = mkText(">", 12, T.accent, false)
    w.titleT = mkText(w.title, 12, T.text, false)
    w.closeT = mkText("X", 12, T.textDim, true)
    w._baseW = w.w
    S.windows[#S.windows + 1] = w
    return w
end

function Window:Tab(name)
    local t = { name = name, widgets = {}, win = self }
    t.glow = { mkSquare(true, T.accent, 8, 1), mkSquare(true, T.accent, 10, 1) }
    t.btnBg = mkSquare(true, T.header, 6, 1)
    t.btnT = mkText(name, 11, T.textDim, true)
    self.tabs[#self.tabs + 1] = t

    function t:Section(title)
        local s = {}
        s.accent = mkSquare(true, T.accent, 1, 1)
        s.titleT = mkText(string.upper(title), 11, T.section, false)
        t.widgets[#t.widgets + 1] = { kind = "section", s = s }

        function s:Toggle(label, default, cb)
            local wd = {
                kind = "toggle",
                value = default and true or false,
                cb = cb,
                hoverBg = mkSquare(true, T.rowHover, 5, 0.55),
                labelT = mkText(label, 11, T.label, false),
                glow = { mkSquare(true, T.accent, 9, 1), mkSquare(true, T.accent, 11, 1) },
                track = mkSquare(true, T.trackOff, 8, 1),
                knob = mkCircle(T.knobOff, 5, true),
            }
            t.widgets[#t.widgets + 1] = wd
            S:Reg(t.win.title .. "/" .. t.name .. "/" .. label, wd)
            if cb then pcall(cb, wd.value) end
            return wd
        end

        function s:Slider(label, default, mn, mx, suffix, cb)
            local wd = {
                kind = "slider",
                value = default,
                mn = mn,
                mx = mx,
                suffix = suffix or "",
                cb = cb,
                cache = {},
                hoverBg = mkSquare(true, T.rowHover, 5, 0.55),
                labelT = mkText(label, 11, T.label, false),
                boxBg = mkSquare(true, T.valueBox, 4, 1),
                boxT = mkText("", 10, T.text, true),
                track = mkSquare(true, T.trackOff, 2, 1),
                fill = mkSquare(true, T.accent, 2, 1),
                gseg = {
                    mkSquare(true, T.accent, 2, 1),
                    mkSquare(true, T.accent, 2, 1),
                    mkSquare(true, T.accent, 2, 1),
                    mkSquare(true, T.accent, 2, 1),
                    mkSquare(true, T.accent, 2, 1),
                },
                kglow = { mkCircle(T.accent, 8, true), mkCircle(T.accent, 11, true) },
                knob = mkCircle(T.knob, 5, true),
            }
            t.widgets[#t.widgets + 1] = wd
            S:Reg(t.win.title .. "/" .. t.name .. "/" .. label, wd)
            if cb then pcall(cb, default) end
            return wd
        end

        function s:Dropdown(label, options, default, cb)
            local wd = {
                kind = "dropdown",
                options = options,
                index = 1,
                cb = cb,
                cache = {},
                rawLabel = label,
                hoverBg = mkSquare(true, T.rowHover, 5, 0.55),
                labelT = mkText(label, 11, T.label, false),
                boxBg = mkSquare(true, T.valueBox, 5, 1),
                boxT = mkText("", 10, T.text, true),
                arrow = mkTri(T.textDim),
            }
            for i, o in ipairs(options) do
                if o == default then wd.index = i end
            end
            t.widgets[#t.widgets + 1] = wd
            S:Reg(t.win.title .. "/" .. t.name .. "/" .. label, wd)
            if cb then pcall(cb, options[wd.index]) end
            return wd
        end

        function s:Button(label, cb)
            local wd = {
                kind = "button",
                cb = cb,
                hoverBg = mkSquare(true, T.rowHover, 5, 0.55),
                boxBg = mkSquare(true, T.accentDim, 5, 1),
                labelT = mkText(label, 11, T.text, true),
            }
            t.widgets[#t.widgets + 1] = wd
            return wd
        end

        function s:Label(text)
            local wd = { kind = "label", labelT = mkText(text, 10, T.textDim, false) }
            t.widgets[#t.widgets + 1] = wd
            return wd
        end

        function s:Search(label, cb)
            local wd = {
                kind = "search",
                text = "",
                cb = cb,
                cache = {},
                focus = false,
                hoverBg = mkSquare(true, T.rowHover, 5, 0.55),
                labelT = mkText(label, 11, T.label, false),
                boxBg = mkSquare(true, T.valueBox, 5, 1),
                boxT = mkText("", 10, T.text, false),
            }
            t.widgets[#t.widgets + 1] = wd
            return wd
        end

        function s:Keybind(label, defaultVK, cb)
            local wd = {
                kind = "keybind",
                vk = defaultVK,
                cb = cb,
                cache = {},
                listening = false,
                hoverBg = mkSquare(true, T.rowHover, 5, 0.55),
                labelT = mkText(label, 11, T.label, false),
                boxBg = mkSquare(true, T.valueBox, 5, 1),
                boxT = mkText("", 10, T.text, true),
            }
            t.widgets[#t.widgets + 1] = wd
            S:Reg(t.win.title .. "/" .. t.name .. "/" .. label, wd)
            if cb then pcall(cb, defaultVK) end
            return wd
        end

        return s
    end

    return t
end

local function hideWidget(wd)
    if wd.kind == "section" then
        wd.s.accent.Visible = false
        wd.s.titleT.Visible = false
    else
        local keys = { "hoverBg", "labelT", "track", "fill", "knob", "boxBg", "boxT", "arrow", "popBg", "popEdge" }
        for _, k in ipairs(keys) do
            if wd[k] then wd[k].Visible = false end
        end
        if wd.optBg then
            for _, d in ipairs(wd.optBg) do d.Visible = false end
        end
        if wd.optT then
            for _, d in ipairs(wd.optT) do d.Visible = false end
        end
        for _, k in ipairs({ "glow", "gseg", "kglow" }) do
            if wd[k] then
                for _, d in ipairs(wd[k]) do d.Visible = false end
            end
        end
        wd.open = false
        wd.optRects = nil
        if wd.kind == "search" and wd.focus then
            wd.focus = false
            if S.searchFocus == wd then S.searchFocus = nil end
        end
    end
    wd.rect = nil
end

function Window:Show(v)
    self.visible = v
    self.animT = v and 1 or 0
    if v then self.tabT = tick() end
end

function Window:bringToFront()
    topZ = topZ + 20
    self.z = topZ
end

-- Layout + input are large; kept faithful to SEIM originals below.
function Window:layout()
    self.animT = self.visible and 1 or 0
    self.anim = approach(self.anim, self.animT, 14)
    local A = self.anim
    local focused = true
    if S.fx then
        local top = 0
        for _, ow in ipairs(S.windows) do
            if ow.visible and ow.z > top then top = ow.z end
        end
        focused = (self.z >= top)
        self.fAnim = approach(self.fAnim or 1, focused and 1 or 0, 10)
        A = A * lerp(0.72, 1, self.fAnim)
    end
    local vis = A > 0.02
    local slide = (1 - A) * -14
    local vpX, vpY = viewport()
    if self.x + self.w > vpX - 4 then self.x = vpX - self.w - 4 end
    if self.y + 40 > vpY then self.y = vpY - 40 end
    if self.x < 4 then self.x = 4 end
    if self.y < 4 then self.y = 4 end

    local x, y, w, z = self.x, self.y + slide, self.w, self.z
    local BAR = 28
    self.colAnim = approach(self.colAnim, self.collapsed and 0 or 1, 16)
    local C = self.colAnim
    local cvis = vis and A > 0.35 and C > 0.55
    local tabRowH = (#self.tabs > 1) and 28 or 0
    local startY = y + BAR + tabRowH + 6
    local cy = startY
    local at = self.tabs[self.activeTab]
    if at then
        for _, wd in ipairs(at.widgets) do
            if wd.kind == "section" then
                cy = cy + 32
            elseif wd.kind == "label" then
                cy = cy + 17
            elseif wd.kind == "slider" then
                cy = cy + T.rowH + 12
            else
                cy = cy + T.rowH
            end
        end
    end
    local fullH = (cy - y) + 10
    self.h = BAR + (fullH - BAR) * C

    for i = 1, 4 do
        local sh = self.shadow[i]
        if S.fx then
            local sp = 1 + (self.fAnim or 1) * 0.8
            local o = i * 2 * sp
            sh.Position = Vector2.new(x - o, y - o + 3 * sp)
            sh.Size = Vector2.new(w + o * 2, self.h + o * 2)
            sh.Transparency = 0.14 * A * (1 - (i - 1) / 4) * sp
            sh.Visible = vis
            sh.ZIndex = z - i
        else
            sh.Visible = false
        end
    end

    self.bg.Position = Vector2.new(x, y)
    self.bg.Size = Vector2.new(w, self.h)
    self.bg.Visible = vis
    self.bg.ZIndex = z
    self.bg.Transparency = T.bgAlpha * A
    self.outline.Position = Vector2.new(x, y)
    self.outline.Size = Vector2.new(w, self.h)
    self.outline.Visible = vis
    self.outline.ZIndex = z + 1
    self.outline.Transparency = A
    if S.fx then
        self.inner.Position = Vector2.new(x + 1, y + 1)
        self.inner.Size = Vector2.new(w - 2, self.h - 2)
        self.inner.Color = cLerp(T.border, T.text, 0.28)
        self.inner.Transparency = 0.30 * A
        self.inner.Visible = vis
        self.inner.ZIndex = z + 2
    else
        self.inner.Visible = false
    end
    self.barBg.Position = Vector2.new(x, y)
    self.barBg.Size = Vector2.new(w, BAR)
    self.barBg.Visible = vis
    self.barBg.ZIndex = z + 1
    self.barBg.Transparency = A

    local NG = #self.grad
    local gx0, gw = x + T.corner, w - T.corner * 2
    local seg = gw / NG
    for i = 1, NG do
        local g = self.grad[i]
        if S.fx and gw > 0 then
            local t0 = (i - 1) / NG
            local cx = gx0 + t0 * gw
            g.From = Vector2.new(cx, y + BAR - 1)
            g.To = Vector2.new(cx + seg + 1, y + BAR - 1)
            g.Thickness = 2
            g.Color = cLerp(T.accent, T.header, t0)
            g.Visible = vis
            g.ZIndex = z + 2
        else
            g.Visible = false
        end
    end

    setText(self.chev, self.cache, "c", self.collapsed and ">" or "v")
    self.chev.Color = self.chevHover and T.text or T.accent
    self.chev.Position = Vector2.new(x + 9, S:CenterY(y, 28, 12))
    self.chev.Visible = vis
    self.chev.ZIndex = z + 2
    self.chev.Transparency = A
    self.titleT.Position = Vector2.new(x + 24, S:CenterY(y, 28, 12))
    self.titleT.Visible = vis
    self.titleT.ZIndex = z + 2
    self.titleT.Transparency = A
    self.closeT.Position = Vector2.new(x + w - 14, S:CenterY(y, 28, 12))
    self.closeT.Visible = vis
    self.closeT.ZIndex = z + 2
    self.closeT.Transparency = A
    self.chevRect = { x + 2, y + 3, 22, 22 }
    self.barRect = { x + 24, y, w - 54, BAR }
    self.closeRect = { x + w - 26, y + 4, 22, 22 }

    if #self.tabs > 1 then
        local tw = (w - T.pad * 2) / #self.tabs
        for i, tab in ipairs(self.tabs) do
            local tx = x + T.pad + (i - 1) * tw
            local act = (i == self.activeTab)
            tab.btnBg.Position = Vector2.new(tx + 1, y + BAR + 2)
            tab.btnBg.Size = Vector2.new(tw - 2, 22)
            tab.btnBg.Color = act and T.accentDim or T.header
            tab.btnBg.Visible = cvis
            tab.btnBg.ZIndex = z + 2
            tab.btnT.Position = Vector2.new(tx + tw / 2, S:CenterY(y + BAR + 2, 22, 11))
            tab.btnT.Color = act and T.text or T.textDim
            tab.btnT.Visible = cvis
            tab.btnT.ZIndex = z + 3
            tab.rect = { tx, y + BAR + 2, tw, 22 }
            for _, g in ipairs(tab.glow) do g.Visible = false end
        end
        if S.fx and cvis then
            local aX = x + T.pad + (self.activeTab - 1) * tw + 1
            local aW = tw - 2
            self.indX = approach(self.indX or aX, aX, 18)
            self.indW = approach(self.indW or aW, aW, 18)
            self.tabInd.Position = Vector2.new(self.indX, y + BAR + 22)
            self.tabInd.Size = Vector2.new(self.indW, 2)
            self.tabInd.Color = T.accent
            self.tabInd.Transparency = A
            self.tabInd.Visible = true
            self.tabInd.ZIndex = z + 4
        else
            self.tabInd.Visible = false
        end
    else
        for _, tab in ipairs(self.tabs) do
            tab.btnBg.Visible = false
            tab.btnT.Visible = false
            tab.rect = nil
            for _, g in ipairs(tab.glow) do g.Visible = false end
        end
        self.tabInd.Visible = false
    end

    for i, tab in ipairs(self.tabs) do
        if i ~= self.activeTab then
            for _, wd in ipairs(tab.widgets) do hideWidget(wd) end
        end
    end
    if not at then return end
    if not cvis then
        for _, wd in ipairs(at.widgets) do hideWidget(wd) end
        return
    end

    local ry = startY
    local iX, iW = x + T.pad, w - T.pad * 2
    for _, wd in ipairs(at.widgets) do
        if wd.kind == "section" then
            wd.s.accent.Position = Vector2.new(iX, ry + 10)
            wd.s.accent.Size = Vector2.new(2, 10)
            wd.s.accent.Visible = true
            wd.s.accent.ZIndex = z + 3
            wd.s.titleT.Position = Vector2.new(iX + 9, S:CenterY(ry + 10, 11, 9))
            wd.s.titleT.Visible = true
            wd.s.titleT.ZIndex = z + 3
            ry = ry + 32
        elseif wd.kind == "label" then
            wd.labelT.Position = Vector2.new(iX, ry)
            wd.labelT.Visible = true
            wd.labelT.ZIndex = z + 3
            ry = ry + 17
        elseif wd.kind == "toggle" then
            wd.tAnim = approach(wd.tAnim or (wd.value and 1 or 0), wd.value and 1 or 0, 16)
            wd.hAnim = approach(wd.hAnim or 0, wd.hover and 1 or 0, 14)
            wd.hoverBg.Position = Vector2.new(iX - 5, ry)
            wd.hoverBg.Size = Vector2.new(iW + 10, T.rowH - 4)
            wd.hoverBg.Transparency = 0.55 * wd.hAnim * A
            wd.hoverBg.Visible = wd.hAnim > 0.02
            wd.hoverBg.ZIndex = z + 2
            wd.labelT.Position = Vector2.new(iX, S:CenterY(ry, T.rowH - 4, 11))
            wd.labelT.Color = cLerp(T.label, T.accent, wd.hAnim * 0.5)
            wd.labelT.Visible = true
            wd.labelT.ZIndex = z + 3
            local tw2, th2 = 30, 15
            local tx = x + w - T.pad - tw2
            for gi = 1, 2 do
                local g = wd.glow[gi]
                if S.fx and wd.tAnim > 0.03 then
                    local o = gi * 2
                    g.Position = Vector2.new(tx - o, ry + 5 - o)
                    g.Size = Vector2.new(tw2 + o * 2, th2 + o * 2)
                    g.Color = T.accent
                    g.Transparency = 0.22 * wd.tAnim * A / gi
                    g.Visible = true
                    g.ZIndex = z + 2
                else
                    g.Visible = false
                end
            end
            wd.track.Position = Vector2.new(tx, ry + 5)
            wd.track.Size = Vector2.new(tw2, th2)
            wd.track.Color = cLerp(T.trackOff, T.accent, wd.tAnim)
            wd.track.Visible = true
            wd.track.ZIndex = z + 3
            local kx = lerp(tx + 8, tx + tw2 - 8, wd.tAnim)
            wd.knob.Position = Vector2.new(kx, ry + 5 + th2 / 2)
            wd.knob.Color = cLerp(T.knobOff, T.knob, wd.tAnim)
            wd.knob.Visible = true
            wd.knob.ZIndex = z + 4
            wd.rect = { iX - 5, ry, iW + 10, T.rowH - 4 }
            ry = ry + T.rowH
        elseif wd.kind == "slider" then
            local rh = T.rowH + 12
            wd.hAnim = approach(wd.hAnim or 0, wd.hover and 1 or 0, 14)
            wd.hoverBg.Position = Vector2.new(iX - 5, ry)
            wd.hoverBg.Size = Vector2.new(iW + 10, rh - 4)
            wd.hoverBg.Transparency = 0.55 * wd.hAnim * A
            wd.hoverBg.Visible = wd.hAnim > 0.02
            wd.hoverBg.ZIndex = z + 2
            wd.labelT.Position = Vector2.new(iX, ry + 3)
            wd.labelT.Visible = true
            wd.labelT.ZIndex = z + 3
            local bw, bh = 46, 16
            local bx = x + w - T.pad - bw
            wd.boxBg.Position = Vector2.new(bx, ry + 1)
            wd.boxBg.Size = Vector2.new(bw, bh)
            wd.boxBg.Visible = true
            wd.boxBg.ZIndex = z + 3
            setText(wd.boxT, wd.cache, "v", tostring(floor(wd.value)) .. wd.suffix)
            wd.boxT.Position = Vector2.new(bx + bw / 2, S:CenterY(ry + 1, 16, 10))
            wd.boxT.Visible = true
            wd.boxT.ZIndex = z + 4
            local ty = ry + 26
            wd.track.Position = Vector2.new(iX, ty)
            wd.track.Size = Vector2.new(iW, 4)
            wd.track.Visible = true
            wd.track.ZIndex = z + 3
            local pct = clamp((wd.value - wd.mn) / maxf(1, wd.mx - wd.mn), 0, 1)
            wd.pAnim = approach(wd.pAnim or pct, pct, 20)
            local fw = maxf(1, iW * wd.pAnim)
            for i = 1, 5 do wd.gseg[i].Visible = false end
            wd.fill.Position = Vector2.new(iX, ty)
            wd.fill.Size = Vector2.new(fw, 4)
            wd.fill.Visible = true
            wd.fill.ZIndex = z + 4
            for gi = 1, 2 do wd.kglow[gi].Visible = false end
            wd.knob.Position = Vector2.new(iX + iW * wd.pAnim, ty + 2)
            wd.knob.Visible = true
            wd.knob.ZIndex = z + 5
            wd.rect = { iX - 5, ry, iW + 10, rh - 4 }
            wd.trackRect = { iX, ty - 8, iW, 20 }
            ry = ry + rh
        elseif wd.kind == "dropdown" then
            wd.hAnim = approach(wd.hAnim or 0, wd.hover and 1 or 0, 14)
            wd.hoverBg.Position = Vector2.new(iX - 5, ry)
            wd.hoverBg.Size = Vector2.new(iW + 10, T.rowH - 4)
            wd.hoverBg.Transparency = 0.55 * wd.hAnim * A
            wd.hoverBg.Visible = wd.hAnim > 0.02
            wd.hoverBg.ZIndex = z + 2
            wd.labelT.Position = Vector2.new(iX, S:CenterY(ry, T.rowH - 4, 11))
            wd.labelT.Visible = true
            wd.labelT.ZIndex = z + 3
            local bw, bh = 98, 18
            local bx = x + w - T.pad - bw
            wd.boxBg.Position = Vector2.new(bx, ry + 4)
            wd.boxBg.Size = Vector2.new(bw, bh)
            wd.boxBg.Color = wd.open and T.accentDim or T.valueBox
            wd.boxBg.Visible = true
            wd.boxBg.ZIndex = z + 3
            setText(wd.boxT, wd.cache, "v", S:Fit(wd.options[wd.index], bw - 18, 10))
            setText(wd.labelT, wd.cache, "l", S:Fit(wd.rawLabel or wd.labelT.Text, iW - bw - 12, 11))
            wd.boxT.Position = Vector2.new(bx + bw / 2 - 5, S:CenterY(ry + 4, 18, 10))
            wd.boxT.Visible = true
            wd.boxT.ZIndex = z + 4
            wd.oAnim = approach(wd.oAnim or 0, wd.open and 1 or 0, 18)
            local ax, ay = bx + bw - 11, ry + 11
            local flip = lerp(1, -1, wd.oAnim)
            wd.arrow.PointA = Vector2.new(ax - 4, ay - 2 * flip)
            wd.arrow.PointB = Vector2.new(ax + 4, ay - 2 * flip)
            wd.arrow.PointC = Vector2.new(ax, ay + 3 * flip)
            wd.arrow.Visible = true
            wd.arrow.ZIndex = z + 4
            wd.rect = { iX - 5, ry, iW + 10, T.rowH - 4 }

            local n = #wd.options
            wd.popBg = wd.popBg or mkSquare(true, T.header, 5, 1)
            wd.popEdge = wd.popEdge or mkSquare(false, T.accent, 5, 1)
            wd.optBg = wd.optBg or {}
            wd.optT = wd.optT or {}
            for i = 1, n do
                wd.optBg[i] = wd.optBg[i] or mkSquare(true, T.accentDim, 3, 1)
                wd.optT[i] = wd.optT[i] or mkText("", 10, T.text, false)
            end
            if wd.oAnim > 0.02 then
                local orH = 17
                local fullH2 = n * orH + 6
                local ph = fullH2 * wd.oAnim
                local longest = 0
                for i = 1, n do
                    local l = #tostring(wd.options[i])
                    if l > longest then longest = l end
                end
                local pw = maxf(bw, minf(186, longest * 6.0 + 16))
                local px = bx + bw - pw
                local py = ry + 4 + bh + 2
                local pz = z + 40
                wd.popBg.Position = Vector2.new(px, py)
                wd.popBg.Size = Vector2.new(pw, ph)
                wd.popBg.Transparency = A
                wd.popBg.Visible = true
                wd.popBg.ZIndex = pz
                wd.popEdge.Position = Vector2.new(px, py)
                wd.popEdge.Size = Vector2.new(pw, ph)
                wd.popEdge.Transparency = 0.7 * A
                wd.popEdge.Visible = true
                wd.popEdge.ZIndex = pz + 1
                wd.optRects = {}
                for i = 1, n do
                    local oy = py + 3 + (i - 1) * orH
                    local shown = (oy + orH) <= (py + ph)
                    local sel = (i == wd.index)
                    local ohov = wd.optHover == i
                    if shown then
                        wd.optBg[i].Position = Vector2.new(px + 3, oy)
                        wd.optBg[i].Size = Vector2.new(pw - 6, orH - 2)
                        wd.optBg[i].Color = sel and T.accent or T.accentDim
                        wd.optBg[i].Transparency = (sel and 0.85 or (ohov and 0.6 or 0)) * A
                        wd.optBg[i].Visible = sel or ohov
                        wd.optBg[i].ZIndex = pz + 2
                        setText(wd.optT[i], wd.cache, "o" .. i, S:Fit(wd.options[i], pw - 14, 10))
                        wd.optT[i].Position = Vector2.new(px + 8, S:CenterY(oy, orH - 2, 10))
                        wd.optT[i].Color = sel and Color3.fromRGB(20, 12, 20) or T.text
                        wd.optT[i].Visible = true
                        wd.optT[i].ZIndex = pz + 3
                        wd.optRects[i] = { px + 3, oy, pw - 6, orH - 2 }
                    else
                        wd.optBg[i].Visible = false
                        wd.optT[i].Visible = false
                    end
                end
            else
                wd.popBg.Visible = false
                wd.popEdge.Visible = false
                wd.optRects = nil
            end
            ry = ry + T.rowH
        elseif wd.kind == "button" then
            wd.hAnim = approach(wd.hAnim or 0, wd.hover and 1 or 0, 16)
            wd.hoverBg.Visible = false
            wd.boxBg.Position = Vector2.new(iX, ry + 3)
            wd.boxBg.Size = Vector2.new(iW, 20)
            wd.boxBg.Color = cLerp(T.accentDim, T.accent, wd.hAnim)
            wd.boxBg.Transparency = A
            wd.boxBg.Visible = true
            wd.boxBg.ZIndex = z + 3
            wd.labelT.Position = Vector2.new(iX + iW / 2, S:CenterY(ry + 3, 20, 11))
            wd.labelT.Visible = true
            wd.labelT.ZIndex = z + 4
            wd.rect = { iX, ry + 3, iW, 20 }
            ry = ry + T.rowH
        elseif wd.kind == "search" then
            wd.hAnim = approach(wd.hAnim or 0, wd.hover and 1 or 0, 14)
            wd.hoverBg.Position = Vector2.new(iX - 5, ry)
            wd.hoverBg.Size = Vector2.new(iW + 10, T.rowH - 4)
            wd.hoverBg.Transparency = 0.55 * wd.hAnim * A
            wd.hoverBg.Visible = wd.hAnim > 0.02
            wd.hoverBg.ZIndex = z + 2
            wd.labelT.Position = Vector2.new(iX, S:CenterY(ry, T.rowH - 4, 11))
            wd.labelT.Visible = true
            wd.labelT.ZIndex = z + 3
            local bw, bh = 150, 18
            local bx = x + w - T.pad - bw
            wd.boxBg.Position = Vector2.new(bx, ry + 4)
            wd.boxBg.Size = Vector2.new(bw, bh)
            wd.boxBg.Color = wd.focus and T.accentDim or T.valueBox
            wd.boxBg.Transparency = A
            wd.boxBg.Visible = true
            wd.boxBg.ZIndex = z + 3
            local shown = wd.text
            if shown == "" then shown = wd.focus and "" or "click to type" end
            if wd.focus and (floor(tick() * 2) % 2 == 0) then shown = shown .. "_" end
            setText(wd.boxT, wd.cache, "v", S:Fit(shown, bw - 10, 10))
            wd.boxT.Color = (wd.text == "" and not wd.focus) and T.textDim or T.text
            wd.boxT.Position = Vector2.new(bx + 5, S:CenterY(ry + 4, 18, 10))
            wd.boxT.Visible = true
            wd.boxT.ZIndex = z + 4
            wd.rect = { iX - 5, ry, iW + 10, T.rowH - 4 }
            ry = ry + T.rowH
        elseif wd.kind == "keybind" then
            wd.hAnim = approach(wd.hAnim or 0, wd.hover and 1 or 0, 14)
            wd.hoverBg.Position = Vector2.new(iX - 5, ry)
            wd.hoverBg.Size = Vector2.new(iW + 10, T.rowH - 4)
            wd.hoverBg.Transparency = 0.55 * wd.hAnim * A
            wd.hoverBg.Visible = wd.hAnim > 0.02
            wd.hoverBg.ZIndex = z + 2
            wd.labelT.Position = Vector2.new(iX, S:CenterY(ry, T.rowH - 4, 11))
            wd.labelT.Visible = true
            wd.labelT.ZIndex = z + 3
            local bw, bh = 66, 18
            local bx = x + w - T.pad - bw
            wd.boxBg.Position = Vector2.new(bx, ry + 4)
            wd.boxBg.Size = Vector2.new(bw, bh)
            wd.boxBg.Color = wd.listening and T.accent or T.valueBox
            wd.boxBg.Transparency = A
            wd.boxBg.Visible = true
            wd.boxBg.ZIndex = z + 3
            setText(wd.boxT, wd.cache, "v", wd.listening and "press.." or S:KeyName(wd.vk))
            wd.boxT.Color = wd.listening and Color3.fromRGB(20, 12, 20) or T.text
            wd.boxT.Position = Vector2.new(bx + bw / 2, S:CenterY(ry + 4, 18, 10))
            wd.boxT.Visible = true
            wd.boxT.ZIndex = z + 4
            wd.rect = { iX - 5, ry, iW + 10, T.rowH - 4 }
            ry = ry + T.rowH
        end
    end
end

function Window:handleInput()
    if not self.visible then return false end
    if S._ignoreClickUntil and tick() < S._ignoreClickUntil then
        return false
    end
    local mx, my = M.x, M.y
    local used = false

    local dd = self.openDD
    if dd and dd.optRects then
        dd.optHover = nil
        for i, r in ipairs(dd.optRects) do
            if inRect(mx, my, r[1], r[2], r[3], r[4]) then
                dd.optHover = i
                break
            end
        end
        if M.pressed then
            if dd.optHover then
                dd.index = dd.optHover
                if dd.cb then pcall(dd.cb, dd.options[dd.index]) end
                S:PlayUI("use")
            else
                S:PlayUI("click")
            end
            dd.open = false
            dd.optHover = nil
            self.openDD = nil
            self:bringToFront()
            return true
        end
        used = true
    end

    if self.dragging then
        if M.down then
            self.x = mx - self.dragDX
            self.y = my - self.dragDY
            used = true
        else
            self.dragging = false
        end
    end
    local chr = self.chevRect
    self.chevHover = chr and inRect(mx, my, chr[1], chr[2], chr[3], chr[4]) or false

    if M.pressed then
        if self.chevHover then
            self.collapsed = not self.collapsed
            S:PlayUI("click")
            self:bringToFront()
            return true
        end
        local cr = self.closeRect
        if cr and inRect(mx, my, cr[1], cr[2], cr[3], cr[4]) then
            self.visible = false
            S:PlayUI("close")
            return true
        end
        local b = self.barRect
        if b and inRect(mx, my, b[1], b[2], b[3], b[4]) then
            self.dragging = true
            self.dragDX = mx - self.x
            self.dragDY = my - self.y
            self:bringToFront()
            return true
        end
        for i, tab in ipairs(self.tabs) do
            if tab.rect and inRect(mx, my, tab.rect[1], tab.rect[2], tab.rect[3], tab.rect[4]) then
                if self.activeTab ~= i then
                    self.tabT = tick()
                    S:PlayUI("tab")
                end
                self.activeTab = i
                self:bringToFront()
                return true
            end
        end
    end

    local at = self.tabs[self.activeTab]
    if not at then return used end

    local lw = self.listenWidget
    if lw then
        if lw.cancelAt and tick() > lw.cancelAt then
            for vk in pairs(S.VK) do
                if S:KeyHeld(vk) then
                    if vk == 0x1B then
                        if lw.allowNil ~= false then
                            lw.vk = nil
                            lw.listening = false
                            self.listenWidget = nil
                            if lw.cb then pcall(lw.cb, lw.vk) end
                            S:PlayUI("click")
                        else
                            -- Esc cancels rebind without clearing (menu key etc.)
                            lw.listening = false
                            self.listenWidget = nil
                            S:PlayUI("click")
                        end
                        break
                    end
                    -- Never bind mouse buttons (LMB/RMB/MMB/XButtons)
                    if S:IsMouseVk(vk) then
                        -- ignore, keep listening
                    else
                        lw.vk = vk
                        lw.listening = false
                        self.listenWidget = nil
                        if lw.cb then pcall(lw.cb, lw.vk) end
                        S:PlayUI("use")
                        break
                    end
                end
            end
        end
        return true
    end

    for _, wd in ipairs(at.widgets) do
        if wd.rect then
            local hov = inRect(mx, my, wd.rect[1], wd.rect[2], wd.rect[3], wd.rect[4])
            wd.hover = hov
            if wd.kind == "slider" then
                if wd.drag and M.down then
                    local tr = wd.trackRect
                    local pct = clamp((mx - tr[1]) / maxf(1, tr[3]), 0, 1)
                    local nv = floor(wd.mn + (wd.mx - wd.mn) * pct + 0.5)
                    if nv ~= wd.value then
                        wd.value = nv
                        if wd.cb then pcall(wd.cb, nv) end
                    end
                    used = true
                elseif not M.down then
                    wd.drag = false
                end
                if M.pressed and wd.trackRect and inRect(mx, my, wd.trackRect[1], wd.trackRect[2], wd.trackRect[3], wd.trackRect[4]) then
                    wd.drag = true
                    S:PlayUI("click")
                    self:bringToFront()
                    return true
                end
            elseif M.pressed and hov then
                if wd.kind == "toggle" then
                    wd.value = not wd.value
                    if wd.cb then pcall(wd.cb, wd.value) end
                    S:PlayUI("toggle")
                    self:bringToFront()
                    return true
                elseif wd.kind == "dropdown" then
                    if self.openDD and self.openDD ~= wd then
                        self.openDD.open = false
                        self.openDD.optHover = nil
                    end
                    wd.open = not wd.open
                    self.openDD = wd.open and wd or nil
                    S:PlayUI("click")
                    self:bringToFront()
                    return true
                elseif wd.kind == "button" then
                    if wd.cb then pcall(wd.cb) end
                    S:PlayUI("use")
                    self:bringToFront()
                    return true
                elseif wd.kind == "search" then
                    if S.searchFocus and S.searchFocus ~= wd then
                        S.searchFocus.focus = false
                    end
                    wd.focus = true
                    S.searchFocus = wd
                    S:PlayUI("click")
                    self:bringToFront()
                    return true
                elseif wd.kind == "keybind" then
                    wd.listening = true
                    wd.cancelAt = tick() + 0.25
                    self.listenWidget = wd
                    S:PlayUI("click")
                    self:bringToFront()
                    return true
                end
            end
        end
    end
    return used
end

--------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------
local Panel = {}
Panel.__index = Panel

function S:Panel(opts)
    opts = opts or {}
    local p = setmetatable({
        title = opts.title or "Panel",
        x = opts.x or 20,
        y = opts.y or 20,
        w = opts.w or 210,
        visible = opts.visible ~= false,
        want = true,
        rows = {},
        pool = {},
        cache = {},
        z = 60,
        dragging = false,
        dragDX = 0,
        dragDY = 0,
        anim = 0,
    }, Panel)
    p.bg = mkSquare(true, T.bg, 6, T.bgAlpha)
    p.outline = mkSquare(false, T.border, 6, 1)
    p.barBg = mkSquare(true, T.header, 6, 1)
    p.titleT = mkText(p.title, 11, T.text, false)
    S.panels[#S.panels + 1] = p
    return p
end

function Panel:Set(rows)
    self.rows = rows or {}
    for i = #self.pool + 1, #self.rows do
        self.pool[i] = {
            l = mkText("", 10, T.text, false),
            r = mkText("", 10, T.textDim, false),
            b = mkSquare(true, T.valueBox, 3, 1),
        }
    end
end

function Panel:layout()
    self.anim = approach(self.anim, (self.visible and self.want ~= false) and 1 or 0, 13)
    local A = self.anim
    local vis = A > 0.02
    local cvis = A > 0.35
    local x, y, w, z = self.x + (1 - A) * -18, self.y, self.w, self.z
    local BAR, RH = 22, 17
    local h = BAR + #self.rows * RH + 6
    self.bg.Position = Vector2.new(x, y)
    self.bg.Size = Vector2.new(w, h)
    self.bg.Visible = vis
    self.bg.ZIndex = z
    self.bg.Transparency = T.bgAlpha * A
    self.outline.Position = Vector2.new(x, y)
    self.outline.Size = Vector2.new(w, h)
    self.outline.Visible = vis
    self.outline.ZIndex = z + 1
    self.outline.Transparency = A
    self.barBg.Position = Vector2.new(x, y)
    self.barBg.Size = Vector2.new(w, BAR)
    self.barBg.Visible = vis
    self.barBg.ZIndex = z + 1
    self.barBg.Transparency = A
    self.titleT.Position = Vector2.new(x + 8, S:CenterY(y, 22, 11))
    self.titleT.Visible = vis
    self.titleT.ZIndex = z + 2
    self.titleT.Transparency = A
    self.barRect = { self.x, y, w, BAR }
    vis = cvis
    for i, row in ipairs(self.rows) do
        local pr = self.pool[i]
        if pr then
            local ry = y + BAR + 3 + (i - 1) * RH
            setText(pr.l, self.cache, "l" .. i, tostring(row.left or ""))
            pr.l.Position = Vector2.new(x + 8, ry)
            pr.l.Color = row.color or T.text
            pr.l.Visible = vis
            pr.l.ZIndex = z + 3
            local rt = row.right and tostring(row.right) or ""
            if rt ~= "" then
                local bw = #rt * 7 + 10
                pr.b.Position = Vector2.new(x + w - 8 - bw, ry - 1)
                pr.b.Size = Vector2.new(bw, 15)
                pr.b.Visible = vis
                pr.b.ZIndex = z + 2
                setText(pr.r, self.cache, "r" .. i, rt)
                pr.r.Position = Vector2.new(x + w - 4 - bw, S:CenterY(ry - 1, 15, 10))
                pr.r.Color = row.rightColor or T.textDim
                pr.r.Visible = vis
                pr.r.ZIndex = z + 3
            else
                pr.b.Visible = false
                pr.r.Visible = false
            end
        end
    end
    for i = #self.rows + 1, #self.pool do
        self.pool[i].l.Visible = false
        self.pool[i].r.Visible = false
        self.pool[i].b.Visible = false
    end
end

function Panel:handleInput()
    if not self.visible or self.want == false then return false end
    if S._ignoreClickUntil and tick() < S._ignoreClickUntil then
        return false
    end
    local mx, my = M.x, M.y
    if self.dragging then
        if M.down then
            self.x = mx - self.dragDX
            self.y = my - self.dragDY
            return true
        else
            self.dragging = false
        end
    end
    if M.pressed and self.barRect and inRect(mx, my, self.barRect[1], self.barRect[2], self.barRect[3], self.barRect[4]) then
        self.dragging = true
        self.dragDX = mx - self.x
        self.dragDY = my - self.y
        return true
    end
    return false
end

--------------------------------------------------------------------
-- Theme / accent helpers
--------------------------------------------------------------------
S.THEMES = {
    ["Default"] = {
        bg = { 17, 16, 19 }, header = { 23, 22, 26 }, border = { 48, 45, 53 },
        text = { 226, 224, 230 }, label = { 178, 175, 186 }, textDim = { 124, 121, 132 },
        trackOff = { 44, 42, 49 }, rowHover = { 31, 29, 35 }, valueBox = { 27, 26, 31 },
        accent = { 255, 110, 190 },
    },
    ["Cyberpunk"] = {
        bg = { 14, 16, 20 }, header = { 19, 22, 28 }, border = { 42, 50, 62 },
        text = { 220, 230, 238 }, label = { 170, 182, 194 }, textDim = { 116, 128, 142 },
        trackOff = { 38, 44, 54 }, rowHover = { 26, 31, 38 }, valueBox = { 22, 26, 33 },
        accent = { 0, 224, 255 },
    },
    ["Blood"] = {
        bg = { 18, 15, 15 }, header = { 24, 20, 20 }, border = { 54, 44, 44 },
        text = { 230, 222, 222 }, label = { 182, 170, 170 }, textDim = { 128, 118, 118 },
        trackOff = { 48, 40, 40 }, rowHover = { 33, 28, 28 }, valueBox = { 29, 24, 24 },
        accent = { 240, 62, 72 },
    },
}
S.THEME_NAMES = { "Default", "Cyberpunk", "Blood" }

function S:SetAccentColor(c)
    if not c then return end
    T.accent = c
    T.accentDim = Color3.fromRGB(
        floor(c.R * 255 * 0.55),
        floor(c.G * 255 * 0.55),
        floor(c.B * 255 * 0.55)
    )
    T.section = cLerp(c, T.textDim, 0.45)
end

function S:SetTheme(name)
    local th = self.THEMES[name]
    if not th then return end
    local function c(v)
        return Color3.fromRGB(v[1], v[2], v[3])
    end
    T.bg = c(th.bg)
    T.header = c(th.header)
    T.border = c(th.border)
    T.text = c(th.text)
    T.textDim = c(th.textDim)
    if th.label then T.label = c(th.label) end
    T.trackOff = c(th.trackOff)
    T.rowHover = c(th.rowHover)
    T.valueBox = c(th.valueBox)
    self:SetAccentColor(c(th.accent))
end

S.accH, S.accS, S.accV = 330, 57, 100
function S:ApplyAccentHSV()
    self:SetAccentColor(Color3.fromHSV(self.accH / 360, self.accS / 100, self.accV / 100))
end

function S:RefreshText()
    local sc = self.textScale or 1
    local font = self.font or (Drawing.Fonts and (Drawing.Fonts.UI or Drawing.Fonts.Monospace))
    for _, e in ipairs(allTexts) do
        if e.d then
            prop(e.d, "Font", font)
            prop(e.d, "Size", math.max(10, math.floor((e.s or 13) * sc + 0.5)))
            prop(e.d, "Outline", true)
            prop(e.d, "OutlineColor", Color3.fromRGB(0, 0, 0))
        end
    end
end

function S:SetFont(name)
    name = tostring(name or "UI")
    if not (self.FONTS and self.FONTS[name]) then name = "UI" end
    self.fontName = name
    self.font = self.FONTS[name]
    self:RefreshText()
end

function S:SetTextScale(scale)
    scale = math.clamp(tonumber(scale) or 1, 0.75, 1.75)
    self.textScale = scale
    local b = self._baseProp or { rowH = 36, pad = 18 }
    T.rowH = math.floor(b.rowH * scale + 0.5)
    T.pad = math.floor(b.pad * scale + 0.5)
    self:RefreshText()
    for _, w in ipairs(self.windows) do
        local baseW = w._baseW or w.w
        w._baseW = baseW
        w.w = math.floor(baseW * math.max(1, scale) + 0.5)
    end
end

function S:AutoScaleFromViewport()
    local _, vy = viewport()
    local scale = math.clamp((vy or 1080) / 1080, 0.9, 1.55)
    self:SetTextScale(scale)
    return scale
end

--------------------------------------------------------------------
-- Search typing
--------------------------------------------------------------------
S.TYPE_KEYS = {}
for vk = 0x41, 0x5A do S.TYPE_KEYS[vk] = string.char(vk + 32) end
for vk = 0x30, 0x39 do S.TYPE_KEYS[vk] = string.char(vk) end
S.TYPE_KEYS[0x20] = " "
S.TYPE_KEYS[0xBD] = "-"
S.TYPE_KEYS[0xBE] = "."
S.keyPrev = {}

local function pumpSearch()
    local wd = S.searchFocus
    if not wd or not wd.focus then return end
    local changed = false
    local function edge(vk)
        local down = S:KeyHeld(vk)
        local was = S.keyPrev[vk]
        S.keyPrev[vk] = down
        return down and not was
    end
    if edge(0x1B) or edge(0x0D) then
        wd.focus = false
        S.searchFocus = nil
        return
    end
    if edge(0x08) and #wd.text > 0 then
        wd.text = wd.text:sub(1, #wd.text - 1)
        changed = true
    end
    for vk, ch in pairs(S.TYPE_KEYS) do
        if edge(vk) and #wd.text < 24 then
            wd.text = wd.text .. ch
            changed = true
        end
    end
    if changed then
        wd.cache.v = nil
        if wd.cb then pcall(wd.cb, wd.text) end
    end
end

--------------------------------------------------------------------
-- Cursor (screen-space pointer aligned with hit-testing)
--------------------------------------------------------------------
S.curTri = mkTri(Color3.fromRGB(255, 255, 255))
S.curEdge = mkTri(Color3.fromRGB(10, 6, 12))
S.curDot = mkCircle(T.accent, 2.5, true)
S.curDot.NumSides = 12
local _sysCursorPrev = nil

local function setSystemCursor(hidden)
    if not S.hideSystemCursor then return end
    pcall(function()
        if hidden then
            if _sysCursorPrev == nil then
                _sysCursorPrev = UserInputService.MouseIconEnabled
            end
            UserInputService.MouseIconEnabled = false
        elseif _sysCursorPrev ~= nil then
            UserInputService.MouseIconEnabled = _sysCursorPrev
            _sysCursorPrev = nil
        end
    end)
end

local function drawCursor(vis)
    if not vis then
        S.curTri.Visible = false
        S.curEdge.Visible = false
        S.curDot.Visible = false
        setSystemCursor(false)
        return
    end
    setSystemCursor(true)
    local x, y = M.x, M.y
    -- arrow tip at mouse
    S.curEdge.PointA = Vector2.new(x, y)
    S.curEdge.PointB = Vector2.new(x + 14, y + 12)
    S.curEdge.PointC = Vector2.new(x + 5, y + 18)
    S.curEdge.Color = Color3.fromRGB(10, 6, 12)
    S.curEdge.ZIndex = 99998
    S.curEdge.Visible = true
    S.curTri.PointA = Vector2.new(x, y)
    S.curTri.PointB = Vector2.new(x + 12, y + 11)
    S.curTri.PointC = Vector2.new(x + 5, y + 16)
    S.curTri.Color = T.accent
    S.curTri.ZIndex = 99999
    S.curTri.Visible = true
    S.curDot.Position = Vector2.new(x, y)
    S.curDot.Color = Color3.fromRGB(255, 255, 255)
    S.curDot.ZIndex = 100000
    S.curDot.Visible = true
end

--------------------------------------------------------------------
-- Watermark (tuff name plate)
--------------------------------------------------------------------
S.wmShadow = mkText("", 22, Color3.fromRGB(8, 6, 10), false)
S.wmMain = mkText("", 22, T.accent, false)
S.wmSub = mkText("", 11, T.textDim, false)

local function drawWatermark(vis)
    if not vis or not S.showWatermark then
        S.wmShadow.Visible = false
        S.wmMain.Visible = false
        S.wmSub.Visible = false
        return
    end
    local name = tostring(S.watermark or "t3ti")
    local vx, vy = viewport()
    local x, y = 18, vy - 52
    setText(S.wmShadow, {}, "a", name)
    S.wmShadow.Size = 23
    S.wmShadow.Position = Vector2.new(x + 2, y + 2)
    S.wmShadow.Color = Color3.fromRGB(8, 6, 10)
    S.wmShadow.Transparency = 0.35
    S.wmShadow.ZIndex = 50
    S.wmShadow.Visible = true
    setText(S.wmMain, {}, "a", name)
    S.wmMain.Size = 22
    S.wmMain.Position = Vector2.new(x, y)
    S.wmMain.Color = T.accent
    S.wmMain.Transparency = 1
    S.wmMain.ZIndex = 51
    S.wmMain.Visible = true
    setText(S.wmSub, {}, "a", "T3ti UI")
    S.wmSub.Size = 11
    S.wmSub.Position = Vector2.new(x + 2, y + 24)
    S.wmSub.Color = T.label
    S.wmSub.Transparency = 0.85
    S.wmSub.ZIndex = 51
    S.wmSub.Visible = true
end

--------------------------------------------------------------------
-- Boot intro (once on script launch)
-- delay popup until 7.05s, shake+fade in, end at 12.001s then open UI
--------------------------------------------------------------------
S._booting = false
S.introDelay = 7.05 -- was 5.05; +2s more delay before popup
S.introEnd = 12.001 -- shift end with the delay so popup length stays similar

local function fetchPlaceIconPng()
    local placeId = game.PlaceId
    local ok, body = pcall(function()
        return game:HttpGet(
            "https://thumbnails.roblox.com/v1/places/gameicons?placeIds="
                .. tostring(placeId)
                .. "&returnPolicy=PlaceHolder&size=512x512&format=Png&isCircular=false"
        )
    end)
    if not ok or type(body) ~= "string" then return nil end
    local url = (body:match('"imageUrl":"(.-)"') or ""):gsub("\\/", "/")
    if url == "" then return nil end
    local ok2, data = pcall(function() return game:HttpGet(url) end)
    if ok2 and type(data) == "string" and #data > 100 then return data end
    return nil
end

local function loadIntroWav()
    if type(getcustomasset) ~= "function" then return nil end

    local function tryAsset(p)
        local ok, asset = pcall(function()
            if isfile and not isfile(p) then error("missing") end
            return getcustomasset(p)
        end)
        if ok and type(asset) == "string" and asset ~= "" then return asset end
        return nil
    end

    local function soundFromAsset(asset)
        local snd = Instance.new("Sound")
        snd.Name = "T3tiIntro"
        snd.SoundId = asset
        snd.Volume = 4
        snd.Parent = SoundService
        return snd
    end

    -- Prefer local workspace files
    local paths = {
        "untitled.wav",
        "t3ti_intro.wav",
        "t3ti-intro/untitled.wav",
        "t3ti-intro\\untitled.wav",
    }
    for _, p in ipairs(paths) do
        local asset = tryAsset(p)
        if asset then return soundFromAsset(asset) end
    end

    -- Pull from local MCP HTTP and cache into executor workspace
    if type(writefile) == "function" then
        local urls = {
            "http://127.0.0.1:16385/untitled.wav",
            "http://127.0.0.1:16384/t3ti-intro/untitled.wav",
        }
        for _, url in ipairs(urls) do
            local ok, data = pcall(function() return game:HttpGet(url) end)
            if ok and type(data) == "string" and #data > 1000 then
                local okw = pcall(function() writefile("t3ti_intro.wav", data) end)
                if okw then
                    local asset = tryAsset("t3ti_intro.wav")
                    if asset then return soundFromAsset(asset) end
                end
            end
        end
    end
    return nil
end

function S:PlayBootIntro(onDone)
    if self._booting then return end
    self._booting = true
    self.uiVisible = false

    local delayT = self.introDelay or 7.05
    local endT = self.introEnd or 12.001
    local png = fetchPlaceIconPng()
    local snd = loadIntroWav()

    local drawings = {}
    local function track(d)
        drawings[#drawings + 1] = d
        return d
    end
    local function mkSq(filled)
        local d = Drawing.new("Square")
        d.Filled = filled ~= false
        d.Thickness = filled == false and 3 or 0
        d.Visible = false
        d.ZIndex = 20000
        return track(d)
    end
    local function mkTx()
        local d = Drawing.new("Text")
        d.Center = true
        d.Outline = true
        d.OutlineColor = Color3.fromRGB(8, 4, 10)
        d.Visible = false
        d.ZIndex = 20020
        return track(d)
    end

    local dim = mkSq(true)
    dim.Color = Color3.fromRGB(0, 0, 0)
    dim.ZIndex = 19990

    local img = nil
    if png then
        img = Drawing.new("Image")
        pcall(function() img.Data = png end)
        img.Visible = false
        img.ZIndex = 20005
        track(img)
    end

    local ring = mkSq(false)
    ring.Color = T.accent
    local tShadow, tMain = mkTx(), mkTx()
    -- fat T sits ON the game icon (no subtitle)
    tMain.ZIndex = 20030
    tShadow.ZIndex = 20025

    local t0 = tick()
    local popped = false
    local finished = false
    local conn

    local function cleanup()
        if finished then return end
        finished = true
        if conn then pcall(function() conn:Disconnect() end) end
        for _, d in ipairs(drawings) do
            pcall(function() d:Remove() end)
        end
        if snd then
            pcall(function()
                snd:Stop()
                snd:Destroy()
            end)
        end
        self._booting = false
        -- skip reveal if we were destroyed / unloaded mid-intro
        if onDone and self.alive then pcall(onDone) end
    end

    if snd then
        pcall(function() snd:Play() end)
    end

    conn = RunService.RenderStepped:Connect(function()
        if not self.alive or finished then
            cleanup()
            return
        end
        local now = tick() - t0
        local vx, vy = viewport()
        local cx, cy = vx * 0.5, vy * 0.5

        -- soft dim during whole intro
        local dimA = 0.55
        if now < 0.4 then
            dimA = 0.55 * (now / 0.4)
        elseif now > endT - 0.55 then
            dimA = 0.55 * math.max(0, (endT - now) / 0.55)
        end
        dim.Position = Vector2.new(0, 0)
        dim.Size = Vector2.new(vx, vy)
        dim.Transparency = dimA
        dim.Visible = dimA > 0.01

        if now < delayT then
            -- delay: no logo yet
            if img then img.Visible = false end
            ring.Visible = false
            tShadow.Visible = false
            tMain.Visible = false
        else
            if not popped then popped = true end
            local localT = now - delayT
            -- fade in
            local fade = math.clamp(localT / 0.45, 0, 1)
            fade = fade * fade * (3 - 2 * fade)
            -- exit fade
            if now > endT - 0.55 then
                fade = fade * math.max(0, (endT - now) / 0.55)
            end
            -- scale punch
            local scale = 1
            if localT < 0.5 then
                local u = localT / 0.5
                scale = 0.62 + (1.14 - 0.62) * (u * u * (3 - 2 * u))
            elseif localT < 0.75 then
                scale = 1.14 - (localT - 0.5) / 0.25 * 0.14
            end
            -- shake (decays)
            local shakeAmp = 0
            if localT < 0.7 then
                shakeAmp = (1 - localT / 0.7) * 10
            end
            local sx = math.sin(localT * 62) * shakeAmp
            local sy = math.cos(localT * 51) * shakeAmp * 0.85

            local side = math.floor(210 * scale)
            local ix = cx - side / 2 + sx
            local iy = cy - side / 2 + sy
            local tcx = ix + side / 2
            local tcy = iy + side / 2

            if img then
                img.Size = Vector2.new(side, side)
                img.Position = Vector2.new(ix, iy)
                img.Transparency = fade
                img.Visible = fade > 0.02
            end

            ring.Size = Vector2.new(side + 16, side + 16)
            ring.Position = Vector2.new(ix - 8, iy - 8)
            ring.Transparency = fade * 0.95
            ring.Color = T.accent
            ring.Visible = fade > 0.02

            -- fat T centered on the game image
            local tSize = math.floor(side * 0.72)
            tShadow.Text = "T"
            tShadow.Size = tSize
            tShadow.Position = Vector2.new(tcx + 3, tcy + 3)
            tShadow.Color = Color3.fromRGB(10, 6, 12)
            tShadow.Transparency = fade * 0.8
            tShadow.Visible = fade > 0.02

            tMain.Text = "T"
            tMain.Size = tSize
            tMain.Position = Vector2.new(tcx, tcy)
            tMain.Color = T.accent
            tMain.Transparency = fade
            tMain.Visible = fade > 0.02
        end

        -- fade audio near end
        if snd and now > endT - 0.7 then
            pcall(function()
                snd.Volume = 4 * math.max(0, (endT - now) / 0.7)
            end)
        end

        if now >= endT then
            cleanup()
        end
    end)
end

--------------------------------------------------------------------
-- Main UI loop
--------------------------------------------------------------------
S.menuKey = 0xA3 -- RCtrl
S.uiVisible = true
local keyWas = false
local menuEdge = false

-- Reliable menu toggle via UIS (Potassium has no iskeypressed)
S:Connect(UserInputService.InputBegan, function(input, _gp)
    if not S.alive or S._booting then return end
    if S:IsMouseVk(S.menuKey) then return end
    local kc = S.VK_TO_KEYCODE[S.menuKey]
    if kc and input.KeyCode == kc then
        menuEdge = true
    end
end)

S:Connect(RunService.RenderStepped, function(dt)
    if not S.alive then return end
    DT = clamp(dt or (1 / 60), 1 / 240, 0.1)
    updateMouse()
    if S._booting then
        -- intro owns the screen; skip menu input/cursor
        return
    end
    pumpSearch()

    if S.rainbow then
        S.accH = (S.accH + (S.rainbowSpeed or 40) * dt) % 360
        S:ApplyAccentHSV()
    end

    local kd = S:KeyHeld(S.menuKey)
    local toggle = menuEdge or (kd and not keyWas)
    menuEdge = false
    if toggle then
        S.uiVisible = not S.uiVisible
        for _, w in ipairs(S.windows) do
            w.visible = S.uiVisible
        end
        S:PlayUI(S.uiVisible and "open" or "close")
    end
    keyWas = kd

    -- Haze / combat games lock mouse — unlock while menu is open so clicks work
    unlockMouseForMenu(S.uiVisible)

    local used = false
    if S.uiVisible then
        local order = {}
        for i, w in ipairs(S.windows) do order[i] = w end
        table.sort(order, function(a, b) return a.z > b.z end)
        for _, w in ipairs(order) do
            if not used then used = w:handleInput() end
        end
    end
    if not used then
        for _, p in ipairs(S.panels) do
            if not used then used = p:handleInput() end
        end
    end

    do
        local peak = 0
        for _, w in ipairs(S.windows) do
            if w.visible and (w.anim or 0) > peak then peak = w.anim end
        end
        S.dimAnim = approach(S.dimAnim, (S.dimOn and peak) or 0, 12)
        if S.dimAnim > 0.01 then
            local vx, vy = viewport()
            S.dimSq.Position = Vector2.new(0, 0)
            S.dimSq.Size = Vector2.new(vx, vy)
            S.dimSq.Transparency = S.dimAmt * S.dimAnim
            S.dimSq.ZIndex = 20
            S.dimSq.Visible = true
        else
            S.dimSq.Visible = false
        end
    end

    for _, w in ipairs(S.windows) do w:layout() end
    for _, p in ipairs(S.panels) do p:layout() end
    drawNotes()
    drawWatermark(true)
    drawCursor(S.showCursor and S.uiVisible)
end)

-- quiet boot — helper triggers intro + notify
return S
