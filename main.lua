local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Core state tracking
local isScriptActive = true
local isAlive = false
local hasDiedOnce = false
local connections = {}
local branchConnections = {}
local scriptStartTime = os.clock()

-- Settings state (ON by default)
local ambienceEnabled = false
local warningsEnabled = true
local timestampsEnabled = true
local menuKeybind = Enum.KeyCode.N
local isBindingKey = false

-- Forward declarations for programmatic UI updaters
local updateAmbienceUI, updateWarningsUI, updateTimestampsUI

-- Cooldown & Anti-Repeat tracking
local lastMessageTime = 0
local COOLDOWN_DURATION = 0.5
local lastSentMessages = {}

-- Dynamic chat channel detection
local rbxGeneralChannel
local legacyChatEvents

local function getChatChannel()
    if rbxGeneralChannel then return "TextChatService" end

    if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
        local textChannels = TextChatService:FindFirstChild("TextChannels")
        if textChannels then
            rbxGeneralChannel = textChannels:FindFirstChild("RBXGeneral")
            if rbxGeneralChannel then return "TextChatService" end
        end
    end

    if not legacyChatEvents then
        legacyChatEvents = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
    end

    if legacyChatEvents and legacyChatEvents:FindFirstChild("SayMessageRequest") then
        return "LegacyChat"
    end

    return nil
end

local function sendChatMessage(message)
    if not isScriptActive then return end
    
    local currentTime = os.clock()
    if currentTime - lastMessageTime < COOLDOWN_DURATION then return end

    local channelType = getChatChannel()
    if channelType == "TextChatService" and rbxGeneralChannel then
        lastMessageTime = currentTime
        rbxGeneralChannel:SendAsync(message)
    elseif channelType == "LegacyChat" and legacyChatEvents then
        local sayReq = legacyChatEvents:FindFirstChild("SayMessageRequest")
        if sayReq then
            lastMessageTime = currentTime
            sayReq:FireServer(message, "All")
        end
    end
end

-- ==========================================
-- 💀 DEATH & REVIVAL LOGIC
-- ==========================================
local deathMessages = {
    "I'm done for... keep moving without me!",
    "They got me... don't let 'em get you...",
    "Agh, this is it... save yourselves!",
    "I'm out... goodluck lads.",
    "Good luck, you guys... I'm finished."
}

local reviveMessages = {
    "Whoa, thought I was a goner. Thanks for the save.",
    "I'm back! Let's make 'em pay for that.",
    "Ah, my head... alright, I owe you one.",
    "I ain't dead yet! Hand me a flashlight.",
    "Back on my feet. Let's get out of this hellhole."
}

local charConnections = {}
local lastStateChangeTime = 0
local STATE_CHANGE_COOLDOWN = 3 -- Cooldown between state transitions

local function setupCharacter(character)
    if not character then return end
    
    -- Clean up previous character connections to prevent memory bloat
    for _, conn in ipairs(charConnections) do
        if conn.Connected then conn:Disconnect() end
    end
    table.clear(charConnections)

    local humanoid = character:WaitForChild("Humanoid", 10)
    
    if humanoid then
        local now = os.clock()

        -- Process revive only if state transition cooldown has passed
        if humanoid.Health > 0 and hasDiedOnce then
            if (now - lastStateChangeTime) >= STATE_CHANGE_COOLDOWN then
                lastStateChangeTime = now
                isAlive = true
                
                ambienceEnabled = true
                warningsEnabled = true
                timestampsEnabled = true
                
                if updateAmbienceUI then updateAmbienceUI(true) end
                if updateWarningsUI then updateWarningsUI(true) end
                if updateTimestampsUI then updateTimestampsUI(true) end

                local msg = reviveMessages[math.random(1, #reviveMessages)]
                sendChatMessage("[Back in action] " .. msg)
            end
        elseif humanoid.Health > 0 then
            isAlive = true
        end

        local function onDeath()
            local currentTime = os.clock()

            -- Require both alive state and minimum time gap since last state change
            if isAlive and (currentTime - lastStateChangeTime >= STATE_CHANGE_COOLDOWN) then
                lastStateChangeTime = currentTime
                isAlive = false
                hasDiedOnce = true
                
                -- Silently disable settings on death
                ambienceEnabled = false
                warningsEnabled = false
                timestampsEnabled = false
                
                if updateAmbienceUI then updateAmbienceUI(false) end
                if updateWarningsUI then updateWarningsUI(false) end
                if updateTimestampsUI then updateTimestampsUI(false) end

                local msg = deathMessages[math.random(1, #deathMessages)]
                sendChatMessage("[Dying message] " .. msg)
            end
        end

        -- 1. Standard Roblox Death Detection
        table.insert(charConnections, humanoid.Died:Connect(onDeath))
        
        table.insert(charConnections, humanoid.HealthChanged:Connect(function(health)
            if health <= 0 then
                onDeath()
            end
        end))

        -- 2. Ancestry Detection (Model deleted/moved from Workspace)
        table.insert(charConnections, character.AncestryChanged:Connect(function(_, newParent)
            if not newParent or newParent ~= workspace then
                onDeath()
            end
        end))

        -- 3. Failsafe Polling Loop
        task.spawn(function()
            while isAlive and character and character.Parent and isScriptActive do
                if not character:FindFirstChild("HumanoidRootPart") then
                    onDeath()
                    break
                end
                
                if character:GetAttribute("IsDead") == true or character:GetAttribute("Dead") == true then
                    onDeath()
                    break
                end

                task.wait(1)
            end
        end)
    end
end

table.insert(connections, player.CharacterAdded:Connect(setupCharacter))
if player.Character then
    task.spawn(setupCharacter, player.Character)
end

-- ==========================================
-- 🗃️ CALLOUTS & DIALOGUE DATA
-- ==========================================
local callouts = {
    Main = {
        {name = "ENTITY", branch = "ENTITY"},
        {name = "RETREAT", messages = {"Move back!", "Back away!", "Retreat!", "Fall back!", "Get out of there!"}},
        {name = "MOVE", messages = {"Go! Go! Go!", "Mooove out!", "Hurry it up!", "Make haste!", "Keep pushing forward!"}},
        {name = "OBJECTIVE", messages = {"Do something!", "Mind the objectives", "Do the tasks!", "Is that taking forever or what?", "Focus on the objective!"}},
        {name = "ITEM", branch = "ITEM"},
        {name = "LOOKOUT", branch = "LOOKOUT"},
        {name = "HELP", messages = {"Heeelp me!", "I need help over here!", "HELP!", "I need a hand over here!", "I'm in trouble!"}},
        {name = "MISCELLANEOUS", branch = "MISCELLANEOUS"},
    },
    ENTITY = {
        {name = "Angler", messages = {"Anglerfish!", "Angler!", "We got one Angler coming!", "Watch out for Angler!", "Heads up, Angler is coming!"}},
        {name = "Frogger", messages = {"Frogger!", "Orange fish!", "We got ourselves a Frogger!", "Watch out for that Frogger bouncing!", "Heads up for Frogger!"}},
        {name = "Blitz", messages = {"We got a Rusher!", "Fast one!", "Bolter!", "Watch out, Blitz is rushing!", "Heads up for Blitz!"}},
        {name = "Chainsmoker", messages = {"Smokey!", "Green one!", "Chains!", "Watch out for Chains!", "Heads up, Smokey's coming!"}},
        {name = "Pinkie", messages = {"Pinkie!", "Pink eye!", "Pink fish!", "I can hear that pink one coming!", "Heads up for the silent one!"}},
        {name = "Pandemonium", messages = {"Foul demon!", "Pandemonium!", "Panzer!", "Watch out for Pandemonium!", "Another minigame, huh"}},
        {name = "Eyefestation", messages = {"Eyefestation!", "Don't look at it!", "Keep your head down!", "Don't look at it, it will fry you", "Whatever you do, do not listen to the voices"}},
        {name = "Wall Dweller", messages = {"Wall Dweller!", "Check the walls!", "Look behind you!", "Watch out for Wall Dwellers!", "Heads up, check the corners!"}},
        {name = "Special", messages = {"Something wicked is coming!", "A terrible one approaches!", "Special Noder!", "Watch out, something bad is coming!", "Heads up for a special!"}},
    },
    ITEM = {
        {name = "Lights", messages = {"We need a light source", "Where's the lights?", "Light it up!", "Light up, it's getting dark", "Light up the place, will yeah?"}},
        {name = "Medical", messages = {"I'm hurt badly!", "I need a medic!", "Where the bloody crocus?", "Wait up, someone's hurt!", "Hey lads, need medical!"}},
        {name = "Card", messages = {"Card!", "Where's the card at?", "Pass the card!", "We got a locked door!", "We need a keycard!"}},
        {name = "Other", messages = {"Found something?", "Search these rooms, might be something we can use", "Spare items?", "Look for supplies!", "Hey, check out this area!"}},
    },
    LOOKOUT = {
        {name = "Item", messages = {"Item over here!", "Hey, check this out", "Yo, take this", "Hey lads, I found an item!", "We got gear here!"}},
        {name = "Monster", messages = {"I sense a dark presence", "Danger is lurking", "Watch it", "Watch out, bad presence!", "Heads up, danger ahead!"}},
    },
    MISCELLANEOUS = {
        {name = "Nervous", messages = {"Did you feel that vibration?", "I got a bad feeling about this area...", "It's way too quiet in here", "My hands won't stop shaking", "Something is watching us, I know it"}},
        {name = "Relief", messages = {"Phew, that was way too close!", "I think we actually lost it", "Is everybody still alive?", "It passed... okay, deep breaths", "Made it through that one in one piece!"}},
        {name = "Motivation", messages = {"We can actually make it out of here!", "Don't give up now, keep pushing!", "Keep your chin up, we're surviving!", "We've made it this far, don't stop now!", "Stay sharp! We can beat this place!"}},
        {name = "Observations", messages = {"Keep your eyes peeled", "Watch your step around here", "Stay aware of your surroundings", "Check the corners, don't miss anything", "Keep an eye out for details"}},
        {name = "Waiting", messages = {"Are we moving or what?", "I'm not standing around waiting to die", "Let's get a move on", "Move it, we're sitting ducks here!", "Hurry up, time is ticking!"}}
    }
}

local ambientDialogues = {
    {prefix = "[Mutters]", text = "Why did Urbanshade send us down here again?"},
    {prefix = "[Mutters]", text = "I don't get paid enough for this..."},
    {prefix = "[Mutters]", text = "Remind me why I signed that Expendable contract?"},
    {prefix = "[Mutters]", text = "The water pressure outside this glass is insane."},
    {prefix = "[Mutters]", text = "My ears won't stop popping from the depth."},
    {prefix = "[Mutters]", text = "I hope that crystal is worth all this trouble."},
    {prefix = "[Mutters]", text = "How deep underwater are we right now?"},
    {prefix = "[Mutters]", text = "Urbanshade really needs better safety protocols."},
    {prefix = "[Mutters]", text = "If we actually make it back to the surface, I'm quitting."},
    {prefix = "[Mutters]", text = "I'm starting to forget what sunlight feels like."},
    {prefix = "[Whispers]", text = "Did anyone else hear something crawling in the pipes?"},
    {prefix = "[Whispers]", text = "Is it just me, or are these areas getting darker?"},
    {prefix = "[Whispers]", text = "This facility feels like a giant metal coffin."},
    {prefix = "[Whispers]", text = "I swear I saw something moving behind that door."},
    {prefix = "[Whispers]", text = "Just keep moving, don't look back."},
    {prefix = "[Whispers]", text = "Keep your voice down... sound travels too well in these parts."},
    {prefix = "[Whispers]", text = "Did the lights just flicker, or is my mind playing tricks on me?"},
    {prefix = "[Whispers]", text = "I keep seeing shadows darting just outside my peripheral vision."},
    {prefix = "[Whispers]", text = "Don't stand too close to the vents. There could be an impostor inside"},
    {prefix = "[Whispers]", text = "Man, why did I agree to go down here in the first place?"}
}

local bickerLines = {
    AmbienceOff = {
        "[Hushed] Alright, keeping my mouth shut for a while.",
        "[Hushed] Going quiet. No more useless chatter.",
        "[Hushed] Zipping it. Focus on surviving, not talking."
    },
    AmbienceOn = {
        "[Chatter] Silence is getting uncomfortable. Back to talking.",
        "[Chatter] Guards down, I can't stay quiet forever.",
        "[Chatter] Alright, back to keeping ourselves sane with talk."
    },
    WarningsOff = {
        "[Careless] You're on your own for spotting things now.",
        "[Careless] Stopping entity callouts. Keep your own eyes open.",
        "[Careless] No more warnings. Hope your ears are sharp."
    },
    WarningsOn = {
        "[Alert] Fine, I'll resume keeping an eye out for horrors.",
        "[Alert] Warnings back on. Don't say I didn't warn you.",
        "[Alert] Re-engaging threat callouts. Watch your back."
    },
    TimestampsOff = {
        "[Untracked] Stopping time checks. Time isn't helping us anyway.",
        "[Untracked] Done watching the clock. It only makes me anxious.",
        "[Untracked] No more keeping track of the minutes."
    },
    TimestampsOn = {
        "[Tracking] Resuming clock watching. Every minute counts down here.",
        "[Tracking] Keeping track of time again. Let's see how long we last.",
        "[Tracking] Timestamps back on. Stay aware of the hours."
    }
}

local timestampMilestones = {
    [15] = {
        "[Time] 15 minutes in. Still breathing, at least.",
        "[Time] Quarter of an hour gone already. Stay sharp.",
        "[Time] 15 minutes down. Feels like hours underwater."
    },
    [30] = {
        "[Time] Looks like the pizza ain't free, it's been 30 minutes already.",
        "[Time] Half an hour spent down in this hellhole.",
        "[Time] 30 minutes mark. We're still kickin'."
    },
    [45] = {
        "[Time] 45 minutes... three quarters of an hour down here.",
        "[Time] Almost a full hour in this dump. Keep moving.",
        "[Time] 45 minutes. Hope someone is tracking our route."
    },
    [60] = {
        "[Time] One whole hour. We really survived a full hour?",
        "[Time] 60 minutes deep. Time is slipping away from us.",
        "[Time] An hour's gone by. The surface feels like a dream."
    },
    [75] = {
        "[Time] 75 minutes... 1 hour and 15 minutes of non-stop stress.",
        "[Time] An hour and fifteen minutes. It just keeps getting darker.",
        "[Time] 75 minutes in. How much deeper can this place go?"
    },
    [90] = {
        "[Time] Hour and a half down. 90 whole minutes.",
        "[Time] 90 minutes in this place. My mind is starting to play tricks.",
        "[Time] An hour and thirty minutes. Stay focused on the objective."
    },
    [105] = {
        "[Time] 105 minutes... almost two full hours.",
        "[Time] Hour and forty-five. We've come too far to die now.",
        "[Time] 105 minutes down. Keep pushing through the dark."
    },
    [120] = {
        "[Time] Two full hours underwater. Unbelievable.",
        "[Time] 120 minutes in this coffin. We're legends if we make it out.",
        "[Time] 2 hours mark. I can barely count the minutes anymore."
    }
}

-- ==========================================
-- ⚙️ LOGIC & FUNCTIONALITY
-- ==========================================

local function getRandomMessage(messageList, poolKey)
    if #messageList <= 1 then return messageList[1] end
    local choice
    repeat
        choice = messageList[math.random(1, #messageList)]
    until choice ~= lastSentMessages[poolKey]
    
    lastSentMessages[poolKey] = choice
    return choice
end

local unusedDialogues = {}
local lastAmbientDialogue = nil

local function getRandomDialogue()
    if #unusedDialogues == 0 then
        for _, entry in ipairs(ambientDialogues) do
            table.insert(unusedDialogues, entry)
        end
    end
    
    local index, choice
    repeat
        index = math.random(1, #unusedDialogues)
        choice = unusedDialogues[index]
    until choice.text ~= lastAmbientDialogue or #unusedDialogues == 1
    
    lastAmbientDialogue = choice.text
    return table.remove(unusedDialogues, index)
end

local function triggerBickerLine(category)
    local pool = bickerLines[category]
    if pool then
        local line = getRandomMessage(pool, "BICKER_" .. category)
        sendChatMessage(line)
    end
end

-- ==========================================
-- 🎨 UI CREATION
-- ==========================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CalloutsV4"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local floatingToggle = Instance.new("TextButton")
floatingToggle.Size = UDim2.new(0, 45, 0, 45)
floatingToggle.Position = UDim2.new(0, 20, 0.5, -22)
floatingToggle.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
floatingToggle.Text = "💬"
floatingToggle.TextSize = 22
floatingToggle.Visible = false
floatingToggle.Parent = screenGui
Instance.new("UICorner", floatingToggle).CornerRadius = UDim.new(1, 0)

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 250, 0, 350)
mainFrame.Position = UDim2.new(0.5, -125, 0.5, -175)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, 0, 0, 35)
topBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
topBar.BorderSizePixel = 0
topBar.ZIndex = 5
topBar.Parent = mainFrame
Instance.new("UICorner", topBar).CornerRadius = UDim.new(0, 8)

local bottomFix = Instance.new("Frame")
bottomFix.Size = UDim2.new(1, 0, 0, 8)
bottomFix.Position = UDim2.new(0, 0, 1, -8)
bottomFix.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
bottomFix.BorderSizePixel = 0
bottomFix.ZIndex = 5
bottomFix.Parent = topBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -115, 1, 0)
titleLabel.Position = UDim2.new(0, 10, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Callouts V4"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 16
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 6
titleLabel.Parent = topBar

local gearBtn = Instance.new("TextButton")
gearBtn.Size = UDim2.new(0, 35, 0, 35)
gearBtn.Position = UDim2.new(1, -105, 0, 0)
gearBtn.BackgroundTransparency = 1
gearBtn.Text = "⚙"
gearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
gearBtn.Font = Enum.Font.GothamBold
gearBtn.TextSize = 18
gearBtn.ZIndex = 6
gearBtn.Parent = topBar

local minimizeBtn = Instance.new("TextButton")
minimizeBtn.Size = UDim2.new(0, 35, 0, 35)
minimizeBtn.Position = UDim2.new(1, -70, 0, 0)
minimizeBtn.BackgroundTransparency = 1
minimizeBtn.Text = "-"
minimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minimizeBtn.Font = Enum.Font.GothamBold
minimizeBtn.TextSize = 22
minimizeBtn.ZIndex = 6
minimizeBtn.Parent = topBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 35, 0, 35)
closeBtn.Position = UDim2.new(1, -35, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 18
closeBtn.ZIndex = 6
closeBtn.Parent = topBar

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -20, 1, -45)
scrollFrame.Position = UDim2.new(0, 10, 0, 45)
scrollFrame.BackgroundTransparency = 1
scrollFrame.ScrollBarThickness = 3
scrollFrame.ScrollingEnabled = true
scrollFrame.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 5)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scrollFrame

-- ==========================================
-- ⚙️ SETTINGS UI
-- ==========================================
local settingsFrame = Instance.new("Frame")
settingsFrame.Size = UDim2.new(1, -20, 1, -45)
settingsFrame.Position = UDim2.new(0, 10, 0, 45)
settingsFrame.BackgroundTransparency = 1
settingsFrame.Visible = false
settingsFrame.Parent = mainFrame

local settingsListLayout = Instance.new("UIListLayout")
settingsListLayout.Padding = UDim.new(0, 6)
settingsListLayout.SortOrder = Enum.SortOrder.LayoutOrder
settingsListLayout.Parent = settingsFrame

local function createSettingToggle(labelText, defaultState, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 38)
    btn.BackgroundColor3 = defaultState and Color3.fromRGB(40, 110, 60) or Color3.fromRGB(110, 40, 40)
    btn.Text = labelText .. ": " .. (defaultState and "ON" or "OFF")
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.Gotham
    btn.TextSize = 13
    btn.Parent = settingsFrame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

    local state = defaultState
    
    local function updateUI(newState)
        state = newState
        btn.BackgroundColor3 = state and Color3.fromRGB(40, 110, 60) or Color3.fromRGB(110, 40, 40)
        btn.Text = labelText .. ": " .. (state and "ON" or "OFF")
    end

    table.insert(connections, btn.MouseButton1Click:Connect(function()
        updateUI(not state)
        callback(state, true)
    end))
    
    return updateUI
end

updateAmbienceUI = createSettingToggle("Option A: Ambience", false, function(state, isManual)
    ambienceEnabled = state
    if isManual then triggerBickerLine(state and "AmbienceOn" or "AmbienceOff") end
end)

updateWarningsUI = createSettingToggle("Option B: Warnings", true, function(state, isManual)
    warningsEnabled = state
    if isManual then triggerBickerLine(state and "WarningsOn" or "WarningsOff") end
end)

updateTimestampsUI = createSettingToggle("Option C: Timestamps", true, function(state, isManual)
    timestampsEnabled = state
    if isManual then triggerBickerLine(state and "TimestampsOn" or "TimestampsOff") end
end)

local keybindBtn = Instance.new("TextButton")
keybindBtn.Size = UDim2.new(1, 0, 0, 38)
keybindBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
keybindBtn.Text = "Option D: Menu Keybind [" .. menuKeybind.Name .. "]"
keybindBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
keybindBtn.Font = Enum.Font.Gotham
keybindBtn.TextSize = 13
keybindBtn.Parent = settingsFrame
Instance.new("UICorner", keybindBtn).CornerRadius = UDim.new(0, 6)

table.insert(connections, keybindBtn.MouseButton1Click:Connect(function()
    isBindingKey = true
    keybindBtn.Text = "Option D: Press any key..."
    keybindBtn.BackgroundColor3 = Color3.fromRGB(150, 100, 30)
end))

local confirmFrame = Instance.new("Frame")
confirmFrame.Size = UDim2.new(1, 0, 1, -35)
confirmFrame.Position = UDim2.new(0, 0, 0, 35)
confirmFrame.BackgroundTransparency = 1
confirmFrame.Visible = false
confirmFrame.Parent = mainFrame

local confirmText = Instance.new("TextLabel")
confirmText.Size = UDim2.new(1, -20, 0, 60)
confirmText.Position = UDim2.new(0, 10, 0, 10)
confirmText.BackgroundTransparency = 1
confirmText.Text = "Terminate Callouts V4?\nThis completely disables the script."
confirmText.TextColor3 = Color3.fromRGB(255, 255, 255)
confirmText.Font = Enum.Font.GothamBold
confirmText.TextSize = 14
confirmText.TextWrapped = true
confirmText.Parent = confirmFrame

local yesBtn = Instance.new("TextButton")
yesBtn.Size = UDim2.new(0, 100, 0, 35)
yesBtn.Position = UDim2.new(0, 15, 0, 80)
yesBtn.BackgroundColor3 = Color3.fromRGB(255, 65, 65)
yesBtn.Text = "Terminate"
yesBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
yesBtn.Font = Enum.Font.GothamBold
yesBtn.Parent = confirmFrame
Instance.new("UICorner", yesBtn).CornerRadius = UDim.new(0, 6)

local noBtn = Instance.new("TextButton")
noBtn.Size = UDim2.new(0, 100, 0, 35)
noBtn.Position = UDim2.new(1, -115, 0, 80)
noBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
noBtn.Text = "Cancel"
noBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
noBtn.Font = Enum.Font.GothamBold
noBtn.Parent = confirmFrame
Instance.new("UICorner", noBtn).CornerRadius = UDim.new(0, 6)

-- ==========================================
-- ⚙️ MENU BEHAVIOR
-- ==========================================
local isMinimized = false
local MAX_MENU_HEIGHT = 400

local function resizeMenu(targetHeight)
    local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(mainFrame, tweenInfo, {Size = UDim2.new(0, 250, 0, targetHeight)}):Play()
end

local function updateDynamicSize()
    if confirmFrame.Visible or isMinimized then return end
    local contentHeight = settingsFrame.Visible and settingsListLayout.AbsoluteContentSize.Y or listLayout.AbsoluteContentSize.Y
    local totalHeight = 55 + contentHeight
    local boundedHeight = math.min(totalHeight, MAX_MENU_HEIGHT)
    
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, contentHeight)
    resizeMenu(boundedHeight)
end

table.insert(connections, listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateDynamicSize))
table.insert(connections, settingsListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateDynamicSize))

local function toggleMenu(forceHide)
    if forceHide or mainFrame.Visible then
        mainFrame.Visible = false
        floatingToggle.Visible = true
    else
        mainFrame.Visible = true
        floatingToggle.Visible = false
        if not isMinimized and not confirmFrame.Visible then
            updateDynamicSize()
        end
    end
end

local function clearBranchConnections()
    for _, conn in ipairs(branchConnections) do
        if conn.Connected then conn:Disconnect() end
    end
    table.clear(branchConnections)
end

function loadBranch(branchName)
    clearBranchConnections()

    for _, child in pairs(scrollFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    
    local branchData = callouts[branchName]
    if not branchData then return end

    if branchName ~= "Main" then
        local backBtn = Instance.new("TextButton")
        backBtn.Size = UDim2.new(1, 0, 0, 30)
        backBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        backBtn.Text = "< Back"
        backBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
        backBtn.Font = Enum.Font.GothamBold
        backBtn.TextSize = 14
        backBtn.Parent = scrollFrame
        Instance.new("UICorner", backBtn).CornerRadius = UDim.new(0, 4)

        table.insert(branchConnections, backBtn.MouseButton1Click:Connect(function() loadBranch("Main") end))
    end

    for _, info in ipairs(branchData) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 35)
        btn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
        btn.Text = info.name
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 14
        btn.Parent = scrollFrame
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

        table.insert(branchConnections, btn.MouseButton1Click:Connect(function()
            if info.branch then
                loadBranch(info.branch)
            elseif info.messages and #info.messages > 0 then
                local poolKey = "UI_" .. branchName .. "_" .. info.name
                local rawMsg = getRandomMessage(info.messages, poolKey)
                
                if not rawMsg:match("[!?%.]$") then rawMsg = rawMsg .. "." end
                
                sendChatMessage("[Callout] " .. rawMsg)
                toggleMenu(true)
            end
        end))
    end
end

-- ==========================================
-- AUTOMATED ENTITY CALLOUTS
-- ==========================================
local entityKeywords = {
    {"pinkimonium", "Pandemonium"}, {"ridgepandemonium", "Pandemonium"},
    {"anglemonium", "Pandemonium"}, {"frogermonium", "Pandemonium"},
    {"pandesmoker", "Pandemonium"}, {"blitzmonium", "Pandemonium"},
    {"monium", "Pandemonium"}, {"pandemonium", "Pandemonium"},
    {"angler", "Angler"}, {"froger", "Frogger"}, {"frogger", "Frogger"},
    {"blitz", "Blitz"}, {"chain", "Chainsmoker"}, {"chainsmoker", "Chainsmoker"},
    {"pinkie", "Pinkie"}, 
    {"eyefestation", "Eyefestation"}, {"eyefest", "Eyefestation"}, {"eye", "Eyefestation"},
    {"dweller", "Wall Dweller"}, {"walldweller", "Wall Dweller"}, 
    {"pipsqueak", "Special"}, {"a60", "Special"}, {"a120", "Special"}, {"bleach", "Special"}
}

local function getEntityCallout(entityName)
    local targetCategory = nil
    local lowerEntityName = string.lower(entityName)
    
    for _, mapping in ipairs(entityKeywords) do
        if string.find(lowerEntityName, mapping[1]) then
            targetCategory = mapping[2]
            break
        end
    end

    if not targetCategory then return nil end

    for _, item in ipairs(callouts.ENTITY) do
        if item.name == targetCategory and item.messages then
            return getRandomMessage(item.messages, "AUTO_" .. targetCategory)
        end
    end
    return nil
end

local function onEntitySpawned(child)
    if not isScriptActive or not isAlive or not warningsEnabled then return end
    
    local rawMsg = getEntityCallout(child.Name)
    if rawMsg then
        if not rawMsg:match("[!?%.]$") then rawMsg = rawMsg .. "." end
        sendChatMessage("[Warning] " .. rawMsg)
    end
end

table.insert(connections, workspace.ChildAdded:Connect(onEntitySpawned))

task.defer(function()
    local gameplayFolder = workspace:WaitForChild("GameplayFolder", 10)
    if not isScriptActive then return end 
    
    if gameplayFolder then
        local monstersFolder = gameplayFolder:WaitForChild("Monsters", 10)
        if not isScriptActive then return end
        
        if monstersFolder then
            table.insert(connections, monstersFolder.ChildAdded:Connect(onEntitySpawned))
        end
    end
end)

task.defer(function()
    local roomsFolder = workspace:WaitForChild("Rooms", 10)
    if not isScriptActive or not roomsFolder then return end
    
    local function checkRoomForEyefestation(room)
        if not isScriptActive then return end
        for _, d in ipairs(room:GetDescendants()) do
            if d.Name == "EyefestationSpawn" then onEntitySpawned(d) end
        end
        
        -- Direct connection without global table insert to prevent memory leaks 
        -- Roblox GC handles this when the room is destroyed.
        room.DescendantAdded:Connect(function(d)
            if d.Name == "EyefestationSpawn" then onEntitySpawned(d) end
        end)
    end

    for _, room in ipairs(roomsFolder:GetChildren()) do
        task.defer(function() checkRoomForEyefestation(room) end)
    end
    
    table.insert(connections, roomsFolder.ChildAdded:Connect(function(room)
        task.wait(0.1)
        if isScriptActive then checkRoomForEyefestation(room) end
    end))
end)

-- ==========================================
-- ⏱️ BACKGROUND AMBIENT DIALOGUE LOOP
-- ==========================================
task.spawn(function()
    task.wait(math.random(15, 25))

    while isScriptActive and screenGui and screenGui.Parent do
        if not isScriptActive then break end
        
        if isAlive and ambienceEnabled then 
            local entry = getRandomDialogue()
            sendChatMessage(entry.prefix .. " " .. entry.text)
        end

        local waitTime = math.random(30, 60)
        task.wait(waitTime)
    end
end)

-- ==========================================
-- ⏱️ PERSISTENT TIMESTAMP TRACKER LOOP
-- ==========================================
task.spawn(function()
    local triggeredMilestones = {}

    while isScriptActive and screenGui and screenGui.Parent do
        task.wait(5)
        
        if not isScriptActive or not screenGui or not screenGui.Parent then break end

        local elapsedMinutes = math.floor((os.clock() - scriptStartTime) / 60)

        if timestampsEnabled and isAlive then
            for milestone = 15, 120, 15 do
                if elapsedMinutes >= milestone and not triggeredMilestones[milestone] then
                    triggeredMilestones[milestone] = true
                    local pool = timestampMilestones[milestone]
                    if pool then
                        local msg = getRandomMessage(pool, "TIME_" .. milestone)
                        sendChatMessage(msg)
                    end
                end
            end
        end
    end
end)

-- ==========================================
-- 🖱️ DRAGGING LOGIC
-- ==========================================
local function makeDraggable(guiObject, handle)
    handle = handle or guiObject
    local dragging, dragInput, dragStart, startPos
    
    table.insert(connections, handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = guiObject.Position
            
            local inputChangedConn
            inputChangedConn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then 
                    dragging = false 
                    inputChangedConn:Disconnect()
                end
            end)
        end
    end))

    table.insert(connections, handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))

    table.insert(connections, UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            guiObject.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))
end

makeDraggable(mainFrame, topBar)
makeDraggable(floatingToggle)

-- ==========================================
-- ⌨️ UI BUTTON HANDLING & KEYBINDS
-- ==========================================
table.insert(connections, floatingToggle.MouseButton1Click:Connect(function()
    toggleMenu(false)
end))

table.insert(connections, gearBtn.MouseButton1Click:Connect(function()
    if isMinimized or confirmFrame.Visible then return end
    settingsFrame.Visible = not settingsFrame.Visible
    scrollFrame.Visible = not settingsFrame.Visible
    updateDynamicSize()
end))

table.insert(connections, minimizeBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        minimizeBtn.Text = "+"
        scrollFrame.Visible = false
        settingsFrame.Visible = false
        confirmFrame.Visible = false
        resizeMenu(35)
    else
        minimizeBtn.Text = "-"
        scrollFrame.Visible = not settingsFrame.Visible
        confirmFrame.Visible = false
        updateDynamicSize()
    end
end))

table.insert(connections, closeBtn.MouseButton1Click:Connect(function()
    if isMinimized then return end 
    scrollFrame.Visible = false
    settingsFrame.Visible = false
    confirmFrame.Visible = true
    resizeMenu(165)
end))

-- ==========================================
-- 💀 CLEAN TERMINATION LOGIC
-- ==========================================
table.insert(connections, yesBtn.MouseButton1Click:Connect(function()
    isScriptActive = false
    ambienceEnabled = false
    warningsEnabled = false
    timestampsEnabled = false
    
    clearBranchConnections()

    -- Disconnect global connections
    for _, conn in ipairs(connections) do
        if conn.Connected then conn:Disconnect() end
    end
    table.clear(connections)
    
    -- Disconnect character-specific connections
    for _, conn in ipairs(charConnections) do
        if conn.Connected then conn:Disconnect() end
    end
    table.clear(charConnections)
    
    if screenGui then screenGui:Destroy() end
    script:Destroy()
end))

table.insert(connections, noBtn.MouseButton1Click:Connect(function()
    confirmFrame.Visible = false
    scrollFrame.Visible = not settingsFrame.Visible
    updateDynamicSize() 
end))

table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not isScriptActive then return end

    if isBindingKey then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            menuKeybind = input.KeyCode
            isBindingKey = false
            keybindBtn.Text = "Option D: Menu Keybind [" .. menuKeybind.Name .. "]"
            keybindBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        end
        return
    end

    if gameProcessed then return end 
    if input.KeyCode == menuKeybind then
        if not confirmFrame.Visible then toggleMenu() end
    end
end))

-- Initialization
loadBranch("Main")

-- ==========================================
-- 🎬 AUTO-INTRO SEQUENCE
-- ==========================================
local introMessages = {
    "Made it to the site. Feels like the kind of place people don’t come back from.",
    "Let’s remember why we’re here. Whatever happens, the objective comes first.",
    "Keep your eyes open. I’d rather not find out what’s waiting for us the hard way.",
    "If this place goes quiet, don’t assume that means we’re safe.",
    "Alright… let’s get what we came for. Hopefully, this isn’t the last thing we ever do."
}

task.spawn(function()
    task.wait(1.5) 
    
    if isScriptActive then
        local randomIntro = introMessages[math.random(1, #introMessages)]
        sendChatMessage('[Intro] "' .. randomIntro .. '"')
    end
end)
