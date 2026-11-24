-- OTEPZ UNIVERSAL AUTO-FARM v1.0
-- auto-click + auto-collect + ESP + auto-rejoin
-- Paste di executor. Copyright otepzkie.

-- Pecahan 1/4 : CONFIG + CORE UTILITIES

--[[ ================= CONFIG ================= ]]
local CFG = {
    VERSION          = "1.0",
    PREFIX           = "[OTEPZ]",
    THEME_MAIN       = Color3.fromRGB(0, 255, 140),
    THEME_BG         = Color3.fromRGB(15, 20, 15),
    THEME_TEXT       = Color3.fromRGB(200, 255, 220),

    AUTO_CLICK       = true,       -- master toggle
    CLICK_DELAY      = 0.05,       -- detik antar klik (anti-spam)
    CLICK_HUMANIZE   = true,       -- jitter biar mirip manusia

    AUTO_COLLECT     = true,       -- auto pickup drops/pet/coin
    COLLECT_RADIUS   = 500,        -- studs
    COLLECT_DELAY    = 0.3,

    AUTO_REJOIN      = true,       -- auto rejoin kalau kena kick/dc
    REJOIN_DELAY     = 10,

    -- Kumpulan RemoteEvent / RemoteFunction names umum
    -- (filter: nama remote yang biasanya dipake buat claim reward)
    REMOTE_PATTERNS  = {"collect", "claim", "pickup", "grab", "redeem", "buy", "tap"},
}

--[[ ================= CORE ================= ]]
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService= game:GetService("HttpService")
local Workspace  = game:GetService("Workspace")
local CoreGui    = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

local OTEPZ = {}
OTEPZ.CFG   = CFG
OTEPZ.IsRunning = false

-- Logging bergaya hacker terminal
function OTEPZ.Log(msg)
    print(CFG.PREFIX .. " " .. msg)
end

function OTEPZ.Warn(msg)
    warn(CFG.PREFIX .. " [WARN] " .. msg)
end

function OTEPZ.Err(msg)
    warn(CFG.PREFIX .. " [ERROR] " .. msg)
end

-- Humanize jitter (±15%)
function OTEPZ.HumanDelay(base)
    if CFG.CLICK_HUMANIZE then
        local jitter = math.random(-15, 15) / 100
        return base + (base * jitter)
    end
    return base
end

-- Cek apakah remote bernama cocok pattern collect/claim/dll
function OTEPZ.IsCollectRemote(name)
    local lower = string.lower(name or "")
    for _, pattern in ipairs(CFG.REMOTE_PATTERNS) do
        if string.find(lower, pattern) then
            return true
        end
    end
    return false
end

-- Ambil HumanoidRootPart aman
function OTEPZ.GetRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    return hrp
end

-- TP sederhana (guarded, anti rubberband)
function OTEPZ.TP(cf)
    local root = OTEPZ.GetRoot()
    if not root then return false end
    local ok, err = pcall(function()
        root.CFrame = cf
    end)
    if not ok then OTEPZ.Warn("TP failed: " .. tostring(err)) end
    return ok
end

-- Scan semua descendants cari Part bertulisan "Coin"/"Cash"/"Drop"/"Reward"
function OTEPZ.ScanCollectibles()
    local out = {}
    local keywords = {"coin","cash","drop","reward","money","gem","point","chest","orb","gift"}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") or obj:IsA("TouchTransmitter") then
            local parent = obj.Parent
            if parent then
                local name = string.lower(parent.Name)
                for _, kw in ipairs(keywords) do
                    if string.find(name, kw) then
                        table.insert(out, parent)
                        break
                    end
                end
            end
        end
    end
    return out
end

-- Kumpulkan RemoteEvent yang cocok pattern di ReplicatedStorage
function OTEPZ.ScanRemotes()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local out = {}
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            if OTEPZ.IsCollectRemote(obj.Name) then
                table.insert(out, obj)
            end
        end
    end
    return out
end

-- core inline
-- Pecahan 2/4 : CLICK ENGINE + ESP

--[[ ============ AUTO CLICK ENGINE ============ ]]
local ClickEngine = {}
ClickEngine.__index = ClickEngine

function ClickEngine.new()
    local self = setmetatable({}, ClickEngine)
    self.Active       = false
    self.Timer        = 0
    self.LastClick    = 0
    self.ClicksTotal  = 0
    self.CPS          = 0
    return self
end

function ClickEngine:Start()
    self.Active = true
    OTEPZ.Log("Click engine started")
end

function ClickEngine:Stop()
    self.Active = false
    OTEPZ.Log("Click engine stopped — total clicks: " .. self.ClicksTotal)
end

function ClickEngine:Update(dt)
    if not self.Active then return end
    self.Timer = self.Timer + dt
    local delay = OTEPZ.HumanDelay(OTEPZ.CFG.CLICK_DELAY)
    if self.Timer - self.LastClick >= delay then
        self:_FireClick()
        self.LastClick = self.Timer
        self.ClicksTotal = self.ClicksTotal + 1
    end
end

function ClickEngine:_FireClick()
    -- Cek apakah ada GUI button yang aktif (interactable)
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if not gui then return end
    -- Pattern umum: Interact / Click / Tap button
    local btns = {
        gui:FindFirstChild("ClickButton", true),
        gui:FindFirstChild("InteractButton", true),
        gui:FindFirstChild("TapButton", true),
        gui:FindFirstChild("CollectButton", true),
    }
    for _, btn in ipairs(btns) do
        if btn and btn:IsA("TextButton") or btn:IsA("ImageButton") then
            pcall(function()
                if btn:IsA("TextButton") then
                    firesignal(btn.MouseButton1Click)
                elseif btn:IsA("ImageButton") then
                    firesignal(btn.MouseButton1Click)
                end
            end)
        end
    end
end

--[[ ============ AUTO COLLECT ENGINE ============ ]]
local CollectEngine = {}
CollectEngine.__index = CollectEngine

function CollectEngine.new()
    local self = setmetatable({}, CollectEngine)
    self.Active        = false
    self.Timer         = 0
    self.LastCollect   = 0
    self.ItemsTotal    = 0
    return self
end

function CollectEngine:Start()
    self.Active = true
    OTEPZ.Log("Collect engine started (radius: " .. OTEPZ.CFG.COLLECT_RADIUS .. ")")
end

function CollectEngine:Stop()
    self.Active = false
    OTEPZ.Log("Collect stopped — items grabbed: " .. self.ItemsTotal)
end

function CollectEngine:Update(dt)
    if not self.Active then return end
    self.Timer = self.Timer + dt
    if self.Timer - self.LastCollect < OTEPZ.CFG.COLLECT_DELAY then return end

    local root = OTEPZ.GetRoot()
    if not root then return end

    local items = OTEPZ.ScanCollectibles()
    for _, item in ipairs(items) do
        local pos = item:IsA("Model") and (item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart"))
        if not pos then pos = item:IsA("BasePart") and item end
        if pos then
            local dist = (root.Position - pos.Position).Magnitude
            if dist <= OTEPZ.CFG.COLLECT_RADIUS then
                pcall(function()
                    if item:IsA("Model") and item.PrimaryPart then
                        item:SetPrimaryPartCFrame(root.CFrame * CFrame.new(0,0,-2))
                    elseif item:IsA("BasePart") then
                        -- Fire TouchTransmitter kalau ada
                        local touch = item:FindFirstChildOfClass("TouchTransmitter")
                        if touch then
                            firetouchinterest(root, item, 0)
                        end
                    end
                end)
                self.ItemsTotal = self.ItemsTotal + 1
            end
        end
    end
    self.LastCollect = self.Timer
end

--[[ ============ SIMPLE ESP ============ ]]
local ESP = {}
ESP.__index = ESP

function ESP.new()
    local self = setmetatable({}, ESP)
    self.Highlights = {}
    return self
end

function ESP:AddTarget(obj)
    if not obj then return end
    if self.Highlights[obj] then return end
    local hl = Instance.new("Highlight")
    hl.FillColor    = OTEPZ.CFG.THEME_MAIN
    hl.FillTransparency = 0.3
    hl.OutlineColor = Color3.new(1, 1, 1)
    hl.Parent = obj
    self.Highlights[obj] = hl
end

function ESP:Clear()
    for obj, hl in pairs(self.Highlights) do
        pcall(function() hl:Destroy() end)
    end
    self.Highlights = {}
end

function ESP:ScanAndTag()
    -- Tag NPC/enemy terdekat dengan Highlight
    local root = OTEPZ.GetRoot()
    if not root then return end
    -- Cari model dengan Humanoid (enemy/NPC/mob)
    for _, char in ipairs(Players:GetPlayers()) do
        if char ~= LocalPlayer then
            local hrp = char.Character and char.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local dist = (root.Position - hrp.Position).Magnitude
                if dist < 150 then
                    self:AddTarget(char.Character)
                end
            end
        end
    end
    -- Juga cari NPC humanoid di Workspace
    for _, npc in ipairs(Workspace:GetDescendants()) do
        if npc:FindFirstChild("HumanoidRootPart") and not Players:GetPlayerFromCharacter(npc) then
            local hrp = npc.HumanoidRootPart
            if (root.Position - hrp.Position).Magnitude < 150 then
                self:AddTarget(npc)
            end
        end
    end
end
-- Pecahan 3/4 : GUI HACKER-STYLE
local CFG = OTEPZ.CFG

local GUI = {}
GUI.__index = GUI

function GUI.new()
    local self = setmetatable({}, GUI)
    self.ScreenGui = nil
    self.Buttons = {}
    self.StatusLabel = nil
    self:Build()
    return self
end

function GUI:Build()
    local old = pcall(function()
        if CoreGui:FindFirstChild("OTEPZ_GUI") then
            CoreGui:FindFirstChild("OTEPZ_GUI"):Destroy()
        end
    end)

    local gui = Instance.new("ScreenGui")
    gui.Name = "OTEPZ_GUI"
    gui.ResetOnSpawn = false
    pcall(function()
        gui.Parent = CoreGui
    end)
    if not gui.Parent then
        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end

    -- Main frame
    local frame = Instance.new("Frame")
    frame.Name = "Main"
    frame.Size = UDim2.new(0, 240, 0, 320)
    frame.Position = UDim2.new(0, 20, 0, 150)
    frame.BackgroundColor3 = CFG.THEME_BG
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    -- Title bar
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 32)
    title.BackgroundTransparency = 1
    title.Text = "⚡ OTEPZ AUTO-FARM v" .. CFG.VERSION
    title.TextColor3 = CFG.THEME_MAIN
    title.Font = Enum.Font.Code
    title.TextSize = 14
    title.Parent = frame

    -- Status label
    local status = Instance.new("TextLabel")
    status.Name = "Status"
    status.Size = UDim2.new(1, -16, 0, 22)
    status.Position = UDim2.new(0, 8, 0, 34)
    status.BackgroundColor3 = Color3.fromRGB(10, 15, 10)
    status.TextColor3 = CFG.THEME_TEXT
    status.Font = Enum.Font.Code
    status.TextSize = 11
    status.Text = "[IDLE] Semua off"
    status.Parent = frame

    local statusCorner = Instance.new("UICorner")
    statusCorner.CornerRadius = UDim.new(0, 5)
    statusCorner.Parent = status

    self.StatusLabel = status

    -- Buttons
    local btnData = {
        {name = "Auto Click",    key = "AUTO_CLICK"},
        {name = "Auto Collect",  key = "AUTO_COLLECT"},
        {name = "Auto Rejoin",   key = "AUTO_REJOIN"},
    }

    local y = 62
    for _, data in ipairs(btnData) do
        local btn = Instance.new("TextButton")
        btn.Name = data.name
        btn.Size = UDim2.new(1, -16, 0, 34)
        btn.Position = UDim2.new(0, 8, 0, y)
        btn.BackgroundColor3 = Color3.fromRGB(25, 35, 25)
        btn.TextColor3 = CFG.THEME_TEXT
        btn.Font = Enum.Font.Code
        btn.TextSize = 13
        btn.Text = "  ▶ " .. data.name .. " [OFF]"
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Parent = frame

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 5)
        c.Parent = btn

        btn.MouseButton1Click:Connect(function()
            CFG[data.key] = not CFG[data.key]
            local on = CFG[data.key]
            btn.Text = (on and "  ■ " or "  ▶ ") .. data.name .. (on and " [ON]" or " [OFF]")
            btn.BackgroundColor3 = on and Color3.fromRGB(30, 70, 40) or Color3.fromRGB(25, 35, 25)
            self:UpdateStatus()
        end)

        self.Buttons[data.key] = btn
        y = y + 42
    end

    -- Close / Kill button
    local killBtn = Instance.new("TextButton")
    killBtn.Name = "Kill"
    killBtn.Size = UDim2.new(1, -16, 0, 30)
    killBtn.Position = UDim2.new(0, 8, 0, y + 6)
    killBtn.BackgroundColor3 = Color3.fromRGB(70, 25, 25)
    killBtn.TextColor3 = Color3.fromRGB(255, 120, 120)
    killBtn.Font = Enum.Font.Code
    killBtn.TextSize = 12
    killBtn.Text = "  ✕ KILL SCRIPT"
    killBtn.TextXAlignment = Enum.TextXAlignment.Left
    killBtn.Parent = frame

    local kc = Instance.new("UICorner")
    kc.CornerRadius = UDim.new(0, 5)
    kc.Parent = killBtn

    killBtn.MouseButton1Click:Connect(function()
        OTEPZ.IsRunning = false
        OTEPZ.Log("Script killed by user")
        gui:Destroy()
    end)

    self.ScreenGui = gui
    OTEPZ.Log("GUI built — theme: hacker green")
end

function GUI:UpdateStatus()
    if not self.StatusLabel then return end
    local parts = {}
    if CFG.AUTO_CLICK   then table.insert(parts, "CLICK") end
    if CFG.AUTO_COLLECT then table.insert(parts, "COLLECT") end
    if CFG.AUTO_REJOIN  then table.insert(parts, "REJOIN") end
    local txt = "⚡ ACTIVE: " .. (#parts > 0 and table.concat(parts, " + ") or "IDLE")
    self.StatusLabel.Text = txt
    OTEPZ.Log("Status: " .. txt)
end

-- Pecahan 4/4 : MAIN LOOP + AUTO REJOIN + BOOTSTRAP

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
 -- placeholder, diganti saat merge
local CFG   = OTEPZ.CFG

--[[ ============ AUTO REJOIN ============ ]]
local function SetupRejoin()
    Players.LocalPlayer.OnTeleport:Connect(function(state)
        if state == Enum.TeleportState.Failed and CFG.AUTO_REJOIN then
            OTEPZ.Log("Teleport failed, rejoin dalam " .. CFG.REJOIN_DELAY .. "s...")
            task.wait(CFG.REJOIN_DELAY)
            pcall(function()
                game:GetService("TeleportService"):Teleport(game.PlaceId, Players.LocalPlayer)
            end)
        end
    end)
    OTEPZ.Log("Auto-rejoin armed")
end

--[[ ============ MAIN LOOP ============ ]]
local ClickEngine, CollectEngine, ESP
local function Run()
    OTEPZ.IsRunning = true
    SetupRejoin()

    -- Inisialisasi engine (dari part2)
    ClickEngine  = OTEPZ.ClickEngine.new()
    CollectEngine = OTEPZ.CollectEngine.new()
    ESP          = OTEPZ.ESP.new()

    ClickEngine:Start()
    CollectEngine:Start()

    local ESPTimer = 0
    local startTime = os.clock()

    RunService.Heartbeat:Connect(function(dt)
        if not OTEPZ.IsRunning then return end
        pcall(function()
            if CFG.AUTO_CLICK then
                ClickEngine:Update(dt)
            end
            if CFG.AUTO_COLLECT then
                CollectEngine:Update(dt)
            end
            -- ESP refresh tiap 2 detik
            ESPTimer = ESPTimer + dt
            if ESPTimer >= 2 then
                ESP:Clear()
                ESP:ScanAndTag()
                ESPTimer = 0
            end
        end)
    end)

    -- Stats updater tiap 5 detik
    task.spawn(function()
        while OTEPZ.IsRunning do
            task.wait(5)
            local elapsed = os.clock() - startTime
            local cps = elapsed > 0 and math.floor(ClickEngine.ClicksTotal / elapsed) or 0
            OTEPZ.Log(string.format(
                "STATS | clicks=%d cps=%d items=%d uptime=%ds",
                ClickEngine.ClicksTotal, cps, CollectEngine.ItemsTotal, math.floor(elapsed)
            ))
        end
    end)

    OTEPZ.Log("=== ALL SYSTEMS ONLINE ===")
end

Run()