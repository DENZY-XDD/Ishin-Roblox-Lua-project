--[[
    ═════════════════════════════════════════════════════════════════
    ⚡ AUTO WEAVE ULTIMATE (v3.0) ⚡
    Universal Combat Dodge & Auto Weave for Roblox Executors
    Optimized for Ishin, Untitled Boxing Game, Combat Warriors & More
    ═════════════════════════════════════════════════════════════════
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Stats = game:GetService("Stats")
local VirtualInputManager = nil
pcall(function() VirtualInputManager = game:GetService("VirtualInputManager") end)

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Global Singleton Check & Comprehensive Teardown of Previous Instances
if getgenv and getgenv().AutoWeaveLoaded then
    if typeof(getgenv().AutoWeaveUnload) == "function" then
        pcall(getgenv().AutoWeaveUnload)
    end
end

-- Forcefully purge any dangling AnimationPlayed connections left by earlier instances
if typeof(getconnections) == "function" then
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character then
            local hum = plr.Character:FindFirstChildOfClass("Humanoid")
            local anim = hum and hum:FindFirstChildOfClass("Animator")
            if anim then
                pcall(function()
                    for _, c in ipairs(getconnections(anim.AnimationPlayed)) do
                        pcall(function() c:Disconnect() end)
                        pcall(function() c:Disable() end)
                    end
                end)
            end
        end
    end
end

pcall(function()
    game:GetService("ContextActionService"):UnbindAction("AutoWeaveHalt")
end)

local scriptConnections = {}
local function trackConn(conn)
    if conn then table.insert(scriptConnections, conn) end
    return conn
end

----------------------------------------------------------------
-- CONFIGURATION & DEFAULT SETTINGS
----------------------------------------------------------------
local CONFIG = {
    AttackKeywords = {
        "punch", "m1", "m2", "attack", "swing", "jab", "hook", "uppercut",
        "slash", "strike", "kick", "heavy", "light", "combo", "bash",
        "slam", "stab", "rush", "hit", "crit", "critical", "lunge", "swing1", "swing2"
    },
    IgnoreKeywords = {
        "idle", "walk", "run", "sprint", "jump", "fall", "land", "emote",
        "pose", "dance", "sit", "cheer", "wave", "equip", "unequip",
        "holster", "draw", "stance", "block", "guard", "breathe", "turn",
        "style", "sheath", "unsheath", "switch", "change", "inspect", "select"
    },
    HitboxKeywords = {
        "hitbox", "hit_box", "hurtbox", "damage", "weaponhitbox", "melee"
    },
}

local state = {
    Enabled = true,
    TriggerMode = "Right Click", -- "Right Click" (Ishin), "Space" (UBG), "Q (Dodge)", "Velocity Dash"
    WeaveDirection = "Adaptive",  -- "Adaptive" (smooth movement), "None", "Random", "Left", "Right", "Back", "Front"
    Percent = 100,               -- Weave success chance (0-100%)
    Range = 14,                  -- Detection range in studs
    Delay = 0.10,                -- Fallback reaction delay in seconds
    PingComp = true,             -- Latency compensation
    FacingCheck = true,          -- Only weave if attacker faces you
    FacingDot = 0.1,             -- Facing threshold (-1 to 1)
    Cooldown = 0.45,             -- Minimum seconds between weaves
    WeaveSpeed = 55,             -- BodyVelocity speed fallback
    WeaveTime = 0.18,            -- BodyVelocity duration
    
    -- Movement Compensation Engine
    MovementComp = true,         -- Movement Compensation: Micro-halt so weave can execute cleanly
    CompHaltDuration = 0.05,     -- Duration (seconds) to micro-halt (default 0.05s / 50ms)
    
    -- Critical Dash Avoidance
    DashAwayFromCrit = true,      -- Toggle: Dash away from Critical / Heavy attacks
    DodgeKey = Enum.KeyCode.Q,    -- In-game Dodge key in Ishin
    CritDashSpeed = 55,           -- Velocity speed when dashing away from crits
    CritDashDuration = 0.26,      -- Duration of the critical dash impulse
    
    -- Yen & Economy Hub
    AutoJobPrompts = true,        -- Auto-trigger nearby job & restock prompts instantly
    YenEspEnabled = true,         -- Visual 3D markers for all Yen hubs
    
    -- Player Combat ESP Engine
    PlayerEsp = true,             -- Master toggle: Show Player ESP
    EspMaxDistance = 120,         -- Maximum render distance in studs
    EspShowName = true,           -- Toggle: Show player display name
    EspShowHealth = true,         -- Toggle: Show dynamic health bar and HP
    EspShowDistance = true,       -- Toggle: Show distance in studs / meters
    EspShowStyle = true,          -- Toggle: Show detected fighting style
    EspShowCrit = true,           -- Toggle: Show critical attack cooldown status
    
    -- Fallback Block & Combo Guard Engine
    FallbackBlock = true,        -- Toggle: If a weave is missed or on cooldown, block instead!
    SmartComboBlock = true,      -- Toggle: Auto-block hits 2 & 3 if first weave was missed
    WeaveComboEnder = true,      -- Toggle: Always weave the 4th combo hit (M1-4) or critical ender
    BlockKey = Enum.KeyCode.F,   -- Block / Guard key in Ishin
    BlockDuration = 0.32,        -- Duration per block hit
    MaxBlockedHits = 2,          -- Release block after absorbing 2 hits
    BlockTimeout = 0.70,         -- Release block if no hits within 0.7 seconds
    GuardBreakPrevent = true,    -- Release block if 1 hit away from guard break / never block criticals
    
    -- Style-Specific Delays
    SmartStyleDelay = true,
    StyleDelays = {
        Boxing = 0.03,           -- Fast punches, near-instant weave
        Karate = 0.08,           -- Snappy strikes & kicks
        Default = 0.12,          -- Standard street brawler timing
        InjuredCrutches = 0.14,  -- Crutches style
        Wrestling = 0.18,        -- Heavy grapples & strikes
        Kendo = 0.22,            -- Weapon swings, longer startup
        Critical = 0.26,         -- Heavy / critical charge attacks
    },
    
    -- Visuals
    ShowCircle = true,
    ShowHitboxes = false,
    ShowHealth = true,
    CircleColor = Color3.fromRGB(124, 92, 255),
    RingThickness = 0.6,
    FillOpacity = 0.85,
    
    -- Keybinds
    ToggleKey = Enum.KeyCode.G,
    HideKey = Enum.KeyCode.RightShift,
}

----------------------------------------------------------------
-- RUNTIME STATE
----------------------------------------------------------------
local lastWeaveTime = 0
local flashUntil = 0
local weaveCount = 0
local lastAnimText = "Waiting for combat..."
local lastAttackerName = "None"
local onWeaveCallback = function() end
local onAnimCallback = function() end

----------------------------------------------------------------
-- HELPER FUNCTIONS
----------------------------------------------------------------
local function getPing()
    local ping = 40
    pcall(function()
        local perf = Stats.Network.ServerStatsItem["Data Ping"]
        if perf then
            ping = perf:GetValue()
        end
    end)
    return ping
end

local function isFacingTarget(enemyHrp, myHrp, threshold)
    if not enemyHrp or not myHrp then return true end
    local dist = (myHrp.Position - enemyHrp.Position).Magnitude
    -- In close melee quarters (within 8 studs), attacks connect regardless of HRP angle or character clipping
    if dist <= 8.0 then
        return true
    end
    
    -- Horizontal 2D planar dot product (ignore vertical elevation differences / jumps)
    local enemyPos = Vector3.new(enemyHrp.Position.X, 0, enemyHrp.Position.Z)
    local myPos = Vector3.new(myHrp.Position.X, 0, myHrp.Position.Z)
    local toMe = (myPos - enemyPos)
    if toMe.Magnitude < 0.001 then return true end
    
    local look = enemyHrp.CFrame.LookVector
    local lookPlanar = Vector3.new(look.X, 0, look.Z)
    if lookPlanar.Magnitude < 0.001 then return true end
    
    local dot = lookPlanar.Unit:Dot(toMe.Unit)
    return dot >= -0.25
end

----------------------------------------------------------------
-- INPUT EMULATION ENGINE (VirtualInputManager + Fallbacks)
----------------------------------------------------------------
local function sendMouseButton2(isDown)
    local cx = Camera and Camera.ViewportSize.X / 2 or 500
    local cy = Camera and Camera.ViewportSize.Y / 2 or 400
    
    if VirtualInputManager then
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(cx, cy, 1, isDown, game, 1)
        end)
    end
    
    if isDown then
        if typeof(mouse2press) == "function" then
            pcall(mouse2press)
        elseif typeof(mouse2click) == "function" then
            pcall(mouse2click)
        end
    else
        if typeof(mouse2release) == "function" then
            pcall(mouse2release)
        end
    end
end

local VK_MAP = {
    [Enum.KeyCode.F] = 0x46,
    [Enum.KeyCode.Q] = 0x51,
    [Enum.KeyCode.W] = 0x57,
    [Enum.KeyCode.A] = 0x41,
    [Enum.KeyCode.S] = 0x53,
    [Enum.KeyCode.D] = 0x44,
    [Enum.KeyCode.Space] = 0x20,
    [Enum.KeyCode.G] = 0x47,
}

local function sendKey(keyCode, isDown)
    if VirtualInputManager then
        pcall(function()
            VirtualInputManager:SendKeyEvent(isDown, keyCode, false, game)
        end)
    end
    
    local vk = VK_MAP[keyCode]
    if vk and typeof(keypress) == "function" and typeof(keyrelease) == "function" then
        pcall(function()
            if isDown then
                keypress(vk)
            else
                keyrelease(vk)
            end
        end)
    end
end

----------------------------------------------------------------
-- AUTO-BLOCK / FALLBACK GUARD & POSTURE DEFENSE ENGINE
----------------------------------------------------------------
local isBlocking = false
local blockReleaseThread = nil
local blockedHitsCount = 0
local lastBlockHitTime = 0
local lastGuardDropTime = 0
local lastPlayerAttackTime = 0
local blockStartTime = 0

local function stopBlock(reason)
    if blockReleaseThread then
        task.cancel(blockReleaseThread)
        blockReleaseThread = nil
    end

    if isBlocking then
        isBlocking = false
        lastGuardDropTime = os.clock()
        blockStartTime = 0
        
        -- Force unconditional key release
        sendKey(state.BlockKey, false)
        if VirtualInputManager then
            pcall(function()
                VirtualInputManager:SendKeyEvent(false, state.BlockKey, false, game)
            end)
        end
        local vk = VK_MAP[state.BlockKey] or 0x46
        if typeof(keyrelease) == "function" then
            pcall(function() keyrelease(vk) end)
            pcall(function() keyrelease(state.BlockKey.Value) end)
        end
        
        if reason then
            lastAnimText = "[GUARD DROP] " .. reason
            onAnimCallback(lastAnimText)
        end
    else
        -- Redundant failsafe in case key got held externally or desynced
        pcall(function()
            if VirtualInputManager then
                VirtualInputManager:SendKeyEvent(false, state.BlockKey, false, game)
            end
            if typeof(keyrelease) == "function" then
                keyrelease(0x46)
            end
        end)
    end
end

local function onPlayerAttackInput()
    lastPlayerAttackTime = os.clock()
    if isBlocking then
        stopBlock("Player Attack (M1/M2 Priority)")
    end
end

local function performBlock(duration, isIncomingAttack)
    if not state.Enabled then return end
    if not state.FallbackBlock and not state.SmartComboBlock then return end
    
    local now = os.clock()
    
    -- PRIORITY 2: Player M1/M2 attacks supersede Block!
    -- If player clicked M1/M2 or is actively attacking (within 0.40s), NEVER block!
    if (now - lastPlayerAttackTime) < 0.40 then
        if isBlocking then
            stopBlock("Player Attacking (M1/M2 Priority)")
        end
        return
    end

    -- Guard Cooldown: Don't instantly re-raise block within 0.20s of dropping it
    if not isBlocking and (now - lastGuardDropTime) < 0.20 then
        return
    end
    
    -- Inactivity reset: If more than 0.7s passed since last hit, reset block count
    if (now - lastBlockHitTime) > (state.BlockTimeout or 0.7) then
        blockedHitsCount = 0
    end
    
    -- Guard Break Prevention:
    -- If we've already blocked 2 hits within the combo, guard is 1 hit away from shattering!
    -- Refuse to block and drop guard immediately so posture can recover!
    if state.GuardBreakPrevent and blockedHitsCount >= (state.MaxBlockedHits or 2) then
        stopBlock("1 Hit from Guard Break -> Dropped Guard!")
        return
    end
    
    if isIncomingAttack then
        blockedHitsCount += 1
        lastBlockHitTime = now
        
        -- If we just reached the max blocked hits (e.g. 2 hits), absorb this hit and drop!
        if blockedHitsCount >= (state.MaxBlockedHits or 2) then
            isBlocking = true
            blockStartTime = now
            sendKey(state.BlockKey, true)
            if blockReleaseThread then
                task.cancel(blockReleaseThread)
            end
            blockReleaseThread = task.delay(0.18, function()
                stopBlock("Blocked 2 Hits -> Guard Dropped (Anti-Break)")
            end)
            return
        end
    end
    
    lastBlockHitTime = now
    local dur = math.min(duration or state.BlockDuration or 0.32, state.BlockTimeout or 0.7)
    
    if not isBlocking then
        isBlocking = true
        blockStartTime = now
        sendKey(state.BlockKey, true)
    else
        -- If already blocking and total time from start exceeds max timeout, drop guard immediately!
        if (now - blockStartTime) >= (state.BlockTimeout or 0.7) then
            stopBlock("Max Block Duration (0.7s)")
            return
        end
    end
    
    if blockReleaseThread then
        task.cancel(blockReleaseThread)
        blockReleaseThread = nil
    end
    
    -- Auto-release after dur (capped at 0.7s inactivity timeout)
    blockReleaseThread = task.delay(dur, function()
        stopBlock("No Hits for 0.7s (Timeout)")
    end)
end

local isScriptSimulatingInput = false

local function triggerWeaveInput()
    local mode = state.TriggerMode
    isScriptSimulatingInput = true
    
    if mode == "Right Click" then
        sendMouseButton2(true)
        task.delay(0.055, function()
            sendMouseButton2(false)
            isScriptSimulatingInput = false
        end)
    elseif mode == "Space" then
        sendKey(Enum.KeyCode.Space, true)
        task.delay(0.055, function()
            sendKey(Enum.KeyCode.Space, false)
            isScriptSimulatingInput = false
        end)
    elseif mode == "Q (Dodge)" then
        sendKey(Enum.KeyCode.Q, true)
        task.delay(0.055, function()
            sendKey(Enum.KeyCode.Q, false)
            isScriptSimulatingInput = false
        end)
    else
        isScriptSimulatingInput = false
    end
end

----------------------------------------------------------------
-- MOVEMENT COMPENSATION ENGINE (Safe Micro-Anchor Stop-to-Weave)
----------------------------------------------------------------
local isMicroAnchored = false
local anchorStartTime = 0

local function isPlayerMoving()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.MoveDirection.Magnitude > 0.05 then
        return true
    end
    if hrp then
        local horizVel = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
        if horizVel.Magnitude > 0.8 then
            return true
        end
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.W) 
        or UserInputService:IsKeyDown(Enum.KeyCode.A) 
        or UserInputService:IsKeyDown(Enum.KeyCode.S) 
        or UserInputService:IsKeyDown(Enum.KeyCode.D) then
        return true
    end
    return false
end

local function applyMovementComp(duration)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    -- Cut horizontal momentum
    hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
    hrp.AssemblyAngularVelocity = Vector3.zero
    
    -- Safe micro-anchor: halts character for 0.05s so Right Click triggers sway
    isMicroAnchored = true
    anchorStartTime = os.clock()
    hrp.Anchored = true
    
    local dur = math.clamp(duration or state.CompHaltDuration or 0.05, 0.03, 0.10)
    task.delay(dur, function()
        if isMicroAnchored and hrp.Parent then
            hrp.Anchored = false
            isMicroAnchored = false
        end
    end)
end

local function releaseMovementComp()
    isMicroAnchored = false
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        pcall(function() hrp.Anchored = false end)
    end
end

----------------------------------------------------------------
-- EXECUTE WEAVE (Movement-Preserving Adaptive Engine)
----------------------------------------------------------------
local function performWeave(attackerRoot)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not attackerRoot then return false end
    
    local now = os.clock()
    if now - lastWeaveTime < state.Cooldown then
        -- Weave on cooldown: fallback to block ONLY IF player is not actively attacking
        if state.FallbackBlock and (now - lastPlayerAttackTime >= 0.35) then
            performBlock(0.32, false)
        end
        return false
    end
    
    -- PRIORITY 1: Weaving supersedes Block! Drop guard immediately so dodge executes cleanly!
    stopBlock("Weave Priority 1 (Dodge)")
    
    lastWeaveTime = now
    flashUntil = now + 0.3
    weaveCount += 1
    onWeaveCallback()
    
    local playerMoving = isPlayerMoving()
    
    -- MOVEMENT COMPENSATION:
    -- If player is moving and MovementComp is enabled, micro-halt the player so Right Click triggers the sway/weave!
    if state.MovementComp and playerMoving then
        applyMovementComp(state.CompHaltDuration or 0.05)
        lastAnimText = "[MOVEMENT COMP] Halted -> Weaving!"
        onAnimCallback(lastAnimText)
    end
    
    -- In Ishin, if MovementComp halted the player to weave stationary, do NOT inject strafe keys!
    -- Only inject strafe keys if MovementComp is OFF or player explicitly selected directional strafing without comp
    local strafeKey = nil
    if not (state.MovementComp and playerMoving) and state.TriggerMode ~= "Velocity Dash" then
        local holdingA = UserInputService:IsKeyDown(Enum.KeyCode.A)
        local holdingD = UserInputService:IsKeyDown(Enum.KeyCode.D)
        local dir = state.WeaveDirection
        
        if not holdingA and not holdingD then
            if dir == "Left" then
                strafeKey = Enum.KeyCode.A
            elseif dir == "Right" then
                strafeKey = Enum.KeyCode.D
            elseif dir == "Back" then
                strafeKey = Enum.KeyCode.S
            elseif dir == "Front" then
                strafeKey = Enum.KeyCode.W
            elseif dir == "Random" then
                strafeKey = (math.random(1, 2) == 1) and Enum.KeyCode.A or Enum.KeyCode.D
            end
        end
    end
    
    if strafeKey then
        sendKey(strafeKey, true)
    end
    
    -- Trigger in-game weave
    if state.TriggerMode == "Velocity Dash" then
        local dir = state.WeaveDirection
        local right = attackerRoot.CFrame.RightVector
        right = Vector3.new(right.X, 0, right.Z).Unit
        local sign = (dir == "Left" and -1) or (dir == "Right" and 1) or (math.random(1, 2) == 1 and 1 or -1)
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(1e6, 0, 1e6)
        bv.Velocity = right * sign * state.WeaveSpeed
        bv.Parent = hrp
        Debris:AddItem(bv, state.WeaveTime)
    else
        triggerWeaveInput()
    end
    
    if strafeKey then
        task.delay(0.06, function()
            sendKey(strafeKey, false)
        end)
    end
    return true
end

----------------------------------------------------------------
-- CRITICAL ATTACK DASH-AWAY ENGINE
----------------------------------------------------------------
local dodgeTrack = nil
local cachedAnimator = nil

local function playDodgeAnimation(humanoid)
    if not humanoid then return end
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return end

    if cachedAnimator ~= animator or not dodgeTrack or not dodgeTrack.Parent then
        cachedAnimator = animator
        local animObj = Instance.new("Animation")
        animObj.AnimationId = "rbxassetid://133535547421315" -- Ishin native DodgeBackward
        local ok, track = pcall(function()
            return animator:LoadAnimation(animObj)
        end)
        if ok and track then
            track.Priority = Enum.AnimationPriority.Action4
            dodgeTrack = track
        else
            dodgeTrack = nil
        end
    end

    if dodgeTrack then
        pcall(function()
            dodgeTrack:Stop(0.02)
            dodgeTrack:Play(0.04, 1, 1.15)
        end)
    end
end

local function performCritDash(attackerRoot)
    local char = LocalPlayer.Character
    local myHrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not myHrp or not attackerRoot then return false end

    -- Always drop block first so posture is not broken
    stopBlock("Crit Dodge (Dash Away)")

    -- Compute horizontal vector directly away from attacker
    local away = (myHrp.Position - attackerRoot.Position)
    local awayDir = Vector3.new(away.X, 0, away.Z)
    if awayDir.Magnitude < 0.01 then
        local look = myHrp.CFrame.LookVector
        awayDir = -Vector3.new(look.X, 0, look.Z)
    end
    awayDir = awayDir.Unit

    -- 1. Visually execute Ishin's authentic native dodge roll animation
    playDodgeAnimation(hum)

    -- 2. Dispatch in-game Dodge key (Q in Ishin)
    local dodgeKey = state.DodgeKey or Enum.KeyCode.Q
    sendKey(dodgeKey, true)
    task.delay(0.06, function()
        sendKey(dodgeKey, false)
    end)

    -- 3. Apply smooth backward dash impulse away from attacker's heavy strike hitbox
    local bv = Instance.new("BodyVelocity")
    bv.MaxForce = Vector3.new(3e5, 0, 3e5)
    bv.Velocity = awayDir * (state.CritDashSpeed or 55)
    bv.Parent = myHrp
    Debris:AddItem(bv, state.CritDashDuration or 0.26)

    lastWeaveTime = os.clock()
    flashUntil = os.clock() + 0.35
    weaveCount += 1
    onWeaveCallback()

    lastAnimText = "[CRIT AVOID] Dashed Away (" .. tostring(math.floor(state.CritDashSpeed or 55)) .. " studs/s)"
    onAnimCallback(lastAnimText)
    return true
end

----------------------------------------------------------------
-- ISHIN ANIMATION ID DATABASE (Whitelisted Attacks & Blacklisted Non-Attacks)
----------------------------------------------------------------
-- All 63 Ishin style attacks mapped by AnimationId
local ISHIN_ATTACKS_BY_ID = {
    -- Boxing
    ["137310197834317"] = { style = "Boxing", name = "BoxingPunch1", delay = 0.14 },
    ["81018814153053"]  = { style = "Boxing", name = "BoxingPunch2", delay = 0.14 },
    ["136727367324331"] = { style = "Boxing", name = "BoxingPunch3", delay = 0.14 },
    ["139555106880218"] = { style = "Boxing", name = "BoxingPunch4", delay = 0.14 },
    ["121790793420904"] = { style = "Boxing", name = "BoxingCritical", delay = 0.38 },

    -- Default / Street
    ["99810130553480"]  = { style = "Default", name = "DefaultPunch1", delay = 0.22, marker = true },
    ["108741734899896"] = { style = "Default", name = "DefaultPunch2", delay = 0.22 },
    ["131420553411309"] = { style = "Default", name = "DefaultPunch3", delay = 0.22 },
    ["128344453267222"] = { style = "Default", name = "DefaultPunch4", delay = 0.22 },
    ["125013954493950"] = { style = "Default", name = "DefaultCritical", delay = 0.38, marker = true },

    -- Karate
    ["72383368083937"]  = { style = "Karate", name = "KaratePunch1", delay = 0.16 },
    ["101493595766761"] = { style = "Karate", name = "KaratePunch2", delay = 0.16 },
    ["117311833156933"] = { style = "Karate", name = "KaratePunch3", delay = 0.16 },
    ["139818368428134"] = { style = "Karate", name = "KaratePunch4", delay = 0.16 },
    ["138751448642270"] = { style = "Karate", name = "KarateCritical", delay = 0.38 },

    -- Taekwondo
    ["71285630391939"]  = { style = "Taekwondo", name = "TaekwondoKick1", delay = 0.19 },
    ["132045283439505"] = { style = "Taekwondo", name = "TaekwondoKick2", delay = 0.19 },
    ["137265538892519"] = { style = "Taekwondo", name = "TaekwondoKick3", delay = 0.19 },
    ["76773915673575"]  = { style = "Taekwondo", name = "TaekwondoKick4", delay = 0.19 },
    ["114511086970158"] = { style = "Taekwondo", name = "TaekwondoCritical", delay = 0.38 },

    -- Kendo / DumbKendo
    ["138879764141061"] = { style = "Kendo", name = "KendoPunch1", delay = 0.26 },
    ["88933140898192"]  = { style = "Kendo", name = "KendoPunch2", delay = 0.26 },
    ["115475660627075"] = { style = "Kendo", name = "KendoPunch3", delay = 0.26 },
    ["140021888835093"] = { style = "Kendo", name = "KendoPunch4", delay = 0.26 },
    ["71126000171857"]  = { style = "Kendo", name = "KendoCritical", delay = 0.38 },
    ["116657713493359"] = { style = "DumbKendo", name = "DumbKendoPunch1", delay = 0.26 },
    ["74164428430876"]  = { style = "DumbKendo", name = "DumbKendoPunch2", delay = 0.26 },
    ["118292765021775"] = { style = "DumbKendo", name = "DumbKendoPunch3", delay = 0.26 },
    ["117921076562321"] = { style = "DumbKendo", name = "DumbKendoPunch4", delay = 0.26 },

    -- Wrestling
    ["128148706798323"] = { style = "Wrestling", name = "WrestlingPunch1", delay = 0.30 },
    ["77286017095346"]  = { style = "Wrestling", name = "WrestlingPunch2", delay = 0.30 },
    ["98630566471996"]  = { style = "Wrestling", name = "WrestlingPunch3", delay = 0.30 },
    ["117584179802706"] = { style = "Wrestling", name = "WrestlingPunch4", delay = 0.30 },
    ["133682402797708"] = { style = "Wrestling", name = "WrestlingCriticalUser", delay = 0.38 },

    -- Nekoashi
    ["105602418022818"] = { style = "Nekoashi", name = "NekoashiPunch1", delay = 0.18 },
    ["91711407671101"]  = { style = "Nekoashi", name = "NekoashiPunch2", delay = 0.18 },
    ["132891001464508"] = { style = "Nekoashi", name = "NekoashiPunch3", delay = 0.18 },
    ["127566377847523"] = { style = "Nekoashi", name = "NekoashiPunch4", delay = 0.18 },
    ["72093472019378"]  = { style = "Nekoashi", name = "NekoashiCritical", delay = 0.38 },

    -- Persona
    ["99008972026322"]  = { style = "Persona", name = "PersonaPunch1", delay = 0.19 },
    ["79497497324591"]  = { style = "Persona", name = "PersonaPunch2", delay = 0.19 },
    ["72813108384355"]  = { style = "Persona", name = "PersonaPunch3", delay = 0.19 },
    ["114803516160636"] = { style = "Persona", name = "PersonaPunch4", delay = 0.19 },

    -- Destroyer
    ["82972261960857"]  = { style = "Destroyer", name = "DestroyerPunch1", delay = 0.24 },
    ["116050210527852"] = { style = "Destroyer", name = "DestroyerPunch2", delay = 0.24 },
    ["76552358251759"]  = { style = "Destroyer", name = "DestroyerPunch3", delay = 0.24 },
    ["81593782253543"]  = { style = "Destroyer", name = "DestroyerPunch4", delay = 0.24 },
    ["130297813599495"] = { style = "Destroyer", name = "DestroyerCriticalStart", delay = 0.38 },

    -- Aikido
    ["113408550290116"] = { style = "Aikido", name = "AikidoPunch1", delay = 0.22 },
    ["86259504003424"]  = { style = "Aikido", name = "AikidoPunch2", delay = 0.22 },
    ["102396666469392"] = { style = "Aikido", name = "AikidoPunch3", delay = 0.22 },
    ["120032809599383"] = { style = "Aikido", name = "AikidoPunch4", delay = 0.22 },
    ["128003609665979"] = { style = "Aikido", name = "AikidoCriticalStart", delay = 0.38 },

    -- HoldingPencil
    ["78572006781458"]  = { style = "HoldingPencil", name = "HoldingPencilPunch1", delay = 0.18 },
    ["132998622367902"] = { style = "HoldingPencil", name = "HoldingPencilPunch2", delay = 0.18 },
    ["79613782313642"]  = { style = "HoldingPencil", name = "HoldingPencilCritical", delay = 0.38 },

    -- InjuredCrutches & Combat
    ["140330263823298"] = { style = "InjuredCrutches", name = "InjuredCrutchesPunch1", delay = 0.24 },
    ["117507927339006"] = { style = "InjuredCrutches", name = "InjuredCrutchesPunch2", delay = 0.24 },
    ["81116685696391"]  = { style = "InjuredCrutches", name = "InjuredCrutchesCritical", delay = 0.38 },
    ["125707761635803"] = { style = "Combat", name = "KickCrutch", delay = 0.22 },
    ["131444620555946"] = { style = "Destroyer", name = "DestroyerCriticalUser", delay = 0.38 },
    ["93179648846144"]  = { style = "Aikido", name = "AikidoCriticalUser", delay = 0.38 },
}

-- Explicitly blacklisted non-attacks (Dashes, Stance Starts, and Weaves)
local ISHIN_IGNORED_IDS = {
    -- Dashes & Dodges
    ["107546386335957"] = "DodgeForward",
    ["133535547421315"] = "DodgeBackward",
    ["123163208664940"] = "DodgeLeft",
    ["136513272168703"] = "DodgeRight",

    -- Stance Toggle Animations
    ["72312429062631"]  = "DefaultStanceStarted",
    ["109507455001910"] = "BoxingStanceStarted",
    ["129175693750876"] = "KarateStanceStarted",
    ["130213599245523"] = "WrestlingStanceStarted",
    ["127899164635557"] = "DumbKendoStanceStarted",
    ["132565748913735"] = "NekoashiStanceStarted",
    ["136557801148507"] = "AikidoStanceStarted",
    ["96073849836703"]  = "PersonaStanceStarted",
    ["105619482774147"] = "DestroyerStanceStarted",
    ["73349381817933"]  = "TaekwondoStanceStarted",

    -- Weaves / Sways
    ["97212032180903"]  = "PersonaWeaveLeft",
    ["100051810519507"] = "WrestlingWeaveRight",
    ["125017887274635"] = "AikidoWeaveLeft",
    ["121240547994862"] = "PersonaWeaveFront",
    ["83572751663384"]  = "AikidoWeaveBack",
    ["89370601011484"]  = "PersonaWeaveBack",
    ["73419191749015"]  = "NekoashiWeaveRight",
    ["74428678371045"]  = "BoxingWeaveLeft",
    ["75622667137034"]  = "KarateWeaveRight",
    ["101183867552242"] = "KarateWeaveLeft",
    ["99061264227636"]  = "WrestlingWeaveLeft",
    ["83606656785740"]  = "DumbKendoWeaveRight",
    ["112174054724865"] = "DumbKendoWeaveLeft",
    ["121275490162337"] = "KendoWeaveLeft",
    ["128582112625569"] = "AikidoWeaveRight",
    ["100911252575815"] = "PersonaWeaveRight",
    ["128981364659402"] = "BoxingWeaveRight",
}

----------------------------------------------------------------
-- ATTACK FILTERING ENGINE (Strict Whitelist Only)
----------------------------------------------------------------
local function getAttackInfo(track)
    local anim = track.Animation
    local animId = anim and anim.AnimationId:match("%d+")
    if not animId then return nil end
    
    -- 1. Explicit Discard: Known non-attacks (Dashes, Stance Starts, Weaves)
    if ISHIN_IGNORED_IDS[animId] then
        return nil
    end

    -- 2. Strict Whitelist: Only verified Ishin attacks trigger weaves
    return ISHIN_ATTACKS_BY_ID[animId]
end

----------------------------------------------------------------
-- COMBO TRACKER & ATTACK CHAIN ANALYSIS
----------------------------------------------------------------
local attackerComboState = setmetatable({}, { __mode = "k" })

local function getAttackComboHit(attackInfo)
    if not attackInfo then return 1 end
    local name = attackInfo.name or ""
    if name:find("Critical") or name:find("Crit") then
        return 4 -- Ender / Critical
    end
    local num = name:match("(%d+)$")
    if num then
        return tonumber(num) or 1
    end
    return 1
end

local comboCaught = false
local lastComboTime = 0

local function markHitstun()
    comboCaught = true
    lastComboTime = os.clock()
    
    -- Only auto-raise block on taking hit if we aren't already blocking, attacking, or 1 hit from guard break
    if not state.Enabled or not state.SmartComboBlock then return end
    if isBlocking then return end
    if blockedHitsCount >= (state.MaxBlockedHits or 2) then return end
    if (os.clock() - lastPlayerAttackTime) < 0.40 then return end
    if (os.clock() - lastGuardDropTime) < 0.20 then return end
    
    performBlock(0.35, false)
    lastAnimText = "[DAMAGE TAKEN] -> Guard Raised (F)"
    onAnimCallback(lastAnimText)
end

local function onEnemyAttack(attackerModel, track, attackInfo)
    if not state.Enabled or not attackInfo then return end
    local myChar = LocalPlayer.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local enemyHrp = attackerModel and attackerModel:FindFirstChild("HumanoidRootPart")
    if not myHrp or not enemyHrp then return end
    
    -- Distance check: Allow up to 14 studs (or state.Range) to track attacks with forward lunges
    local dist = (myHrp.Position - enemyHrp.Position).Magnitude
    local maxDetectRange = math.max(state.Range, 14)
    if dist > maxDetectRange then return end
    
    -- Facing check: within 8 studs always true; 2D planar dot product for longer ranges
    if state.FacingCheck and not isFacingTarget(enemyHrp, myHrp, state.FacingDot) then
        return
    end
    
    local hitIndex = getAttackComboHit(attackInfo)
    local now = os.clock()
    if now - lastComboTime > 1.4 then
        comboCaught = false
    end
    
    -- 0.7s Inactivity reset: If no hit has been blocked in 0.7s, reset the blocked hits counter
    if (now - lastBlockHitTime) > (state.BlockTimeout or 0.7) then
        blockedHitsCount = 0
    end
    
    local style = attackInfo.style
    local baseDelay = attackInfo.delay or 0.22
    local isActualCrit = (attackInfo.name:find("Critical") ~= nil)
        or (attackInfo.name:find("Crit") ~= nil)
        or (attackInfo.name:find("Heavy") ~= nil)
    local isCrit = isActualCrit or (hitIndex >= 4)
    
    -- Latency compensation
    local reactionDelay = baseDelay
    if state.PingComp then
        local ping = getPing()
        reactionDelay = math.max(0.04, reactionDelay - ((ping / 1000) * 0.5))
    end

    -- For Critical attacks: initiate dash away at 0.20s into windup so player clears hitbox before impact
    if isActualCrit and state.DashAwayFromCrit then
        reactionDelay = math.min(reactionDelay, 0.20)
    end

    -- GUARD BREAK PREVENTION:
    -- If a Critical/Heavy attack is incoming, or if we have already blocked 2 hits:
    -- NEVER BLOCK! Drop block so you dodge the critical and never get guard broken!
    if state.GuardBreakPrevent and (isCrit or blockedHitsCount >= (state.MaxBlockedHits or 2)) then
        if isBlocking then
            stopBlock("Anti-GuardBreak (Critical / 2 Hits Blocked)")
        end
    end

    -- SMART COMBO AUTO-BLOCK (Hits 2 & 3):
    -- ONLY activates if caught in combo AND we haven't already blocked 2 hits AND attack is NOT a Critical!
    if state.SmartComboBlock and (hitIndex == 2 or hitIndex == 3) and comboCaught and not isCrit and (blockedHitsCount < (state.MaxBlockedHits or 2)) then
        performBlock(baseDelay + 0.25, true)
        lastAttackerName = attackerModel.Name
        lastAnimText = attackerModel.Name .. " [" .. style .. "]: " .. attackInfo.name .. " -> [AUTO-BLOCK " .. blockedHitsCount .. "/" .. (state.MaxBlockedHits or 2) .. "]"
        onAnimCallback(lastAnimText)
        return
    end
    
    -- 4th Hit / Ender / Critical:
    -- Combo ender window: drop guard and weave/dash!
    if hitIndex >= 4 or isCrit then
        comboCaught = false
        if isBlocking then
            stopBlock("Dropping Guard to Weave/Dash Ender")
        end
    end
    
    -- Weave chance roll
    local willWeave = (math.random() * 100 <= state.Percent)
    if not willWeave then
        if state.FallbackBlock or state.SmartComboBlock then
            performBlock(baseDelay + 0.3)
        end
        return
    end

    -- Update telemetry (shows style + computed apex in UI)
    lastAttackerName = attackerModel.Name
    local actionTag = (isActualCrit and state.DashAwayFromCrit and " [CRIT DASH AWAY]")
        or (hitIndex >= 4 and " [ENDER WEAVE]")
        or (" [WEAVE " .. hitIndex .. "/4]")
    lastAnimText = attackerModel.Name .. " [" .. style .. "]: " .. attackInfo.name .. actionTag .. " (" .. string.format("%.2fs", reactionDelay) .. ")"
    onAnimCallback(lastAnimText)
    
    local weaved = false
    local markerConn

    local function executeAvoidance()
        if weaved or not state.Enabled then return end
        weaved = true
        if markerConn then markerConn:Disconnect() end
        if isBlocking then
            stopBlock()
        end

        if isActualCrit and state.DashAwayFromCrit then
            performCritDash(enemyHrp)
        else
            local success = performWeave(enemyHrp)
            if not success and (state.FallbackBlock or state.SmartComboBlock) then
                performBlock(0.35)
            end
        end
    end
    
    -- 1. Hook Keyframe "Hit" marker if present (e.g. DefaultPunch, DefaultCritical)
    pcall(function()
        markerConn = track:GetMarkerReachedSignal("Hit"):Connect(function()
            executeAvoidance()
        end)
    end)
    
    -- 2. Precision Apex Timer (for styles without markers or as fallback)
    task.delay(reactionDelay, function()
        if weaved or not state.Enabled then
            if markerConn then markerConn:Disconnect() end
            return
        end
        if not track.IsPlaying then
            if markerConn then markerConn:Disconnect() end
            return
        end
        local freshMyHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not freshMyHrp or not enemyHrp.Parent then
            if markerConn then markerConn:Disconnect() end
            return
        end
        
        -- At strike apex: ensure enemy is within strike reach
        local strikeDist = (freshMyHrp.Position - enemyHrp.Position).Magnitude
        if strikeDist <= math.max(state.Range * 1.3, 11) then
            executeAvoidance()
        else
            if state.FallbackBlock or state.SmartComboBlock then
                performBlock(0.25)
            end
        end
    end)
end

----------------------------------------------------------------
-- LIGHTWEIGHT ANIMATION SCANNER & LOCAL PLAYER HOOK
----------------------------------------------------------------
local trackedAnimators = setmetatable({}, { __mode = "k" })
local playerKnownStyles = {}
local playerLastCrit = {}
local playerEspInstances = {}
local CRIT_COOLDOWN_TIME = 8.0

local function registerAnimator(animator)
    if trackedAnimators[animator] then return end
    local model = animator:FindFirstAncestorOfClass("Model")
    if not model or model == LocalPlayer.Character then return end
    
    trackedAnimators[animator] = true
    
    local ok, conn = pcall(function()
        return animator.AnimationPlayed:Connect(function(track)
            if model == LocalPlayer.Character then return end
            local attackInfo = getAttackInfo(track)
            if attackInfo then
                local plr = Players:GetPlayerFromCharacter(model)
                if plr then
                    if attackInfo.style then playerKnownStyles[plr] = attackInfo.style end
                    if attackInfo.name:find("Crit") or attackInfo.name:find("Heavy") or attackInfo.name:find("Critical") then
                        playerLastCrit[plr] = os.clock()
                    end
                end
                if state.Enabled then
                    onEnemyAttack(model, track, attackInfo)
                end
            end
        end)
    end)
    if ok and conn then
        trackConn(conn)
    end
end

local function hookPlayer(plr)
    if plr == LocalPlayer then return end
    local function onChar(char)
        if not char then return end
        local hum = char:WaitForChild("Humanoid", 4)
        local hrp = char:WaitForChild("HumanoidRootPart", 4)
        local animator = hum and hum:WaitForChild("Animator", 4)
        if animator then
            registerAnimator(animator)
        end
        if not hrp or not hum then return end
        
        if playerEspInstances[plr] then
            pcall(function() playerEspInstances[plr].bb:Destroy() end)
            playerEspInstances[plr] = nil
        end
        
        local bb = Instance.new("BillboardGui")
        bb.Name = "CombatEsp_" .. plr.Name
        bb.Adornee = hrp
        bb.Size = UDim2.fromOffset(145, 52)
        bb.AlwaysOnTop = true
        bb.ExtentsOffset = Vector3.new(0, -0.5, 0)   -- lower to feet
        bb.MaxDistance = state.EspMaxDistance or 120
        bb.Enabled = state.PlayerEsp
        bb.Parent = hrp
        
        local frame = Instance.new("Frame", bb)
        frame.Size = UDim2.fromScale(1, 1)
        frame.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
        frame.BackgroundTransparency = 0.25
        local cr = Instance.new("UICorner", frame)
        cr.CornerRadius = UDim.new(0, 6)
        local st = Instance.new("UIStroke", frame)
        st.Color = Color3.fromRGB(124, 92, 255)
        st.Thickness = 1
        st.Transparency = 0.3
        
        local topLbl = Instance.new("TextLabel", frame)
        topLbl.Size = UDim2.new(1, -8, 0, 14)
        topLbl.Position = UDim2.fromOffset(4, 3)
        topLbl.BackgroundTransparency = 1
        topLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        topLbl.Font = Enum.Font.GothamBold
        topLbl.TextSize = 11
        topLbl.TextXAlignment = Enum.TextXAlignment.Left
        topLbl.Text = plr.DisplayName
        
        local hpBg = Instance.new("Frame", frame)
        hpBg.Size = UDim2.new(1, -8, 0, 8)
        hpBg.Position = UDim2.fromOffset(4, 20)
        hpBg.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
        local hpCr = Instance.new("UICorner", hpBg)
        hpCr.CornerRadius = UDim.new(0, 4)
        
        local hpFill = Instance.new("Frame", hpBg)
        hpFill.Size = UDim2.fromScale(1, 1)
        hpFill.BackgroundColor3 = Color3.fromRGB(50, 220, 110)
        local fillCr = Instance.new("UICorner", hpFill)
        fillCr.CornerRadius = UDim.new(0, 4)
        
        local hpText = Instance.new("TextLabel", hpBg)
        hpText.Size = UDim2.fromScale(1, 1)
        hpText.BackgroundTransparency = 1
        hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
        hpText.Font = Enum.Font.GothamBold
        hpText.TextSize = 8
        hpText.Text = "100/100"
        
        local bottomLbl = Instance.new("TextLabel", frame)
        bottomLbl.Size = UDim2.new(1, -8, 0, 14)
        bottomLbl.Position = UDim2.fromOffset(4, 33)
        bottomLbl.BackgroundTransparency = 1
        bottomLbl.TextColor3 = Color3.fromRGB(200, 200, 220)
        bottomLbl.Font = Enum.Font.GothamMedium
        bottomLbl.TextSize = 10
        bottomLbl.TextXAlignment = Enum.TextXAlignment.Left
        bottomLbl.Text = "Style: ? • Crit: READY"
        
        playerEspInstances[plr] = {
            bb = bb,
            frame = frame,
            topLbl = topLbl,
            hpBg = hpBg,
            hpFill = hpFill,
            hpText = hpText,
            bottomLbl = bottomLbl,
            hum = hum,
            hrp = hrp,
        }
    end
    if plr.Character then task.spawn(onChar, plr.Character) end
    trackConn(plr.CharacterAdded:Connect(onChar))
    trackConn(plr.CharacterRemoving:Connect(function()
        if playerEspInstances[plr] then
            pcall(function() playerEspInstances[plr].bb:Destroy() end)
            playerEspInstances[plr] = nil
        end
    end))
end

for _, plr in ipairs(Players:GetPlayers()) do
    hookPlayer(plr)
end
trackConn(Players.PlayerAdded:Connect(hookPlayer))
trackConn(Players.PlayerRemoving:Connect(function(plr)
    if playerEspInstances[plr] then
        pcall(function() playerEspInstances[plr].bb:Destroy() end)
        playerEspInstances[plr] = nil
    end
    playerKnownStyles[plr] = nil
    playerLastCrit[plr] = nil
end))

----------------------------------------------------------------
-- LOCAL PLAYER HITSTUN & DAMAGE DETECTOR
----------------------------------------------------------------
local function hookLocalPlayer()
    local function onLocalChar(char)
        if not char then return end
        local hum = char:WaitForChild("Humanoid", 4)
        local anim = hum and hum:WaitForChild("Animator", 4)
        
        if hum then
            local lastHealth = hum.Health
            trackConn(hum.HealthChanged:Connect(function(newHealth)
                if newHealth < lastHealth then
                    lastHealth = newHealth
                    markHitstun()
                else
                    lastHealth = newHealth
                end
            end))
        end
        
        if anim then
            trackConn(anim.AnimationPlayed:Connect(function(track)
                if not state.Enabled then return end
                local animId = track.Animation and track.Animation.AnimationId:match("%d+")
                local name = (track.Name or ""):lower()
                
                local isHitAnim = false
                if animId and (animId == "111003631876168" or animId == "99470338604270" or animId == "89110706638186") then
                    isHitAnim = true
                elseif name:find("hit") or name:find("hurt") or name:find("stun") or name:find("flinch") or name:find("damage") then
                    if not name:find("blockhit") and not name:find("guardhit") then
                        isHitAnim = true
                    end
                end
                
                if isHitAnim then
                    markHitstun()
                end
                
                -- Detect Local Player Attacking (M1/M2/Crit) -> Priority 2: Drop block immediately!
                local isAttackAnim = false
                if animId and ISHIN_ATTACKS_BY_ID[animId] then
                    isAttackAnim = true
                elseif name:find("punch") or name:find("m1") or name:find("m2") or name:find("attack")
                    or name:find("swing") or name:find("jab") or name:find("hook") or name:find("uppercut")
                    or name:find("slash") or name:find("kick") or name:find("crit") then
                    if not name:find("blockhit") and not name:find("guardhit") and not name:find("hit") and not name:find("hurt") then
                        isAttackAnim = true
                    end
                end
                if isAttackAnim then
                    onPlayerAttackInput()
                end

                -- Detect Guard Absorbing Hit (BlockHit)
                if animId == "79698927438954" or name:find("blockhit") or name:find("guardhit") then
                    blockedHitsCount += 1
                    lastBlockHitTime = os.clock()
                    if blockedHitsCount >= (state.MaxBlockedHits or 2) then
                        task.delay(0.12, function()
                            stopBlock("Blocked 2 Hits -> Dropped Guard (Anti-Break)")
                        end)
                    end
                end
                
                -- Detect Guard Shattered / Broken
                if animId == "119014403580124" or name:find("guardbroken") or name:find("guard_broken") then
                    stopBlock("Guard Shattered")
                    blockedHitsCount = 0
                    comboCaught = false
                end
            end))
        end
    end
    
    if LocalPlayer.Character then
        task.spawn(onLocalChar, LocalPlayer.Character)
    end
    trackConn(LocalPlayer.CharacterAdded:Connect(onLocalChar))
end

hookLocalPlayer()

----------------------------------------------------------------
-- RANGE CIRCLE
----------------------------------------------------------------
local anchor = Instance.new("Part")
anchor.Name = "WeaveRangeAnchor"
anchor.Size = Vector3.new(0.1, 0.1, 0.1)
anchor.Transparency = 1
anchor.Anchored = true
anchor.CanCollide = false
anchor.CanQuery = false
anchor.CanTouch = false
anchor.Parent = workspace

local flat = CFrame.Angles(math.rad(90), 0, 0)

local ring = Instance.new("CylinderHandleAdornment")
ring.Adornee = anchor
ring.Height = 0.05
ring.CFrame = flat
ring.AlwaysOnTop = true
ring.ZIndex = 2
ring.Parent = anchor

local fillDisc = Instance.new("CylinderHandleAdornment")
fillDisc.Adornee = anchor
fillDisc.Height = 0.04
fillDisc.CFrame = flat
fillDisc.AlwaysOnTop = true
fillDisc.ZIndex = 1
fillDisc.Parent = anchor

local GREY = Color3.fromRGB(110, 110, 125)

local lastPos = Vector3.new()
local renderConn = trackConn(RunService.RenderStepped:Connect(function()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or not state.ShowCircle then
        ring.Visible = false
        fillDisc.Visible = false
        return
    end
    ring.Visible = true
    fillDisc.Visible = true

    local pos = hrp.Position
    if (pos - lastPos).Magnitude > 0.05 then
        lastPos = pos
        local groundOffset = hum.HipHeight + hrp.Size.Y / 2 - 0.05
        anchor.CFrame = CFrame.new(pos - Vector3.new(0, groundOffset, 0))
    end

    local r = math.max(state.Range, 1)
    if ring.Radius ~= r then
        ring.Radius = r
        ring.InnerRadius = math.max(r - state.RingThickness, 0)
        fillDisc.Radius = r
    end

    local flashing = os.clock() < flashUntil
    local targetColor = flashing and Color3.fromRGB(255, 255, 255) or (state.Enabled and state.CircleColor or GREY)
    if ring.Color3 ~= targetColor then
        ring.Color3 = targetColor
        fillDisc.Color3 = targetColor
    end
    ring.Transparency = flashing and 0 or 0.25
    fillDisc.Transparency = flashing and 0.4 or state.FillOpacity
end))

local heartbeatConn = trackConn(RunService.Heartbeat:Connect(function()
    local now = os.clock()
    -- WATCHDOG: Ensure block is never held longer than BlockTimeout (default 0.70s)
    if isBlocking then
        local elapsed = now - blockStartTime
        if elapsed >= (state.BlockTimeout or 0.70) then
            stopBlock("Watchdog: Hard Timeout (0.7s)")
        end
    end
    
    -- Inactivity reset for combo counter
    if blockedHitsCount > 0 and (now - lastBlockHitTime) > (state.BlockTimeout or 0.70) then
        blockedHitsCount = 0
    end

    -- MOVEMENT COMPENSATION WATCHDOG: Ensure micro-anchor never exceeds 0.10s
    if isMicroAnchored then
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if (now - anchorStartTime) > 0.10 then
            isMicroAnchored = false
            if hrp then
                pcall(function() hrp.Anchored = false end)
            end
        end
    end

    -- COMBAT ESP ENGINE: Dynamic BillboardGui updater
    local myChar = LocalPlayer.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local myPos = (myHrp and myHrp.Position) or Vector3.new()
    
    for plr, esp in pairs(playerEspInstances) do
        local eHrp = esp.hrp
        local eHum = esp.hum
        if not eHrp or not eHrp.Parent or not eHum or not eHum.Parent then
            esp.bb.Enabled = false
        else
            local dist = (eHrp.Position - myPos).Magnitude
            if not state.PlayerEsp or dist > (state.EspMaxDistance or 120) or eHum.Health <= 0 then
                esp.bb.Enabled = false
            else
                esp.bb.Enabled = true
                esp.bb.MaxDistance = state.EspMaxDistance or 120
                
                -- Top Row: Name & Distance
                local nameStr = state.EspShowName and plr.DisplayName or ""
                local distStr = state.EspShowDistance and (" [" .. math.floor(dist) .. "m]") or ""
                esp.topLbl.Visible = (state.EspShowName or state.EspShowDistance)
                esp.topLbl.Text = nameStr .. distStr
                
                -- Health Bar & HP Text
                esp.hpBg.Visible = state.EspShowHealth
                if state.EspShowHealth then
                    local maxHp = math.max(eHum.MaxHealth, 1)
                    local hp = math.clamp(eHum.Health, 0, maxHp)
                    local pct = math.clamp(hp / maxHp, 0, 1)
                    esp.hpFill.Size = UDim2.fromScale(pct, 1)
                    
                    local hpColor = (pct > 0.5) 
                        and Color3.fromRGB(math.floor(255 * (1 - pct) * 2), 220, 90)
                        or Color3.fromRGB(255, math.floor(220 * pct * 2), 70)
                    esp.hpFill.BackgroundColor3 = hpColor
                    esp.hpText.Text = math.floor(hp) .. "/" .. math.floor(maxHp)
                end
                
                -- Bottom Row: Style & Crit Cooldown
                local styleStr = state.EspShowStyle and (playerKnownStyles[plr] or "Default") or ""
                local critStr = ""
                local critColor = Color3.fromRGB(70, 220, 120)
                if state.EspShowCrit then
                    local lastCrit = playerLastCrit[plr]
                    if lastCrit and (now - lastCrit < CRIT_COOLDOWN_TIME) then
                        local rem = CRIT_COOLDOWN_TIME - (now - lastCrit)
                        critStr = string.format("Crit: %.1fs", rem)
                        critColor = Color3.fromRGB(255, 110, 80)
                    else
                        critStr = "Crit: READY"
                        critColor = Color3.fromRGB(70, 220, 120)
                    end
                end
                
                esp.bottomLbl.Visible = (state.EspShowStyle or state.EspShowCrit)
                if state.EspShowStyle and state.EspShowCrit then
                    esp.bottomLbl.Text = styleStr .. " • " .. critStr
                elseif state.EspShowStyle then
                    esp.bottomLbl.Text = styleStr
                elseif state.EspShowCrit then
                    esp.bottomLbl.Text = critStr
                end
                esp.bottomLbl.TextColor3 = critColor
            end
        end
    end
end))

----------------------------------------------------------------
-- GUI CREATION (Modern Dark Aesthetic)
----------------------------------------------------------------
local WHITE = Color3.new(1, 1, 1)
local ACCENT = Color3.fromRGB(124, 92, 255)
local ACCENT2 = Color3.fromRGB(0, 200, 255)
local BG = Color3.fromRGB(13, 13, 19)
local PANEL = Color3.fromRGB(24, 24, 35)
local OFFC = Color3.fromRGB(50, 50, 66)
local MUTED = Color3.fromRGB(145, 145, 168)
local GREEN = Color3.fromRGB(70, 220, 120)
local RED = Color3.fromRGB(235, 70, 80)

local function tween(obj, t, props, style, dir)
    TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props):Play()
end

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

local function round(o, r) new("UICorner", { CornerRadius = UDim.new(0, r) }, o) end
local function grad(o) return new("UIGradient", { Color = ColorSequence.new(ACCENT, ACCENT2) }, o) end

local function label(parent, text, size, pos, font, textSize, color, align)
    return new("TextLabel", {
        Text = text, Size = size, Position = pos, BackgroundTransparency = 1,
        Font = font, TextSize = textSize, TextColor3 = color,
        TextXAlignment = align or Enum.TextXAlignment.Left,
    }, parent)
end

-- Parent GUI safely (CoreGui if executor allows, else PlayerGui)
local guiParent = nil
pcall(function()
    guiParent = game:GetService("CoreGui")
end)
if not guiParent or not pcall(function() return guiParent.Name end) then
    guiParent = LocalPlayer:WaitForChild("PlayerGui")
end

local gui = new("ScreenGui", {
    Name = "AutoWeaveUltimateGui", ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 100,
}, guiParent)

local main = new("Frame", {
    Size = UDim2.fromOffset(375, 530),
    Position = UDim2.new(0, 50, 0.5, -265),
    BackgroundColor3 = BG, BorderSizePixel = 0, Active = true,
    ClipsDescendants = true,
}, gui)
round(main, 16)
local scale = new("UIScale", { Scale = 1 }, main)

-- Animated Gradient Border
local border = new("Frame", {
    Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2),
    BackgroundTransparency = 1, ZIndex = 10,
}, main)
round(border, 14)
local borderStroke = new("UIStroke", { Thickness = 2, Color = WHITE }, border)
local borderGrad = new("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, ACCENT),
        ColorSequenceKeypoint.new(0.5, ACCENT2),
        ColorSequenceKeypoint.new(1, ACCENT),
    }),
}, borderStroke)

-- Header
local header = new("Frame", { Size = UDim2.new(1, 0, 0, 70), BackgroundTransparency = 1, Active = true }, main)
local title = label(header, "AUTO WEAVE", UDim2.new(1, -120, 0, 28), UDim2.fromOffset(18, 12),
    Enum.Font.GothamBlack, 22, WHITE)
grad(title)
local sub = label(header, "Hide / show: RightShift", UDim2.new(1, -120, 0, 16), UDim2.fromOffset(18, 42),
    Enum.Font.Gotham, 12, MUTED)
local pill = new("TextLabel", {
    Size = UDim2.fromOffset(78, 26), Position = UDim2.new(1, -96, 0, 18),
    Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = WHITE,
    BackgroundColor3 = GREEN, BorderSizePixel = 0, Text = "ACTIVE",
}, header)
round(pill, 13)

local toast
local enableSet
local function refreshPill()
    pill.Text = state.Enabled and "ACTIVE" or "OFF"
    tween(pill, 0.2, { BackgroundColor3 = state.Enabled and GREEN or RED })
end

local function setEnabled(v)
    state.Enabled = v
    if enableSet then enableSet(v, true) end
    refreshPill()
    if toast then toast("Auto Weave " .. (v and "ON" or "OFF"), v and GREEN or RED) end
end

-- Dragging
do
    local dragging, dragStart, startPos
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, dragStart, startPos = true, input.Position, main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
end

-- Tabs Bar
local tabBar = new("Frame", {
    Size = UDim2.new(1, -36, 0, 34), Position = UDim2.fromOffset(18, 74),
    BackgroundColor3 = PANEL, BorderSizePixel = 0,
}, main)
round(tabBar, 10)

local indicator = new("Frame", {
    Size = UDim2.new(1 / 5, -6, 1, -6), Position = UDim2.new(0, 3, 0, 3),
    BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 1,
}, tabBar)
round(indicator, 8)
grad(indicator)

local content = new("Frame", {
    Size = UDim2.new(1, 0, 1, -118), Position = UDim2.fromOffset(0, 118),
    BackgroundTransparency = 1,
}, main)

local pages, tabButtons = {}, {}
local function showTab(i)
    for j, p in ipairs(pages) do p.Visible = (j == i) end
    for j, b in ipairs(tabButtons) do
        tween(b, 0.2, { TextColor3 = (j == i) and WHITE or MUTED })
    end
    tween(indicator, 0.3, { Position = UDim2.new((i - 1) / 5, 3, 0, 3) }, Enum.EasingStyle.Quint)
end

local function newTab(name, index)
    local btn = new("TextButton", {
        Text = name, Size = UDim2.new(1 / 5, 0, 1, 0), Position = UDim2.new((index - 1) / 5, 0, 0, 0),
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 10,
        TextColor3 = MUTED, ZIndex = 2, AutoButtonColor = false,
    }, tabBar)
    tabButtons[index] = btn
    btn.MouseButton1Click:Connect(function() showTab(index) end)

    local page = new("ScrollingFrame", {
        Size = UDim2.new(1, -24, 1, -14), Position = UDim2.fromOffset(12, 4),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = ACCENT, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
    }, content)
    new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, page)
    new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8) }, page)
    pages[index] = page
    return page
end

local combatPage = newTab("COMBAT", 1)
local stylesPage = newTab("STYLES", 2)
local yenPage = newTab("YEN", 3)
local visualsPage = newTab("VISUALS", 4)
local bindsPage = newTab("BINDS", 5)

----------------------------------------------------------------
-- UI COMPONENTS (Toggles, Sliders, Dropdowns, Binds)
----------------------------------------------------------------
local function makeToggle(page, text, default, cb)
    local row = new("TextButton", {
        Size = UDim2.new(1, -6, 0, 42), BackgroundColor3 = PANEL, BorderSizePixel = 0,
        AutoButtonColor = false, Text = "",
    }, page)
    round(row, 10)
    label(row, text, UDim2.new(1, -80, 1, 0), UDim2.fromOffset(14, 0), Enum.Font.GothamMedium, 14, WHITE)
    local sw = new("Frame", {
        Size = UDim2.fromOffset(44, 24), Position = UDim2.new(1, -58, 0.5, -12),
        BackgroundColor3 = OFFC, BorderSizePixel = 0,
    }, row)
    round(sw, 12)
    local knob = new("Frame", {
        Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = WHITE, BorderSizePixel = 0,
    }, sw)
    round(knob, 9)

    local value = default
    local function set(v, silent)
        value = v
        tween(sw, 0.2, { BackgroundColor3 = v and ACCENT or OFFC })
        tween(knob, 0.25, { Position = v and UDim2.fromOffset(23, 3) or UDim2.fromOffset(3, 3) }, Enum.EasingStyle.Back)
        if not silent then cb(v) end
    end
    row.MouseButton1Click:Connect(function() set(not value) end)
    set(default, true)
    return set
end

local function makeSlider(page, name, min, max, default, decimals, suffix, cb)
    local holder = new("Frame", { Size = UDim2.new(1, -6, 0, 56), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, page)
    round(holder, 10)
    label(holder, name, UDim2.new(0.6, 0, 0, 20), UDim2.fromOffset(14, 8), Enum.Font.GothamMedium, 14, WHITE)
    local valueLabel = label(holder, "", UDim2.new(0.4, -14, 0, 20), UDim2.new(0.6, 0, 0, 8),
        Enum.Font.GothamBold, 14, ACCENT2, Enum.TextXAlignment.Right)

    local track = new("Frame", {
        Size = UDim2.new(1, -28, 0, 6), Position = UDim2.fromOffset(14, 40),
        BackgroundColor3 = OFFC, BorderSizePixel = 0,
    }, holder)
    round(track, 3)
    local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, track)
    round(fill, 3)
    grad(fill)
    local knob = new("Frame", {
        Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3,
    }, track)
    round(knob, 7)
    local hit = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 28),
        BackgroundTransparency = 1, Text = "",
    }, holder)

    local function set(v)
        local m = 10 ^ decimals
        v = math.clamp(math.floor(v * m + 0.5) / m, min, max)
        local a = (v - min) / (max - min)
        fill.Size = UDim2.fromScale(a, 1)
        knob.Position = UDim2.fromScale(a, 0.5)
        valueLabel.Text = string.format("%." .. decimals .. "f", v) .. suffix
        cb(v)
    end
    local function fromX(x)
        local a = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        set(min + (max - min) * a)
    end

    local dragging = false
    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            tween(knob, 0.12, { Size = UDim2.fromOffset(20, 20) })
            fromX(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            fromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
            dragging = false
            tween(knob, 0.12, { Size = UDim2.fromOffset(14, 14) })
        end
    end)
    set(default)
end

local function makeDropdown(page, name, options, default, cb)
    local holder = new("Frame", { Size = UDim2.new(1, -6, 0, 46), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, page)
    round(holder, 10)
    label(holder, name, UDim2.new(0.45, 0, 1, 0), UDim2.fromOffset(14, 0), Enum.Font.GothamMedium, 14, WHITE)
    
    local btn = new("TextButton", {
        Size = UDim2.new(0.5, -14, 0, 30), Position = UDim2.new(0.5, 0, 0.5, -15),
        BackgroundColor3 = OFFC, BorderSizePixel = 0, AutoButtonColor = false,
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = WHITE, Text = default,
    }, holder)
    round(btn, 8)
    new("UIStroke", { Color = ACCENT, Thickness = 1, Transparency = 0.5 }, btn)
    
    local currentIdx = 1
    for i, opt in ipairs(options) do
        if opt == default then currentIdx = i break end
    end
    
    btn.MouseButton1Click:Connect(function()
        currentIdx = (currentIdx % #options) + 1
        local chosen = options[currentIdx]
        btn.Text = chosen
        cb(chosen)
    end)
end

local listeningKey = nil
local function makeKeybind(page, text, stateKey)
    local row = new("Frame", { Size = UDim2.new(1, -6, 0, 42), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, page)
    round(row, 10)
    label(row, text, UDim2.new(1, -120, 1, 0), UDim2.fromOffset(14, 0), Enum.Font.GothamMedium, 14, WHITE)
    local key = new("TextButton", {
        Size = UDim2.fromOffset(96, 28), Position = UDim2.new(1, -110, 0.5, -14),
        BackgroundColor3 = OFFC, BorderSizePixel = 0, AutoButtonColor = false,
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = WHITE,
        Text = state[stateKey].Name,
    }, row)
    round(key, 8)
    new("UIStroke", { Color = ACCENT, Thickness = 1, Transparency = 0.5 }, key)
    key.MouseButton1Click:Connect(function()
        key.Text = "..."
        tween(key, 0.15, { BackgroundColor3 = ACCENT })
        listeningKey = { key = stateKey, button = key }
    end)
end

local function makeButton(page, text, btnText, cb)
    local row = new("Frame", { Size = UDim2.new(1, -6, 0, 42), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, page)
    round(row, 10)
    label(row, text, UDim2.new(1, -135, 1, 0), UDim2.fromOffset(14, 0), Enum.Font.GothamMedium, 13, WHITE)
    local btn = new("TextButton", {
        Size = UDim2.fromOffset(115, 28), Position = UDim2.new(1, -125, 0.5, -14),
        BackgroundColor3 = ACCENT, BorderSizePixel = 0, AutoButtonColor = false,
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = WHITE,
        Text = btnText,
    }, row)
    round(btn, 8)
    btn.MouseButton1Click:Connect(function()
        tween(btn, 0.08, { BackgroundColor3 = ACCENT2 })
        task.delay(0.12, function()
            tween(btn, 0.15, { BackgroundColor3 = ACCENT })
        end)
        pcall(cb)
    end)
    return btn
end

----------------------------------------------------------------
-- POPULATE PAGES
----------------------------------------------------------------
-- COMBAT
enableSet = makeToggle(combatPage, "Auto Weave", state.Enabled, setEnabled)

makeDropdown(combatPage, "Trigger Mode", { "Right Click", "Space", "Q (Dodge)", "Velocity Dash" }, state.TriggerMode, function(v)
    state.TriggerMode = v
end)

makeDropdown(combatPage, "Strafe Dir", { "Adaptive", "None", "Random", "Left", "Right", "Back", "Front" }, state.WeaveDirection, function(v)
    state.WeaveDirection = v
end)

makeSlider(combatPage, "Weave Chance", 0, 100, state.Percent, 0, "%", function(v) state.Percent = v end)
makeSlider(combatPage, "Range", 5, 30, state.Range, 0, " studs", function(v) state.Range = v end)
makeSlider(combatPage, "Weave Cooldown", 0.2, 1.2, state.Cooldown, 2, "s", function(v) state.Cooldown = v end)

-- Movement Compensation Engine (Stop-to-Weave)
makeToggle(combatPage, "Movement Compensation", state.MovementComp, function(v) state.MovementComp = v end)
makeSlider(combatPage, "Movement Halt Time", 0.03, 0.10, state.CompHaltDuration, 2, "s", function(v) state.CompHaltDuration = v end)

-- Critical Dash Avoidance
makeToggle(combatPage, "Dash Away From Crits", state.DashAwayFromCrit, function(v) state.DashAwayFromCrit = v end)
makeKeybind(combatPage, "Dodge Key", "DodgeKey")
makeSlider(combatPage, "Crit Dash Speed", 35, 90, state.CritDashSpeed, 0, " studs/s", function(v) state.CritDashSpeed = v end)
makeSlider(combatPage, "Crit Dash Duration", 0.15, 0.45, state.CritDashDuration, 2, "s", function(v) state.CritDashDuration = v end)

-- Fallback Guard & Smart Combo Controls
makeToggle(combatPage, "Block on Missed Weave", state.FallbackBlock, function(v) state.FallbackBlock = v end)
makeToggle(combatPage, "Combo Auto-Block (Hits 2 & 3)", state.SmartComboBlock, function(v) state.SmartComboBlock = v end)
makeToggle(combatPage, "Weave 4th Hit / Ender", state.WeaveComboEnder, function(v) state.WeaveComboEnder = v end)
makeToggle(combatPage, "Prevent Guard Break", state.GuardBreakPrevent, function(v) state.GuardBreakPrevent = v end)
makeSlider(combatPage, "Max Blocked Hits", 1, 4, state.MaxBlockedHits, 0, " hits", function(v) state.MaxBlockedHits = v end)
makeSlider(combatPage, "Block Idle Timeout", 0.3, 1.2, state.BlockTimeout, 2, "s", function(v) state.BlockTimeout = v end)
makeKeybind(combatPage, "Block Key", "BlockKey")
makeSlider(combatPage, "Block Hit Duration", 0.15, 0.6, state.BlockDuration, 2, "s", function(v) state.BlockDuration = v end)

makeToggle(combatPage, "Ping Compensation", state.PingComp, function(v) state.PingComp = v end)
makeToggle(combatPage, "Facing Check", state.FacingCheck, function(v) state.FacingCheck = v end)

-- Combat Info Rows
local animRow = new("Frame", { Size = UDim2.new(1, -6, 0, 52), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, combatPage)
round(animRow, 10)
label(animRow, "Last Attack Detected", UDim2.new(1, -20, 0, 16), UDim2.fromOffset(14, 6), Enum.Font.GothamMedium, 12, MUTED)
local animText = label(animRow, "none yet", UDim2.new(1, -28, 0, 22), UDim2.fromOffset(14, 26), Enum.Font.GothamBold, 12, ACCENT2)
animText.TextTruncate = Enum.TextTruncate.AtEnd
onAnimCallback = function(t) animText.Text = t end

local statsRow = new("Frame", { Size = UDim2.new(1, -6, 0, 42), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, combatPage)
round(statsRow, 10)
label(statsRow, "Weaves Triggered", UDim2.new(0.6, 0, 1, 0), UDim2.fromOffset(14, 0), Enum.Font.GothamMedium, 14, MUTED)
local statsValue = label(statsRow, "0", UDim2.new(0.4, -14, 1, 0), UDim2.new(0.6, 0, 0, 0),
    Enum.Font.GothamBlack, 18, WHITE, Enum.TextXAlignment.Right)
grad(statsValue)
onWeaveCallback = function() statsValue.Text = tostring(weaveCount) end

-- STYLES (AUTOMATED ENGINE INTEL - NO MANUAL SLIDERS NEEDED)
local intelHeader = new("Frame", { Size = UDim2.new(1, -6, 0, 56), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, stylesPage)
round(intelHeader, 10)
label(intelHeader, "AUTO-ADAPTIVE APEX ENGINE", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(14, 8), Enum.Font.GothamBold, 13, ACCENT2)
label(intelHeader, "Keyframe Hit Hook + 14 Calibrated Style Offsets", UDim2.new(1, -20, 0, 16), UDim2.fromOffset(14, 28), Enum.Font.Gotham, 11, MUTED)

local function makeStyleInfo(name, timing, desc)
    local row = new("Frame", { Size = UDim2.new(1, -6, 0, 38), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, stylesPage)
    round(row, 8)
    label(row, name, UDim2.new(0.45, 0, 1, 0), UDim2.fromOffset(14, 0), Enum.Font.GothamMedium, 13, WHITE)
    local tVal = label(row, timing, UDim2.new(0.5, -14, 1, 0), UDim2.new(0.5, 0, 0, 0), Enum.Font.GothamBold, 12, ACCENT, Enum.TextXAlignment.Right)
    return row
end

makeStyleInfo("Default / Street", "Marker / 0.22s", "Hits at 0.35s")
makeStyleInfo("Boxing", "0.14s", "Hits at 0.24s")
makeStyleInfo("Karate", "0.16s", "Hits at 0.26s")
makeStyleInfo("Taekwondo", "0.19s", "Hits at 0.29s")
makeStyleInfo("Nekoashi", "0.18s", "Hits at 0.28s")
makeStyleInfo("Kendo / Swords", "0.26s", "Hits at 0.37s")
makeStyleInfo("Wrestling", "0.30s", "Hits at 0.42s")
makeStyleInfo("Destroyer", "0.24s", "Hits at 0.35s")
makeStyleInfo("Aikido", "0.22s", "Hits at 0.32s")
makeStyleInfo("Heavy / Critical", "Marker / 0.38s", "Hits at 0.50s")

----------------------------------------------------------------
-- YEN & ECONOMY HUB
----------------------------------------------------------------
local YEN_HUBS = {
    {
        name = "8-Eleven Store (Manager)",
        tag = "Restock & Register Shift (Top Yen)",
        pos = Vector3.new(199.4, -10.2, 91.0),
        color = Color3.fromRGB(255, 185, 30),
    },
    {
        name = "Police Station (Officer Kuroda)",
        tag = "Patrol Salary & Combat Bounties",
        pos = Vector3.new(2.9, -10.1, 201.2),
        color = Color3.fromRGB(80, 165, 255),
    },
    {
        name = "Science Lab Mop Spawner",
        tag = "Cleaning Quest (Mop 4 Puddles)",
        pos = Vector3.new(-99.9, 4.1, -207.0),
        color = Color3.fromRGB(100, 255, 140),
    },
    {
        name = "Fight Club (Ringmaster)",
        tag = "Sparring Bouts & High-Stakes Bets",
        pos = Vector3.new(-26.3, -44.6, 195.9),
        color = Color3.fromRGB(255, 80, 80),
    },
    {
        name = "Hidden Dealer (Pawn Shop)",
        tag = "Sell Drops & Items for Cash",
        pos = Vector3.new(273.5, -10.6, -312.5),
        color = Color3.fromRGB(220, 100, 255),
    },
    {
        name = "Spray Paint Tagger",
        tag = "Graffiti Tagging Missions",
        pos = Vector3.new(167.1, -10.4, 174.1),
        color = Color3.fromRGB(255, 230, 80),
    },
}

local waypointInstances = {}
local hubDistanceLabels = {}

local function createYenWaypoints()
    local folder = Instance.new("Folder")
    folder.Name = "IshinYenWaypoints"
    folder.Parent = workspace
    table.insert(waypointInstances, folder)

    for _, hub in ipairs(YEN_HUBS) do
        local anchorPart = Instance.new("Part")
        anchorPart.Name = "Waypoint_" .. hub.name:gsub("%s+", "")
        anchorPart.Size = Vector3.new(1, 1, 1)
        anchorPart.Position = hub.pos
        anchorPart.Anchored = true
        anchorPart.CanCollide = false
        anchorPart.CanQuery = false
        anchorPart.CanTouch = false
        anchorPart.Transparency = 1
        anchorPart.Parent = folder
        table.insert(waypointInstances, anchorPart)

        local bb = Instance.new("BillboardGui")
        bb.Adornee = anchorPart
        bb.Size = UDim2.fromOffset(150, 42)
        bb.AlwaysOnTop = true
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.Enabled = state.YenEspEnabled
        bb.Parent = anchorPart
        table.insert(waypointInstances, bb)

        local frame = Instance.new("Frame", bb)
        frame.Size = UDim2.fromScale(1, 1)
        frame.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
        frame.BackgroundTransparency = 0.15
        local cr = Instance.new("UICorner", frame)
        cr.CornerRadius = UDim.new(0, 8)
        local st = Instance.new("UIStroke", frame)
        st.Color = hub.color
        st.Thickness = 1.2

        local t = Instance.new("TextLabel", frame)
        t.Size = UDim2.new(1, -8, 0.55, 0)
        t.Position = UDim2.fromOffset(4, 2)
        t.BackgroundTransparency = 1
        t.TextColor3 = Color3.fromRGB(255, 255, 255)
        t.Font = Enum.Font.GothamBold
        t.TextSize = 10
        t.Text = hub.name

        local d = Instance.new("TextLabel", frame)
        d.Size = UDim2.new(1, -8, 0.45, 0)
        d.Position = UDim2.new(0, 4, 0.55, -2)
        d.BackgroundTransparency = 1
        d.TextColor3 = hub.color
        d.Font = Enum.Font.GothamMedium
        d.TextSize = 10
        d.Text = "...m"

        table.insert(hubDistanceLabels, { label = d, pos = hub.pos, isBillboard = true })
    end
end

createYenWaypoints()

local function setYenWaypointsVisible(visible)
    for _, inst in ipairs(waypointInstances) do
        if inst:IsA("BillboardGui") then
            inst.Enabled = visible
        end
    end
end

local function getLiveWallet()
    local val = 0
    pcall(function()
        local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local gui7 = pgui and pgui:FindFirstChild("7431305A313A45DD86BBC5B664FB55D1")
        local walletLabel = gui7 and gui7:FindFirstChild("WalletFrame", true) and gui7.WalletFrame:FindFirstChild("Label", true)
        if walletLabel then
            local clean = walletLabel.Text:gsub("[^%d]", "")
            val = tonumber(clean) or 0
        end
    end)
    return val
end

local function getLiveClubFunds()
    local text = "¥ 85,500"
    pcall(function()
        local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local gui7 = pgui and pgui:FindFirstChild("7431305A313A45DD86BBC5B664FB55D1")
        local fundsLabel = gui7 and gui7:FindFirstChild("FundsLabel", true)
        if fundsLabel and fundsLabel.Text ~= "" then
            text = fundsLabel.Text:gsub("Funds:%s*", "")
        end
    end)
    return text
end

-- Live Economy Status Card
local yenCard = new("Frame", { Size = UDim2.new(1, -6, 0, 78), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, yenPage)
round(yenCard, 10)
label(yenCard, "WALLET BALANCE", UDim2.new(0.5, 0, 0, 16), UDim2.fromOffset(14, 8), Enum.Font.GothamMedium, 11, MUTED)
local walletValueLabel = label(yenCard, "¥ 8,600", UDim2.new(0.5, 0, 0, 24), UDim2.fromOffset(14, 24), Enum.Font.GothamBlack, 18, Color3.fromRGB(255, 215, 60))

label(yenCard, "CLUB TREASURY", UDim2.new(0.5, -14, 0, 16), UDim2.new(0.5, 0, 0, 8), Enum.Font.GothamMedium, 11, MUTED, Enum.TextXAlignment.Right)
local clubValueLabel = label(yenCard, "¥ 85,500", UDim2.new(0.5, -14, 0, 24), UDim2.new(0.5, 0, 0, 24), Enum.Font.GothamBold, 15, ACCENT2, Enum.TextXAlignment.Right)

local sessionGainLabel = label(yenCard, "Session Gain: +¥ 0", UDim2.new(1, -28, 0, 16), UDim2.fromOffset(14, 54), Enum.Font.GothamMedium, 11, GREEN)

makeButton(yenPage, "Club Treasury & Payouts", "Open Treasury", function()
    local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local gui7 = pgui and pgui:FindFirstChild("7431305A313A45DD86BBC5B664FB55D1")
    local cf = gui7 and gui7:FindFirstChild("ClubFundsContainer")
    if cf then
        cf.Visible = not cf.Visible
        toast(cf.Visible and "Club Treasury Opened!" or "Club Treasury Closed", ACCENT)
    else
        toast("Club Funds not found", RED)
    end
end)

makeButton(yenPage, "Claim In-Game Promo Codes", "Open Codes", function()
    local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local gui7 = pgui and pgui:FindFirstChild("7431305A313A45DD86BBC5B664FB55D1")
    local codes = gui7 and gui7:FindFirstChild("CodesContainer")
    if codes then
        codes.Visible = not codes.Visible
        toast(codes.Visible and "Codes Menu Opened!" or "Codes Menu Closed", ACCENT)
    else
        toast("Codes Menu not found", RED)
    end
end)

makeToggle(yenPage, "Auto-Trigger Job Prompts", state.AutoJobPrompts, function(v)
    state.AutoJobPrompts = v
    toast("Auto Job Prompts " .. (v and "ON" or "OFF"), v and GREEN or RED)
end)

makeToggle(yenPage, "Show Yen Hub Waypoints", state.YenEspEnabled, function(v)
    state.YenEspEnabled = v
    setYenWaypointsVisible(v)
    toast("Yen Waypoints " .. (v and "ON" or "OFF"), v and GREEN or RED)
end)

local hubsHeader = new("Frame", { Size = UDim2.new(1, -6, 0, 32), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, yenPage)
round(hubsHeader, 8)
label(hubsHeader, "TOP YEN EARNING HUBS IN ISHIN", UDim2.new(1, -20, 1, 0), UDim2.fromOffset(14, 0), Enum.Font.GothamBold, 12, ACCENT2)

local function makeHubRow(name, tag, pos, color)
    local row = new("Frame", { Size = UDim2.new(1, -6, 0, 48), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, yenPage)
    round(row, 8)
    label(row, name, UDim2.new(0.65, 0, 0, 20), UDim2.fromOffset(14, 6), Enum.Font.GothamBold, 12, WHITE)
    label(row, tag, UDim2.new(0.65, 0, 0, 16), UDim2.fromOffset(14, 26), Enum.Font.Gotham, 10, MUTED)
    local distLbl = label(row, "...m", UDim2.new(0.35, -14, 1, 0), UDim2.new(0.65, 0, 0, 0), Enum.Font.GothamBold, 12, color, Enum.TextXAlignment.Right)
    table.insert(hubDistanceLabels, { label = distLbl, pos = pos, isBillboard = false })
    return row
end

for _, hub in ipairs(YEN_HUBS) do
    makeHubRow(hub.name, hub.tag, hub.pos, hub.color)
end

-- Telemetry & Auto-Prompt Listeners
local initialWallet = nil
local lastYenTelemetryCheck = 0

trackConn(RunService.Heartbeat:Connect(function()
    local now = os.clock()
    if now - lastYenTelemetryCheck < 0.35 then return end
    lastYenTelemetryCheck = now

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local myPos = hrp and hrp.Position or Vector3.new()

    for _, item in ipairs(hubDistanceLabels) do
        local dist = math.floor((item.pos - myPos).Magnitude)
        if item.isBillboard then
            item.label.Text = dist .. " studs"
        else
            item.label.Text = dist .. "m"
        end
    end

    local curWallet = getLiveWallet()
    if initialWallet == nil and curWallet > 0 then
        initialWallet = curWallet
    end
    if curWallet > 0 then
        walletValueLabel.Text = "¥ " .. string.format("%d", curWallet):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    end
    clubValueLabel.Text = getLiveClubFunds()
    if initialWallet then
        local gain = curWallet - initialWallet
        sessionGainLabel.Text = "Session Gain: " .. (gain >= 0 and "+¥ " or "-¥ ") .. string.format("%d", math.abs(gain))
    end
end))

local pps = game:GetService("ProximityPromptService")
trackConn(pps.PromptShown:Connect(function(prompt)
    if not state.AutoJobPrompts then return end
    task.spawn(function()
        task.wait(0.06)
        pcall(function()
            if typeof(fireproximityprompt) == "function" then
                fireproximityprompt(prompt)
            end
        end)
    end)
end))

-- VISUALS
makeToggle(visualsPage, "Show Range Circle", state.ShowCircle, function(v) state.ShowCircle = v end)
makeSlider(visualsPage, "Ring Thickness", 0.2, 3, state.RingThickness, 1, "", function(v) state.RingThickness = v end)
makeSlider(visualsPage, "Fill Opacity", 0.3, 1, state.FillOpacity, 2, "", function(v) state.FillOpacity = v end)

-- PLAYER COMBAT ESP (Health, Name, Distance, Style, Crit CD)
local espHeader = new("Frame", { Size = UDim2.new(1, -6, 0, 32), BackgroundColor3 = PANEL, BorderSizePixel = 0 }, visualsPage)
round(espHeader, 8)
label(espHeader, "PLAYER COMBAT ESP", UDim2.new(1, -20, 1, 0), UDim2.fromOffset(14, 0), Enum.Font.GothamBold, 12, ACCENT2)

makeToggle(visualsPage, "Enable Player ESP", state.PlayerEsp, function(v) state.PlayerEsp = v end)
makeSlider(visualsPage, "ESP Max Distance", 20, 250, state.EspMaxDistance, 0, " studs", function(v) state.EspMaxDistance = v end)
makeToggle(visualsPage, "Show Player Name", state.EspShowName, function(v) state.EspShowName = v end)
makeToggle(visualsPage, "Show Health Bar & HP", state.EspShowHealth, function(v) state.EspShowHealth = v end)
makeToggle(visualsPage, "Show Distance", state.EspShowDistance, function(v) state.EspShowDistance = v end)
makeToggle(visualsPage, "Show Fighting Style", state.EspShowStyle, function(v) state.EspShowStyle = v end)
makeToggle(visualsPage, "Show Crit Cooldown", state.EspShowCrit, function(v) state.EspShowCrit = v end)

-- BINDS
makeKeybind(bindsPage, "Toggle Weave", "ToggleKey")
makeKeybind(bindsPage, "Hide / Show GUI", "HideKey")

----------------------------------------------------------------
-- TOAST NOTIFICATION
-----------------------------------------------------------------
local toastFrame = new("Frame", {
    Size = UDim2.fromOffset(200, 38), AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, -40), BackgroundColor3 = BG,
    BorderSizePixel = 0, Visible = false,
}, gui)
round(toastFrame, 19)
new("UIStroke", { Color = ACCENT, Thickness = 1.5 }, toastFrame)
local toastDot = new("Frame", {
    Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(16, 14),
    BackgroundColor3 = WHITE, BorderSizePixel = 0,
}, toastFrame)
round(toastDot, 5)
local toastLabel = label(toastFrame, "", UDim2.new(1, -40, 1, 0), UDim2.fromOffset(34, 0),
    Enum.Font.GothamBold, 14, WHITE)

local toastToken = 0
toast = function(text, color)
    toastToken += 1
    local mine = toastToken
    toastLabel.Text = text
    toastDot.BackgroundColor3 = color or ACCENT
    toastFrame.Position = UDim2.new(0.5, 0, 1, -40)
    toastFrame.Visible = true
    tween(toastFrame, 0.25, { Position = UDim2.new(0.5, 0, 1, -56) }, Enum.EasingStyle.Back)
    task.delay(1.8, function()
        if toastToken == mine then
            tween(toastFrame, 0.25, { Position = UDim2.new(0.5, 0, 1, -40) })
            task.delay(0.26, function()
                if toastToken == mine then toastFrame.Visible = false end
            end)
        end
    end)
end

----------------------------------------------------------------
-- KEYBOARD INPUT LISTENER
----------------------------------------------------------------
local guiVisible = true
local function setGuiVisible(v)
    guiVisible = v
    if v then
        main.Visible = true
        tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
    else
        tween(scale, 0.2, { Scale = 0.92 })
        task.delay(0.22, function()
            if not guiVisible then main.Visible = false end
        end)
    end
end

local inputConn = trackConn(UserInputService.InputBegan:Connect(function(input, gp)
    -- PRIORITY 2: If player physically clicks M1 (MouseButton1) or M2 (MouseButton2), stop blocking immediately!
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        onPlayerAttackInput()
        return
    end

    if not isScriptSimulatingInput then
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            onPlayerAttackInput()
            return
        end

        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.R then
                onPlayerAttackInput()
            end
        end
    end

    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    
    if listeningKey then
        local l = listeningKey
        listeningKey = nil
        if input.KeyCode ~= Enum.KeyCode.Escape then
            state[l.key] = input.KeyCode
        end
        l.button.Text = state[l.key].Name
        tween(l.button, 0.15, { BackgroundColor3 = OFFC })
        sub.Text = "Hide / show: " .. state.HideKey.Name
        return
    end
    
    if gp then return end
    
    if input.KeyCode == state.ToggleKey then
        setEnabled(not state.Enabled)
    elseif input.KeyCode == state.HideKey then
        setGuiVisible(not guiVisible)
    end
end))

local inputEndedConn = trackConn(UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == state.BlockKey and not isBlocking then
        pcall(function()
            if VirtualInputManager then
                VirtualInputManager:SendKeyEvent(false, state.BlockKey, false, game)
            end
        end)
    end
end))

-- Initialize UI State
showTab(1)
refreshPill()
toast("Auto Weave Loaded!", GREEN)

----------------------------------------------------------------
-- CLEANUP HANDLER
----------------------------------------------------------------
local function cleanup()
    state.Enabled = false
    if getgenv then getgenv().AutoWeaveLoaded = false end
    for _, conn in ipairs(scriptConnections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(scriptConnections)
    
    stopBlock()
    releaseMovementComp()
    
    if typeof(getconnections) == "function" then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character then
                local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                local anim = hum and hum:FindFirstChildOfClass("Animator")
                if anim then
                    pcall(function()
                        for _, c in ipairs(getconnections(anim.AnimationPlayed)) do
                            pcall(function() c:Disconnect() end)
                            pcall(function() c:Disable() end)
                        end
                    end)
                end
            end
        end
    end
    
    pcall(function() anchor:Destroy() end)
    for _, inst in ipairs(waypointInstances) do
        pcall(function() inst:Destroy() end)
    end
    for plr, esp in pairs(playerEspInstances) do
        pcall(function() esp.bb:Destroy() end)
    end
    table.clear(playerEspInstances)
    pcall(function() gui:Destroy() end)
end

if getgenv then
    getgenv().AutoWeaveLoaded = true
    getgenv().AutoWeaveUnload = cleanup
end

print("[AutoWeave Ultimate] Successfully initialized.")
