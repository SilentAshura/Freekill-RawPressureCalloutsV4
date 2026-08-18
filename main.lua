-- ==========================================
-- 😺 CONNECTIONS AND STUFF
-- ==========================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local isScriptActive = true
local isAlive = false
local hasDiedOnce = false
local connections = {}
local branchConnections = {}
local timeTrackerStarted = false
local scriptStartTime = 0
local ambienceEnabled = false
local warningsEnabled = false
local timestampsEnabled = false
local deathReviveEnabled = true
local teleportMessagesEnabled = false
local ambientThread
local timestampThread
local preDeathWarnings = false
local preDeathTimestamps = false
local menuKeybind = Enum.KeyCode.N
local isBindingKey = false
local updateAmbienceUI, updateWarningsUI, updateTimestampsUI, updateDeathReviveUI, updateTeleportUI
local lastMessageTime = 0
local COOLDOWN_DURATION = 1
local lastSentMessages = {}
local lastEyefestCalloutTime = 0 
local lastDivinerootCalloutTime = 0 
local lastTeleportMsgTime = 0
local TELEPORT_COOLDOWN = 5
local entitySpawnHistory = {}
local lastSpamWarningTime = {}
local SPAM_TIME_WINDOW = 8
local SPAM_THRESHOLD = 3
local SPAM_COOLDOWN = 10
local lastPandeCalloutTime = 0
local PANDE_COOLDOWN = 2.5 
local processedInstances = setmetatable({}, {__mode = "k"})
local entityPlurals = {
    ["Angler"] = "Anglers",
    ["Froger"] = "Frogers",
    ["Blitz"] = "Blitzes",
    ["Chainsmoker"] = "Chainsmokeys",
    ["Pinkie"] = "Pinkies",
    ["Pandemonium"] = "Pandemoniums",
    ["Eyefestation"] = "Eyefestations",
    ["Wall Dweller"] = "Wall Dwellers",
    ["Special"] = "Specials"
}
local spamMessages = {
    "Why the hell are there so many %s spawning?!",
    "Are you kidding me? How many %s are going to show up?!",
    "More %s?! The game is spamming them at us!",
    "Seriously, why are there so many %s coming all at once?!",
    "Okay, what is going on? That's way too many %s!"
}
local function getRandomMessage(messageList, poolKey)
    if not messageList or #messageList == 0 then return "" end
    if #messageList == 1 then return messageList[1] end
    local choice
    repeat
        choice = messageList[math.random(1, #messageList)]
    until choice ~= lastSentMessages[poolKey]
    lastSentMessages[poolKey] = choice
    return choice
end
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
    if currentTime - lastMessageTime < COOLDOWN_DURATION then 
        task.wait(COOLDOWN_DURATION)
    end
    lastMessageTime = os.clock()
    local channelType = getChatChannel()
    if channelType == "TextChatService" and rbxGeneralChannel then
        lastMessageTime = currentTime
        pcall(function()
            rbxGeneralChannel:SendAsync(message)
        end)
    elseif channelType == "LegacyChat" and legacyChatEvents then
        local sayReq = legacyChatEvents:FindFirstChild("SayMessageRequest")
        if sayReq then
            lastMessageTime = currentTime
            pcall(function()
                sayReq:FireServer(message, "All")
            end)
        end
    end
end
-- ==========================================
-- 💀 DEATH, REVIVAL, & TELEPORT LOGIC
-- ==========================================
local deathMessages = {
    "I'm done for... keep moving without me!",
    "They got me!",
    "Agh, this is it... save yourselves!",
    "I'm out... goodluck lads.",
    "Good luck, you guys... I'm finished.",
    "AHHHHHHHHHHHH!",
    "Aww Shee-",
    "AH FAHH-",
    "Thank gad. I'm tired of being the noisest person in the room.",
    "Malas Suwerte."
}
local reviveMessages = {
    "Whoa, thought I was a goner.",
    "I'm back! Let's make 'em pay for that.",
    "Ah, my head... alright, lets rock.",
    "I ain't dead yet! Hand me a flashlight.",
    "Back on my feet. Let's get out of this hellhole.",
    "Well, this is better than six feet below, I guess.",
    "Lady Death does not like me down there.",
    "I was busy chatting with the ghosts, bummer.",
    "I was just playing dead, you know? No? Forget it then.",
    "I was planning on ghosting, but alright."
}
local teleportMessages = {
    "Ugh, my stomach... I absolutely hate fast travel.",
    "Did we really have to warp like that? I feel nauseous.",
    "I despise molecular transport. Next time, let's just walk.",
    "Great, another spatial jump. I think I left my lunch in the previous room.",
    "Can we stop zipping around? My head is spinning from that fast motion."
}
local charConnections = {}
local lastStateChangeTime = 0
local lastDeathOrReviveTime = 0
local STATE_CHANGE_COOLDOWN = 3 
local function setupCharacter(character)
    if not character then return end   
    for _, conn in ipairs(charConnections) do
        if conn.Connected then conn:Disconnect() end
    end
    table.clear(charConnections)
    local humanoid = character:WaitForChild("Humanoid", 10)
    local hrp = character:WaitForChild("HumanoidRootPart", 10) 
    if humanoid then
        local now = os.clock()
        if humanoid.Health > 0 and hasDiedOnce then
            if (now - lastStateChangeTime) >= STATE_CHANGE_COOLDOWN then
                lastStateChangeTime = now
                lastDeathOrReviveTime = now
                isAlive = true                
                warningsEnabled = preDeathWarnings
                timestampsEnabled = preDeathTimestamps                
                if updateWarningsUI then updateWarningsUI(warningsEnabled) end
                if updateTimestampsUI then updateTimestampsUI(timestampsEnabled) end
                if deathReviveEnabled then
                    local msg = getRandomMessage(reviveMessages, "REVIVE")
                    sendChatMessage("[Back in action] " .. msg)
                end
            end
        elseif humanoid.Health > 0 then
            isAlive = true
        end
        local function onDeath()
            local currentTime = os.clock()
            if isAlive and (currentTime - lastStateChangeTime >= STATE_CHANGE_COOLDOWN) then
                lastStateChangeTime = currentTime
                lastDeathOrReviveTime = currentTime
                isAlive = false
                hasDiedOnce = true               
                preDeathWarnings = warningsEnabled
                preDeathTimestamps = timestampsEnabled              
                ambienceEnabled = false
                warningsEnabled = false
                timestampsEnabled = false               
                if updateAmbienceUI then updateAmbienceUI(false) end
                if updateWarningsUI then updateWarningsUI(false) end
                if updateTimestampsUI then updateTimestampsUI(false) end
                if deathReviveEnabled then
                    local msg = getRandomMessage(deathMessages, "DEATH")
                    sendChatMessage("[Dying message] " .. msg)
                end
            end
        end
        table.insert(charConnections, humanoid.Died:Connect(onDeath))       
        table.insert(charConnections, humanoid.HealthChanged:Connect(function(health)
            if health <= 0 then
                onDeath()
            end
        end))
        table.insert(charConnections, character.AncestryChanged:Connect(function(_, newParent)
            if not newParent or newParent ~= workspace then
                onDeath()
            end
        end))
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
    if hrp then
        task.spawn(function()
            local lastPos = hrp.Position
            while isAlive and character and character.Parent and isScriptActive do
                task.wait(0.1)
                if not hrp or not hrp.Parent then break end
                
                local currentPos = hrp.Position
                local dist = (currentPos - lastPos).Magnitude
                
                if dist > 150 and teleportMessagesEnabled then
                    local tNow = os.clock()
                    if tNow - lastTeleportMsgTime > TELEPORT_COOLDOWN and (tNow - lastDeathOrReviveTime) >= 10 then
                        lastTeleportMsgTime = tNow
                        local msg = getRandomMessage(teleportMessages, "TELEPORT")
                        sendChatMessage("[Teleported] " .. msg)
                    end
                end                
                lastPos = currentPos
            end
        end)
    end
end
table.insert(connections, player.CharacterAdded:Connect(setupCharacter))
if player.Character then
    task.spawn(setupCharacter, player.Character)
end
-- ==========================================
-- 🗃️ CALLOUTS & DIALOGUE DATA, thank https://research.nightfalldivision.com for our rooms callout sources
-- ==========================================
local GENERIC_ROOM_MESSAGES = {
    "Sector seems clear for now, keep moving.",
    "Just a standard room. Keep your eyes peeled for supplies.",
    "Nothing special about this area. Let's push forward.",
    "Stay together and keep moving, we're making good time.",
    "Don't let your guard down, even in these quiet rooms.",
    "Standard sector. Let's sweep it for gear and move on.",
    "All clear here so far. Let's not dawdle.",
    "Just another room. We can make it through this.",
    "Keep your heads up! We don't know what's behind the next door.",
    "Let's keep up the pace. Moving to the next area."
}
local callouts = {
    Main = {
        {name = "ENTITY", branch = "ENTITY"},
        {name = "SECTOR", autoRoomCheck = true},
        {name = "REPLY", branch = "REPLY"},
        {name = "MOVE", branch = "MOVE"},
        {name = "OBJECTIVE", messages = {"Go and do the objectives", "Mind the objectives", "Do the objectives!", "Is that taking forever or what?", "Focus on the objective!"}},
        {name = "ITEM", branch = "ITEM"},
        {name = "LOOKOUT", branch = "LOOKOUT"},
        {name = "MOCK", branch = "MOCK"},
        {name = "HELP", messages = {"Heeelp me!", "I need help over here!", "HELP!", "I need a hand over here!", "I'm in trouble!"}},
        {name = "MISCELLANEOUS", branch = "MISCELLANEOUS"},
    },
    ENTITY = {
        {name = "Angler", messages = {"Anglerfish!", "Angler!", "We got one Angler coming!", "Watch out for Angler!", "Heads up, Angler is coming!", "Classic Angler spawned.", "Lights out, Anglers in. Hide."}},
        {name = "Froger", messages = {"Froger!", "Orange fish! (Froger)", "We got ourselves a Froger!", "Watch out for that Froger bouncing!", "Heads up for Froger!", "That Orange fish is heading our way!", "WE GOT A FROGGA'"}},
        {name = "Blitz", messages = {"We got a Blitz!", "Fast one! GET IN A HIDING SPOT QUICKLY! (Blitz)", "WE GOT BLITZ RUSHIN'!", "Watch out, Blitz is COMING!", "Heads up for Blitz!", "Blitz is approaching fast!", "BLITZ INBDOUND!"}},
        {name = "Chainsmoker", messages = {"Smokey! (Chains)", "Green one! (Chains)", "Chains!", "Watch out for Chains!", "Heads up, Smokey's coming! (Chains)", "We got green smoke to inhale, it appears (Chains)", "The gas node is here again lads (Chains)"}},
        {name = "Pinkie", messages = {"Pinkie!", "Pink eye!", "Pink fish!", "I can hear that Pink one coming!", "Heads up for the Pink one!", "That Pink fish knows how to scream alright.", "We got that Pink fish heading here."}},
        {name = "Pandemonium", messages = {"Foul demon! (Pandemonium)", "Pandemonium!", "WE GOT A PANDEMONIUM!", "Watch out for Pandemonium!", "Another minigame, huh? (Pandemonium)", "We got ourselves a Pandemonium!", "EXPENDABLE AT DOOR 30! (Pandemonium)"}},
        {name = "Eyefestation", messages = {"Eyefestation!", "Don't look outside the glass. That light is not the exit. (Eyefest)", "Keep your head down! (Eyefest)", "Don't look at it, it will fry you (Eyefest)", "Whatever you do, do not listen to the voices (Eyefest)", "That shark is here again, jeez. (Eyefest)", "Don't start a staring contest. (Eyefest)"}},
        {name = "Wall Dweller", messages = {"Wall Dweller!", "They're in the walls! Those Wall Dwellers are in the walls again!", "Another Wall Dweller. Might as well call a friend.", "Watch out for Wall Dwellers!", "Heads up, a Wall Dweller is here.", "Man, those Wall Dwellers sure are persistent.", "Thank gad, I was getting hungry. (Wall Dwellers)"}},
        {name = "Pandemonium Variants", branch = "PANDEMONIUMVARIANTS"},
        {name = "Others", branch = "OTHERNODES"},
        {name = "Special", messages = {"Something wicked is coming! (Special Node)", "A terrible one approaches! (Special Node)", "Special Noder!", "Watch out, something bad is coming! (Special Node)", "Heads up for a special! (Special Node)", "Something is coming, and that's not a good one! (Special Node)", "WE GOT SOMETHING COMING ALRIGHT! (Special Node)"}},
    },
    ROOM = {
        {name = "Room100", aliases = {"room100"}, messages = {"We're not dying here.", "We're almost at the crystal.", "The crystal should be close.", "Don't mess this up now.", "Alright, let's see what's waiting for us.", "The monsters knows we're here."}},
        {name = "Turret", aliases = {"turret"}, messages = {"Oh great, a turret.", "Portal lied to me. Turrets are NOT adorable.", "Well, I found the security system.", "Don't get swiss cheesed now", "Remember: cardboard boxes. That's how you beat these things.", "Why can't all turrets be the friendly Portal ones?"}},
        {name = "Gauntlet", aliases = {"gauntlet"}, messages = { "I'll smash that computer when I get the chance.", "When I see that computer I will 'rescue' it alright", "Why are there SO many things trying to kill us?", "Don't even think about looking at it. This AI knows how to skrew people over", "Just keep turning away. DON'T LOOK AT IT.", "I am THIS close to saving that computer."}},
        {name = "Steam", aliases = {"steam"}, messages = {"Be careful of the steam, it's quite hot.", "If you get hurt by the steam, I'm laughing.", "Don't get burnt now.", "Those steam can cause serious burns, don't touch it."}},
        {name = "Electrified", aliases = {"electri"}, messages = {"Watchout for the electrified water", "That water isn't safe for stepping on", "Go around the water if possible.", "I'm sure there's another oute apart from crossing the water."}},
        {name = "PipePuzzle", aliases = {"pipeboard"}, messages = {"Oh boy, pipe puzzle time.", "Don't even think of greifing the puzzle or I'll send you to Valhalla myself", "Puzzle room. Neat.", "The puzzle should be solved to cross.", "Check the puzzle if it's fixed or not."}},
        {name = "BrokenRoom", aliases = {"brokenside", "bighole", "roundaboutdestroyed"}, messages = {"Watch your step, there's a broken floor", "Keep your eyes on the ground unless you enjoy free falling.", "There's a hole, mind that.", "Big hole. Keep away from it.", "There's a hole, be mindful.", "Pits and holes in this room. Careful now."}},
        {name = "Shop", aliases = {"shop"}, messages = {"Oh boy, Sebastian's Shop.", "Wasup Sebby.", "Hey, Sebastian's here.", "Might as well see what he's selling.", "Alright, what do you got for us?", "How many bodies did this guy loot?"}},
        {name = "VaculaVoidMass", aliases = {"voidmass"}, messages = {"Vacula Void Mass up ahead.", "That thing is way too big.", "Yeah, I'm not getting anywhere near that.", "Just walk past it. I don't want another void spawn to come.", "Keep moving before it notices us.", "So that's were all those void lockers some from"}},
        {name = "GuardianAngel", aliases = {"guardianangel"}, messages = {"Guardian Angel room. Time to jog.", "Oh great. ANOTHER long walk.", "Huh, that's actually kinda bad. Why did they need to do such a thing?", "Maybe it'll won't mind us passing through.", "Let's hope we don't anger it.", "What did that poor creature do to deserve this?"}},
        {name = "Toilet", aliases = {"toilet"}, messages = {"Found the Toilet room.", "Bathrooms. Check for loot, and don't think about fishing for it.", "Oh great, I could do a number two.", "Check the stalls real quick.", "Alright, let's go after you finish your buisness.", "Thank gad, I was about to explode from all that walking. "}},
        {name = "Cafeteria", aliases = {"cafeteria"}, messages = {"Looks like we arrived at a cafeteria. Lunch is on me, lads", "Load up that tray like we aren't coming back from this mission.", "Oh nice, I was getting hungry from all that walking", "I'm going to get two number 9s, a large number 9, a number 6 with extra dip, a number 7, two number 45s, and a large soda", "Oh neat, at least we'll have something better than WallDweller meat", "Maybe we could grab some coffee to maintain our sanity."}},
        {name = "SubCrash", aliases = {"submarinecrash"}, messages = {"That could have been us, we're lucky.", "Maybe that team's pathing was off. Bad luck.", "Check that sub, there could be something in there.", "If something comes, hide in the back of that sub.", "We're lucky we weren't that sub's occupants."}},
        {name = "Forest", aliases = {"caveforest"}, messages = {"A forest underwater. Now I've seen it all.", "Those trees look creepy", "We're in a Cave Forest underwater. Great.", "Just keep moving, I don't want to be near those trees."}},
        {name = "Cavern", aliases = {"spider"}, messages = {"Someone's arachnophobia about to trip in here", "Why is there a spider cave underground?", "We're in a Spider Cavern. Move fast.", "I sure hope there's no big spider in here.", "Don't worry about the nodes. they can't get us in here, I think."}},
        {name = "NaviAI", aliases = {"navi"}, messages = {"Navi AI room ahead.", "Found that sassy Ai.", "Maybe Navi knows a faster route than this.", "Let's see what the robot has to say.", "Alright Navi, don't screw us over.", "Two AI meetings in one run. Neat"}},
        {name = "Flooded", aliases = {"^flooded"}, messages = {"Don't let anything grab your legs.", "I can't see stuff in this water.", "Keep moving. Standing still feels like a bad idea.", "This is starting to feel like a Resident Evil level.", "Oh great, more water.", "If something jumps out of the water, I'm blaming Half-Life."}},
        {name = "Vent", aliases = {"^vent"}, messages = {"I feel like an imposter going through a vent.", "My claustrophobia could never.", "Hey, at least we can hide in the vents.", "Get in the vents, that's probably the way.", "Just keep moving, don't get cramped in there."}},
        {name = "Painter", aliases = {"painter"}, messages = {"Finally, we're meeting who's responsible for all those fake doors and turrets.", "Careful of that turret now.", "I am inclined to break that AI's screen.", "Time for that computer to pay for what its done.", "We're near the PAInter room now."}},
        {name = "Tram",
            aliases = {"tram"},
            Start = {"Tram station ahead!", "Oh nice, a tram line. How fun.", "Let's go ride this tram outta' here.", "Looks like we're taking the tram this time.", "Hey, at least we don't have to walk.", "Oh good, public transportation. What could possibly go wrong?", "I've played enough horror games to know this tram is not taking us somewhere nice."},
            Middle = {"In Transit."},
            End = {"Fun ride. Time to hop off.", "That was faster than I expected.", "Could have been a better ride.", "Alright, back to walking.", "There we go, back on our feet.", "That was quite quick. I thought it would take far longer."}},
        {name = "Chase", aliases = {"chase"}, messages = {"I am not cut out for this.", "Man, I hate being chased.", "Yeah, I doubt urbanshade equipment surviving this one.", "There should be a better route than this tunnel.", "We got nodes chasing us already, and here is another.", "I've seen this before. It ends badly."}},
        {name = "FSL", aliases = {"searchlightsending"}, messages = {"Our final job. Let's make this quick.", "Comeon, let's go and fix those generators fast.", "Lucy keeping an eye out for us, let's make it worth it.", "Don't stop now, let's go finish the job.", "Check those ones under, could be unfinished.", "We're almost done lads, let's show them what we're made of."}},
        {name = "Searchlights", aliases = {"searchlights"}, messages = {"Searchlights up ahead! Stay low.", "Keep to the cover and fix those generators fast.", "Don't let those lights catch you.", "Wait for the light to pass.", "Alright, let's sneak through.", "If one of you gets grabbed, I am not looking for your remains."}},
        {name = "Firewall",  aliases = {"firewall"}, messages = {"Don't get burned or splatted now.", "I swear this computer wants to hasten his degragation.", "I don't like wearing jetsuits. Too bulky.", "Keep moving before we get cooked.", "Oh great. Time to get in shape.", "Maybe all those parkour lessons would finally pay off."}},
        {name = "SeaBunny", aliases = {"bunn"}, messages = {"They're just hanging around like they own the place.", "Check the SeaBunnies and see what they're offering.", "Maybe one of these little guys has something useful.", "They're so small, how are they surviving down here?", "Aw, look at that one.", "Squish the bunny."}},
        {name = "Airlock", 
            aliases = {"airlock"}, 
            Start = {"Airlock ahead. Hope everyone remembered their suits.", "We're going outside. Don't forget to hold your breath.", "Cycle the airlock. Let's see what's out there.", "This door better seal properly behind us.", "Time for a spacewalk. Or sea-walk. Whatever this is."}, 
            Middle = {"Watch your step out here, the pressure feels weird.", "Keep moving, I don't want to test how long these suits last.", "Don't get eaten by wahtever is out here.", "Don't drift off. I'm not playing catch with you.", "The view would be great if everything wasn't trying to kill us."}, 
            End = {"Back inside. Pressurizing now.", "Glad that's over. My suit was fogging up.", "Finally, solid ground and breathable air.", "We made it across. Let's keep moving.", "Never thought I'd miss indoor lighting this much."}},
        {name = "River",
            aliases = {"river"}, 
            Start = {"Rivers in a room is wildwork.", "Don't slip in the water now.", "We got a river under the sea, how does that even happen?", "Well, guess we're getting our feet wet.", "Watch the water, it looks pretty deep.", "If this turns into Subnautica, I'm done."},
            Middle = {  "Wading through the river! Keep following the current!", "Don't wander too far from the water.", "Watch your footing, it's slippery.", "I really hope nothing lurks in here.", "Just follow the river and we'll be fine.", "If something grabs my leg, keep going without me."},
            End = {"End of the river section! Back on dry ground!", "Clear of the River area!", "Finally, no more wet feet.", "That wasn't too bad.", "Alright, we're out of the water, for now.", "Why is the water always where the monsters live?"}},
        {name = "LavaLabs",
            aliases = {"lava"}, 
            Start = {"We're in Mantle extraction.", "It's getting really hot in here.", "Yeah, that's lava.", "Watch your step around the magma.", "I don't think we're dressed for this.", "We're in Hell. Great."},
            Middle = {"We're moving above lava now.", "Stay away from the lava.", "One wrong step and we're cooked.", "It's getting hotter.", "If I hear heavy metal, I'm running.", "I would really like some fire resistance right about now."},
            End = {"Finally, I can breathe properly again.", "Thank goodness, finally somewhere that's not boiling.", "I can feel my skin recovering already.", "That was way too hot.", "Let's never do that again, I don't want to lose my breath that way.", "Mario has done this stuff before. I'm sure of it."}},
        {name = "Maintenance",
            aliases = {"maintenance"}, 
            Start = {"Looks like we're going in Maintenance.", "Oh great, pipes. Watch out for steam.", "This place looks like it's seen better days.", "Watch your head around here.", "Something tells me we're gonna get lost.", "Every horror game has a maintenance tunnel. Why?"},
            Middle = {"These tunnels just keep going.", "Watch out for the pipes.", "There's machinery all over the place.", "Try not to hit anything important.", "I swear every hallway looks the same.", "Pipes, darkness, and machinery. Fantastic combination."},
            End = { "We're finally out of Maintenance.", "Those tunnels were cramped.", "Glad we're done with the pipes.", "We made it through without breaking anything.", "Let's hope the next area is easier.", "Finally out of that pipe maze. Could had been worse."}},
        {name = "Garden",
            aliases = {"garden"}, 
            Start = {"Oh, we're in the Oxygen Gardens.", "Finally, somewhere that looks nice.", "The plants down here are actually kinda pretty.", "This is a nice change of scenery.", "Let's enjoy this while it lasts.", "Enjoy the plants. We're probably going to lose them."},
            Middle = {"This place is actually pretty peaceful.", "Maybe we can take some plants with us?", "There's plants everywhere.", "I almost forgot we're still underwater.", "Don't get too comfortable. Some of those plants are 'alive'.", "Well, that answers why we can breathe down here."},
            End = {"We're leaving the Oxygen Gardens.", "That was a nice change of scenery.", "Back to the scary stuff, I guess.", "At least we got some fresh air.", "I was planning on fist fighting a plantman", "I would have been a caretaker down here."}},
        {name = "Server",
            aliases = {"server"}, 
            Start = {"Oh, we're in the server farm.", "Lots of computers in here.", "Don't go mining for digital currency now", "This place is packed with servers.", "Don't touch anything that looks important.", "If the lights go out, I'm blaming whoever touched something."},
            Middle = {"We're pretty deep into the server farm now.", "There's wires everywhere in here.", "Watch where you're stepping.", "I can't even tell what half of these machines do.", "Don't even think about sticking any USB you found into something here.", "Someone tell GLaDOS we're stealing her aesthetic."},
            End = {"We're out of the server farm.", "That was a lot of computers.", "Nothing exploded, so that's good.", "Back to the normal halls.", "Let's get away from all these machines.", "This is exactly where the game would hide a monster in a server rack."}},
        {name = "Trench",
            aliases = {"trench"}, 
            Start = {"We're down in the Trenches now.", "I am NOT making eye contact with the fish demon.", "Try not to stare into the windows.", "You know what likes hanging around here.", "Eyes forward. Literally.", "Whatever's outside, it wants us to look at it."},
            Middle = {"We're pretty deep into the Trench.", "Mind the glass for Eyefestation.", "Seriously, don't stare at the windows.", "Just look ahead and keep moving.", "Something could be watching us right now.", "Don't look at the windows. We know better."},
            End = {"We're out of the Trench now. I need sunglasses.", "No more creepy windows.", "Thank goodness we're leaving the glass behind.", "We made it through. I hate sharks.", "Let's keep moving. We got a good view of the trenches from that.", "Thank gad the glass didn't crack midway."}},
        {name = "Sewers",
            aliases = {"^sewer"}, 
            Start = {"We're in the Sewers.", "Oh boy, sewage. Time to ruin another suit.", "Watch your step down here. Trip once and I am not holding a hand out for you.", "It's already starting to smell.", "At least it can't get much worse. Right?", "I swear to gad, if there's a Witch down here..."},
            Middle = {"Seriously, look, I'll give any one of ya' a thousand bucks to whoever gives me a piggyback ride.", "Keep away from the nasty water. I don't think that can be rinsed off.", "I am walking through a toilet. Thank you, Jimmy Gibbs.", "This place isn't the best match with my suit.", "Oh man... I think I just stepped in a boomer asset. Please tell me that's a boomer asset.", "Where the hell is the safe room?"},
            End = {"We're finally out of the Sewers.", "Guys, my boots are leaking. This is officially the worst day of my life.", "Finally, clean air.", "Why is it always sewers?! Why can't we escape through a mattress factory?!", "Let's never come back here.", "I hate sewers."}},
        {name = "Dredge",
            aliases = {"dredge"}, 
            Start = {"Dredge ahead. Get ready to get your ankles wet.", "Oh great, more water.", "Looks like we're going to walk in water again.", "Watch your step down here.", "Something is definitely swimming around.", "Don't let anything grab you. We can't see stuff down there."},
            Middle = {"Wading through the Dredge! Watch out for the monster fish in the water!", "Keep moving through the water.", "Don't let anything grab your legs.", "Keep an eye on the water.", "I really hope that shadow was just my imagination.", "Monster fish. Because regular monsters weren't enough."},
            End = {"Out of the Dredge water! Dry ground ahead!", "We're clear of the Dredge.", "Back on dry ground again.", "Nothing ate us, so that's nice.", "Let's stay out of the water for a while.", "I'm starting to wonder if this is better or worse than the sewers."}},
        {name = "Admin",
            aliases = {"admin"}, 
            Start = {"We're in Admin.", "Looks like the administrative offices.", "Red office rooms ahead.", "This place looks important.", "Maybe there's something useful around here.", "This is way too clean for a place we're supposed to survive in."},
            Middle = {"We're making our way through the Admin offices.", "Check the desks while we're here.", "There could still be something useful in these rooms.", "Lots of paperwork around here.", "Don't get too distracted.", "This is where we'd find the lore. Keep moving."},
            End = {"We're out of Admin.", "Alright, paperwork's over.", "That was a lot of offices.", "Back to exploring.", "Let's keep moving. We almost got lost in there.", "Nothing says survival horror like administrative paperwork."}},
        {name = "Quarters",
            aliases = {"quarters"}, 
            Start = { "These look like the employee quarters.", "Oh, living quarters. Might be loot in here.", "Looks like people actually lived here.", "Wonder how long these rooms have been empty.", "Let's check around these rooms before we leave.", "This is the part where somebody finds a note explaining what happened."},
            Middle = {"Those beds and couches looks real comfy", "There could still be some stuff left behind.", "Somebody definitely lived in this room.", "Keep an eye out for any useful items left in here.", "Don't spend all day searching, we can't rest here.", "This place looks abandoned. Which means something probably still lives here."},
            End = {"We're leaving the living quarters.", "Alright, we're done snooping around.", "Hope we found something useful.", "Back to the main path.", "Let's keep moving. We can't rest here else our PDGs would blow up.", "I would have grabbed the outfits if we had the time."}},
        {name = "Outskirt",
            aliases = {"outskirt"}, 
            Start = {"Oh, we're out in the Outskirts.", "Looks like there's still construction going on.", "Watch your step around here.", "This place isn't finished yet.", "Mind the gaps. I can't fish in that hole.", "This place hasn't finished loading."},
            Middle = {"Careful. The floor looks optional.", "Watch those holes in the floor.", "Don't fall off the edge.", "This whole place feels unfinished.", "Just keep an eye on where you're going.", "This feels like the part of the map where they expect you to fall."},
            End = {"We're clear of the construction area.", "Glad to be free of loose stones.", "That place was one bad step away from disaster.", "Back to safer ground.", "Let's keep going. Next area should be better.", "At least the place didn't fall on our head with how unsafe that was."}},
        {name = "Heavy",
            aliases = {"heavy", "hccheckpoint"},
            Start = {"We're in Heavy Containment now.", "Yeah, this place looks dangerous.", "Keep your guard up. This place looks like it's built for something much worse.", "That's one giant door.", "If this is heavy containment, does that make the others light containment?.", "Don't blink."},
            Middle = {"We're pretty deep into Heavy Containment.", "Built to last for a century, and over a hundred years old", "Don't wander off in here.", "Whatever's contained here probably isn't friendly.", "I wonder what could have breached on here.","SCP Foundation would charge us rent for this place."},
            End = {"We're out of Heavy Containment.", "Glad we don't have to stay in there.", "We're alive, so that's a win.", "That could've gone a lot worse.", "If it's behind three blast doors, leave it behind three blast doors.", "Yeah, we're definitely not supposed to be here."}},
        {name = "Meat",
            aliases = {"meat"},
            Start = {"We're going inside a dead creature now.", "Oh, we're going in something alright.", "Everything in there is fleshy.", "Why are we going inside a creature?", "Yeah, I don't like this.", "That's not a wall. That's monster tissue."},
            Middle = {"Everything in here looks alive.", "Gross fleshy walls everywhere.", "I really don't want to know what that smell is.", "If the floor starts breathing, I'm leaving.", "Don't touch anything.", "I miss concrete."},
            End = {"We're finally out of the that.", "Thank goodness we're out of there.", "I never want to see another meat wall again.", "That was disgusting.", "Let's pretend that never happened.", "The sewers would be better at this point."}},
        {name = "Backarea",
            aliases = {"backarea"},
            Start = {"Oh great. WallDwellers love this place.", "Two ways through. Catwalk or ground.", "This feels like one of those levels where the obvious path is the wrong one.", "I'll take the high ground. Anakin taught me well.", "I have a bad feeling about the lower path. Very Resident Evil.", "Pick a path and keep moving. We're not splitting up."},
            Middle = {"Watch the catwalk, I don't trust anything with a railing this thin.", "Ground route looks clear. For now.", "Don't fall. This isn't Assassin's Creed.", "I swear, if something starts chasing us, we're all going the same way.", "The higher path looks safer. Which means it's probably not.", "Some of the loot are locked behind doors. Use a breacher."},
            End = {"Made it through. Somehow.", "See? Easy. Nothing fell.", "The high ground was the right choice. Jedi wisdom wins again.", "One more hallway cleared. Keep moving.", "I'm just glad we didn't have to pick the wrong door."}},
        {name = "EndlessRidge",
            aliases = {"endlessridge"},
            Start = {"Huh... wasn't expecting the Ridge to be this well lit.", "At least we can actually see where we're going.", "Something about these lights feels... off.", "How far does this place actually go?", "Stay together. I don't like how quiet it is."}, 
            Middle = {"We've been walking for a while. Are we even getting anywhere?", "Don't stare at the lights too long. I swear they're getting brighter.", "At least it wasn't dark like normal.", "I can't tell if we're going forward or just going in circles.", "Keep moving. We can worry about where we are later."}, 
            End = {"There's the catwalk. Keep moving.", "We're finally leaving the Ridge.", "I never thought I'd be happy to see a bridge hanging over a void.", "Let's keep moving. We're bound to see it again later.", "I prefer this over the normal version."}},
        {name = "Ridge",
            aliases = {"ridge"},
            Start = {"We're in the Ridge now.", "Looks like we die in a dark if we aren't careful.", "Great, this place is dark.", "Keep your eyes and ears open.", "Something about this place feels off.", "Don't wander off. The darkness is basically a second monster."},
            Middle = {"Still making our way through the Ridge.", "These lights are making this place creepy.", "Don't let the darkness throw you off.", "I can barely see anything in here.", "Just keep moving, keep your ears open.", "Whatever's out there has night vision. Lucky."},
            End = {"We're out of the Ridge.", "Finally, some normal lighting.", "That wasn't too bad.", "Glad that's over with.", "Let's keep moving before the lights get worse.", "About time we end this nightmare"}},
        {name = "Hotel", 
            aliases = {"^hotel"},
            Start = {"Welcome to the hotel. Start checking those drawers.", "If the lights flicker, find a closet immediately.", "Keep your ears open for that rushing sound.", "Grab any lighters or flashlights you see.", "Don't trust the door numbers. Dupe is waiting."}, 
            Middle = {"If Seek spawns, we are cooked.", "At least there's no Void lockers in here.", "Is there a Screech behind me? Do look.", "Keep moving, follow the Guiding Light.", "I swear that painting just looked at me."}, 
            End = {"We made it back to the Blacksite.", "Finally, a moment to breathe. I thought Rush was going to appear.", "My heart can't take another closet hiding session.", "We survived the hotel... for now.", "I am never trusting two same numbered doors again."}},
        {name = "Rooms", 
            aliases = {"^rooms"},
            Start = {"Wait, how did we end up in A-000?", "Grab a gummylight, it gets dark fast in here.", "No help here, we're on our own.", "These rooms just keep going endlessly.", "Man, don't they have enough references already?"}, 
            Middle = {"Get in a locker if you hear the static.", "I sure hope A-90 doesn't spawn here.", "If you hear banging sounds coming from the front, pray.", "Why does everything look like a retro office?", "Just keep opening doors, don't stop."}, 
            End = {"We found the exit door!", "Finally out of that yellow maze.", "I never want to hear a distorted static sound again.", "That was a thousand doors too many.", "We survived the Rooms. Unbelievable."}},
    },  
    PANDEMONIUMVARIANTS = {
        {name = "Anglemonium", messages = {"That's not an Angler, that's a Pandemonium! (Anglemonium)", "Ugh, I hate it when Pande' tries to hide itself. (Anglemonium)", "Oh great, we can't have regular Pandemonium. We got his Angler cousin. (Anglemonium)", "THAT'S PANDEMONIUM, NOT ANGLER! (Anglemonium)", "Sounds like Angler. I'm 100% it's not. (Anglemonium)"}},
        {name = "Frogermonium", messages ={"I don't think that's a Froger. It moves like Pandemonium. (Frogermonium)", "That's Pandemonium! Not the Orange one! (Frogermonium)", "Oh, we got a Frogermonium. Type ****", "THAT'S NOT FROGER, THAT'S A PANDE' IN HIS SKIN! (Frogermonium)", "That is Pandemonium, cause that 'Frog' won't rebound, I'm sure of it. (Frogermonium)"}},
        {name = "Pinkimonium", messages ={"Oh, Pandemonium now wants to be silent? Tough luck. (Pinkimonium)", "We got a Pinkimonium lads!", "That's Pandemonium screaming! Not the Pink one! (Pinkimonium)", "A woke Pandemonium. Now I've seen it all. (Pinkimonium)", "Can't Pandemonium act normal for once? (Pinkimonium)"}},
        {name = "Pandesmoker", messages ={"WHY IS THAT PANDEMONIUM FAST? (PandeSmokey)", "WE GOT A GREEN PANDEMONIUM! (PandeSmokey)", "That Pandemonium is spewing gas! (PandeSmokey)", "That's not Chains, that's Pandemonium! GET MOVING! (PandeSmokey)", "WHY IS THAT PANDEMONIUM FASTER THAN NORMAL? (Pandesmokey)"}},
        {name = "Blitzemonium", messages ={"WE GOT A BLITZEMONIUM!", "That's Pandemonium, Not Blitz! (Blitzemonium)", "Pandemonium wants to be fast now, huh? (Blitzemonium)", "That Pandemonium is faster than expected. (Blitzemonium)", "We got Pandemonium's faster cousin! (Blitzemonium)"}},
    },
    OTHERNODES = {
        {name = "Pipsqueak", messages = {"Discount locker basher heading our way. (Pipsqueak)", "We got a Pipsqueak!", "PIPSQUEAK INBOUND!", "Oh, Pipsqueak. At least it's not the worse one.", "Pipsqueak heading to our location."}},
        {name = "A60", messages ={"This A-60 can't stay in Rooms? Jeez.", "WE GOT A-60!", "RED ROOMS NODE HEADING OUR WAY! (A-60)", "MULTI-MONSTER INCOMING! (A-60)", "A-60 is having a field day down here."}},
        {name = "A200", messages ={"That metal bashing is A-200. Hide in a locker.", "WE GOT A-200, FIND A LOCKER STAT!", "A-200 BASHING ITS WAY HERE!", "A-200 is flanking from the front,  go find a locker.", "A-200 just can't stay in Rooms, huh?"}},
        {name = "Bleach", messages = {"Bleach incoming, don't walk into it now.", "This Bleach is making me go blind.", "BLEACH HEADING THIS WAY!", "Bleach is going to bleach our eyes at this rate.", "Can't this Bleach find another game like Doors instead?"}},
        {name = "DeathAngel", messages ={"CAN'T WE HAVE NORMAL NODES FOR ONCE? (Harbinger)", "The lockers and drawers are telling us we are in deep trouble. (Harbinger)","DEATH INCARNATE! (Harbinger)", "Oh comeon?! A LITERAL DEATH ANGEL? (Harbinger)", "May lady luck help you survive this angel. (Harbinger)"}},
        {name = "Mirage", messages ={"That's weird, that don't sound like a node at all. (Mirage)", "That's just a Mirage, nothing special.", "Let's keep moving while Mirage passes us by.", "Comeon, that's Mirage. Still, stay sharp.", "The hallucinations are getting stronger by the minute. (Mirage)"}},
    },
    REPLY = {
        {name = "Yes", messages = {"Yeah, sure.", "Duly noted.", "Yeah sure", "Yeah, fine.", "Okay.", "Ok"}},
        {name = "No", messages = {"Hell no", "No.", "No way, not happening.", "No way man.", "Nope, no chance", "Nawh fam."}},
        {name = "Unsure", messages = {"I don't think so.", "Not sure.", "I don't know.", "Not certain.", "Uhh...IDK"}},
        {name = "Thanks", messages = {"Appreciate it, mate.", "Thanks.", "Thank you.", "Thanks, good looking out.", "Thanks a lot.", "Thanks lass."}},
        {name = "Question", messages = {"Huh?", "Say again?", "Can you repeat that?", "Pardon?", "Say what now?"}},
        {name = "Sorry", messages = {"I apologize.", "That wasn't intended.", "Sorry about that.", "My mistake.", "Uhh...My bad."}},
    },
    MOCK = {
        {name = "Mock Short", messages = {"Sonion.", "Oh brother.", "Dawg...", "Bruh", "Bro..."}},
        {name = "Mock Long", messages = {"Two braincells fighting for third place. Jeez.", "Dawg...", "That was a terrible idea.", "You can do better than that.", "You just had to do that, comeon", "At this point, I'm not even suprised."}},
        {name = "Mock Question", messages = {"Are we serious?", "Are you kidding me?", "You really thought that would work?", "How did you manage that?", "Uhh...HOW DID THAT HAPPEN?", "Common sense took the day off, huh?"}}, 
        {name = "Mock Hurt",  messages = {"That looked like it hurt", "Excellent work. Truly. A flawless display of incompetence.", "That looked painful. Funny, though.", "Keep that up and you'll be dead before you know it.", "That's gonna leave a mark.", "Don't die on me, now."}},
        {name = "Mock Death", messages = {"OH COMEON, HOW DID YOU DIE?", "Of course someone dies.", "I think this person wants to flirt with lady death.", "Just because Sebastian sells revive tokens, that doesn't mean dying is a good idea.", "Can you like, not die, FOR 5 MINUTES?", "You lasted longer than I expected. Not by much.", "Maybe next time, try not dying.", "Your survival instincts have officially resigned.", "Should've tried being better at surviving.", "And that's why we don't do whatever you just did."}},
    },
    MOVE = {
        {name = "Forward", messages = {"Go! Go! Go!", "Mooove out!", "Hurry it up!", "Make haste!", "Keep pushing forward!"}},
        {name = "Retreat", messages = {"Move back!", "Back away!", "Retreat!", "Fall back!", "Get out of there!"}},
    },
    ITEM = {
        {name = "Lights", messages = {"We need a light source", "Where's the lights?", "Light it up!", "Light up, it's getting dark", "Light up the place, will yeah?"}},
        {name = "Medical", messages = {"I'm hurt badly!", "I need a medic!", "Where the bloody crocus?", "Wait up, someone's hurt!", "Hey lads, someone needs medical!"}},
        {name = "Card", messages = {"Card?", "Where's the card at?", "Pass the card!", "We got a locked door!", "We need a keycard!"}},
        {name = "Other", messages = {"Found something?", "Search these rooms, might be something we can use", "Spare items?", "Look for supplies!", "Hey, check out this area!"}},
    },
    LOOKOUT = {
        {name = "Item", messages = {"Item over here!", "Hey, check this out", "Yo, take this", "Hey lads, I found an item!", "We got gear here!"}},
        {name = "Monster", messages = {"I sense a dark presence", "Danger is lurking around these parts", "Watch out for danger, will ya'?", "Watch it, lads!", "Heads up, danger ahead!"}},
    },
    MISCELLANEOUS = {
        {name = "Hide", messages = {"FIND A LOCKER, QUICKLY!", "FIND A HIDNG SPOT NOW!", "THAT'S NOT GOOD! HIDE!", "AHH HELL, FIND A SAFE SPOT!", "WE NEED TO HIDE, NOW!"}},
        {name = "Foreshadow", messages = {"Did you feel that vibration?", "I got a bad feeling about this area...", "It's way too quiet in here", "My hands won't stop shaking", "Something is here, I know it"}},
        {name = "Relief", messages = {"Phew, that was way too close! Y'all good?", "I think we actually lost it, are y'all alright?", "Is everybody still alive?", "It passed... okay, do head count.", "Made it through that one in one piece! Now, anyone dead?"}},
        {name = "Motivation", messages = {"We can actually make it out of here!", "Don't give up now, keep going!", "Keep your chin up, we're surviving!", "We've made it this far, don't stop now!", "Stay sharp! We can beat this place!"}},
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
        "[Hushed] I'll stop talking about uneeded stuff for a bit..",
        "[Hushed] Saving my breath for now.",
        "[Hushed] Going quiet. No more useless chatter.",
        "[Hushed] Fine, I'll focus on surviving, not yapping."
    },
    AmbienceOn = {
        "[Chatter] Silence is getting uncomfortable. Back to talking.",
        "[Chatter] Too quiet around here anyway. Let's talk.",
        "[Chatter] Alright, I'll keep the small talk going.",
        "[Chatter] Guards down, I can't stay quiet forever.",
        "[Chatter] Alright, back to keeping ourselves sane with talk."
    },
    WarningsOff = {
        "[Careless] Stopping entity callouts. Keep your own eyes open.",
        "[Careless] You're on your own for spotting monsters for now.",
        "[Careless] Turning off entity alerts. Don't blame me if something grabs you.",
        "[Careless] Halting entity callouts. I think y'all know what you're doing.",
        "[Careless] No more warnings for now. Hope your ears are sharp."
    },
    WarningsOn = {
        "[Alert] Warnings back on. Don't say I didn't warn you.",
        "[Alert] Entity tracking active again. I'll shout if I see anything.",
        "[Alert] Keeping my eyes peeled for threats again.",
        "[Alert] Fine, I'll resume keeping an eye out for horrors.",
        "[Alert] Engaging threat callouts. Watch your back."
    },
    TimestampsOff = {
        "[Untracked] Done watching the clock. It only makes me anxious.",
        "[Untracked] Clock watching off. Time doesn't matter down here anyway.",
        "[Untracked] Stopping the timer. Ignorance is bliss.",
        "[Untracked] No more keeping track of the minutes."
    },
    TimestampsOn = {
        "[Tracking] Resuming clock watching. Every minute counts down here.",
        "[Tracking] Timer enabled. Let's see how deep into the shift we get.",
        "[Tracking] Clock's ticking. I'll keep an eye on the time.",
        "[Tracking] Keeping track of time again. Let's see how long we last.",
        "[Tracking] Timestamps back on. Stay aware of the hours."
    },
    DeathReviveOff = {
        "[Silenced] Keeping quiet about my own condition for now.",
        "[Silenced] Won't be shouting if I drop or get revived.",
        "[Silenced] Stopping updates on my personal status.",
        "[Silenced] If I go down, no one will hear me.",
        "[Silenced] Silencing my own death and revive callouts."
    },
    DeathReviveOn = {
        "[Foreshadow] I'll let everyone know if I take a fatal hit.",
        "[Foreshadow] Status alerts on. I'll shout if I'm downed or revived.",
        "[Foreshadow] Back to reporting when I go down or get back on my feet.",
        "[Foreshadow] Expect a holler from me if I end up biting the dust.",
        "[Foreshadow] Keeping you posted on whether I'm alive or kicking."
    },
    TeleportOff = {
        "[Relieved] Keeping my complaints about warp jumps to myself.",
        "[Relieved] Fine, I won't complain every time space bends.",
        "[Relieved] Suppressing the urge to whine about teleporting.",
        "[Relieved] Muting my complaints whenever we jump across rooms.",
        "[Relieved] Swallowing my nausea quietly during teleportation."
    },
    TeleportOn = {
        "[Sick] I will definitely complain next time we teleport.",
        "[Sick] Warp reactions on. My stomach is already turning.",
        "[Sick] Be ready to hear me groan every single time we warp.",
        "[Sick] Spatial jumps whine re-enabled. Prepare to hear me complain.",
        "[Sick] Teleport reactions back on. My head hurts just thinking about it."
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
-- ⚙️ ROOM DETECTION HELPERS
-- ==========================================
local function isPlayerInsideRoom(hrpPos, roomInst)
    if not roomInst or not roomInst.Parent then return false end
    if roomInst:IsA("Model") then
        local cf, size = roomInst:GetBoundingBox()
        local localPos = cf:PointToObjectSpace(hrpPos)
        local halfSize = size / 2
        return math.abs(localPos.X) <= (halfSize.X + 5)
           and math.abs(localPos.Y) <= (halfSize.Y + 10)
           and math.abs(localPos.Z) <= (halfSize.Z + 5)
    end
    local primary = roomInst:FindFirstChildWhichIsA("BasePart", true)
    if primary then return (hrpPos - primary.Position).Magnitude <= 60 end
    return false
end
local function getCurrentRoomName()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return "" end
    local roomsFolder = workspace:FindFirstChild("Rooms") or (workspace:FindFirstChild("GameplayFolder") and workspace.GameplayFolder:FindFirstChild("Rooms"))
    if not roomsFolder then return "" end
    for _, room in ipairs(roomsFolder:GetChildren()) do
        if isPlayerInsideRoom(hrp.Position, room) then
            return string.lower(room.Name)
        end
    end
    return ""
end
-- ==========================================
-- ⚙️ LOGIC & FUNCTIONALITY
-- ==========================================
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
screenGui.Name = "CalloutsV4_Extended"
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
titleLabel.Text = "Callouts V4.3+"
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
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.Parent = mainFrame
local scrollPadding = Instance.new("UIPadding")
scrollPadding.PaddingBottom = UDim.new(0, 15)
scrollPadding.Parent = scrollFrame
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 5)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scrollFrame
-- ==========================================
-- ⚙️ SETTINGS UI
-- ==========================================
local settingsFrame = Instance.new("ScrollingFrame")
settingsFrame.Size = UDim2.new(1, -20, 1, -45)
settingsFrame.Position = UDim2.new(0, 10, 0, 45)
settingsFrame.BackgroundTransparency = 1
settingsFrame.ScrollBarThickness = 3
settingsFrame.ScrollingEnabled = true
settingsFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
settingsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
settingsFrame.Visible = false
settingsFrame.Parent = mainFrame
local settingsListLayout = Instance.new("UIListLayout")
settingsListLayout.Padding = UDim.new(0, 6)
settingsListLayout.SortOrder = Enum.SortOrder.LayoutOrder
settingsListLayout.Parent = settingsFrame
local function createSettingToggle(labelText, defaultState, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -5, 0, 38)
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
updateWarningsUI = createSettingToggle("Option B: Warnings", false, function(state, isManual)
    warningsEnabled = state
    if not state then
        table.clear(entitySpawnHistory)
        table.clear(lastSpamWarningTime)
    end
    if isManual then triggerBickerLine(state and "WarningsOn" or "WarningsOff") end
end)
updateTimestampsUI = createSettingToggle("Option C: Timestamps", false, function(state, isManual)
    timestampsEnabled = state
    if state and not timeTrackerStarted then
        scriptStartTime = os.clock()
        timeTrackerStarted = true
    end
    if isManual then triggerBickerLine(state and "TimestampsOn" or "TimestampsOff") end
end)
local timeEditFrame = Instance.new("Frame")
timeEditFrame.Size = UDim2.new(1, -5, 0, 30)
timeEditFrame.BackgroundTransparency = 1
timeEditFrame.Parent = settingsFrame
local timeTextBox = Instance.new("TextBox")
timeTextBox.Size = UDim2.new(1, -45, 1, 0)
timeTextBox.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
timeTextBox.TextColor3 = Color3.fromRGB(255, 255, 255)
timeTextBox.PlaceholderText = "Set bg time (mins)"
timeTextBox.Font = Enum.Font.Gotham
timeTextBox.TextSize = 13
timeTextBox.Parent = timeEditFrame
Instance.new("UICorner", timeTextBox).CornerRadius = UDim.new(0, 4)
local timeEnterBtn = Instance.new("TextButton")
timeEnterBtn.Size = UDim2.new(0, 40, 1, 0)
timeEnterBtn.Position = UDim2.new(1, -40, 0, 0)
timeEnterBtn.BackgroundColor3 = Color3.fromRGB(40, 110, 60)
timeEnterBtn.Text = "OK"
timeEnterBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
timeEnterBtn.Font = Enum.Font.GothamBold
timeEnterBtn.Parent = timeEditFrame
Instance.new("UICorner", timeEnterBtn).CornerRadius = UDim.new(0, 4)
table.insert(connections, timeEnterBtn.MouseButton1Click:Connect(function()
    local inputStr = timeTextBox.Text
    local minStr, secStr = string.match(inputStr, "^(%d+)[%.%:](%d+)$")   
    if not minStr then
        local wholeMin = string.match(inputStr, "^(%d+)$")
        if wholeMin then
            minStr = wholeMin
            secStr = "0"
        end
    end   
    if minStr and secStr then
        local m = tonumber(minStr)
        local s = tonumber(secStr)      
        if s <= 60 then
            local totalSeconds = (m * 60) + s
            timeTrackerStarted = true
            scriptStartTime = os.clock() - totalSeconds
            timeTextBox.Text = ""
            timeTextBox.PlaceholderText = string.format("Set to %d.%02d", m, s)
        else
            timeTextBox.Text = ""
            timeTextBox.PlaceholderText = "Error: Seconds > 60"
        end
    else
        timeTextBox.Text = ""
        timeTextBox.PlaceholderText = "Invalid format"
    end
end))
updateDeathReviveUI = createSettingToggle("Option D: Death/Revive", true, function(state, isManual)
    deathReviveEnabled = state
    if isManual then triggerBickerLine(state and "DeathReviveOn" or "DeathReviveOff") end
end)
updateTeleportUI = createSettingToggle("Option E: Teleport React", false, function(state, isManual)
    teleportMessagesEnabled = state
    if isManual then triggerBickerLine(state and "TeleportOn" or "TeleportOff") end
end)
local keybindBtn = Instance.new("TextButton")
keybindBtn.Size = UDim2.new(1, -5, 0, 38)
keybindBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
keybindBtn.Text = "Option F: Menu Keybind [" .. menuKeybind.Name .. "]"
keybindBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
keybindBtn.Font = Enum.Font.Gotham
keybindBtn.TextSize = 13
keybindBtn.Parent = settingsFrame
Instance.new("UICorner", keybindBtn).CornerRadius = UDim.new(0, 6)
table.insert(connections, keybindBtn.MouseButton1Click:Connect(function()
    isBindingKey = true
    keybindBtn.Text = "Option F: Press any key..."
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
confirmText.Position = UDim2.new(0, 10, 0, 0)
confirmText.BackgroundTransparency = 1
confirmText.Text = "Terminate Callouts V4?\nThis completely disables the script."
confirmText.TextColor3 = Color3.fromRGB(255, 255, 255)
confirmText.Font = Enum.Font.GothamBold
confirmText.TextSize = 14
confirmText.TextWrapped = true
confirmText.Parent = confirmFrame
local yesBtn = Instance.new("TextButton")
yesBtn.Size = UDim2.new(0, 100, 0, 35)
yesBtn.Position = UDim2.new(0, 15, 0, 60)
yesBtn.BackgroundColor3 = Color3.fromRGB(255, 65, 65)
yesBtn.Text = "Terminate"
yesBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
yesBtn.Font = Enum.Font.GothamBold
yesBtn.Parent = confirmFrame
Instance.new("UICorner", yesBtn).CornerRadius = UDim.new(0, 6)
local noBtn = Instance.new("TextButton")
noBtn.Size = UDim2.new(0, 100, 0, 35)
noBtn.Position = UDim2.new(1, -115, 0, 60)
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
local function loadBranch(branchName)
    clearBranchConnections()
    for _, child in pairs(scrollFrame:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end   
    local branchData = callouts[branchName]
    if not branchData then return end
    if branchName ~= "Main" then
        local backBtn = Instance.new("TextButton")
        backBtn.Size = UDim2.new(1, -5, 0, 30)
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
        btn.Size = UDim2.new(1, -5, 0, 35)
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
            elseif info.autoRoomCheck then
    local currentRoomName = getCurrentRoomName()
    local messagePool = nil
    local foundSpecialRoom = false
    
    for _, roomData in ipairs(callouts.ROOM) do
        local matched = false
        
        if roomData.aliases then
            for _, alias in ipairs(roomData.aliases) do
                local searchTerm = string.lower(alias)
                
                -- Check if the alias starts with '^' for strict prefix matching
                if searchTerm:find("^%^") then
                    if string.match(currentRoomName, searchTerm) then
                        matched = true
                        break
                    end
                else
                    -- Standard substring search for regular aliases/features
                    if currentRoomName:find(searchTerm, 1, true) then
                        matched = true
                        break
                    end
                end
            end
        else
            local searchTerm = string.lower(roomData.name)
            if searchTerm:find("^%^") then
                if string.match(currentRoomName, searchTerm) then matched = true end
            else
                if currentRoomName:find(searchTerm, 1, true) then matched = true end
            end
        end
        
        if matched then
            foundSpecialRoom = true                       
            if roomData.Start or roomData.Middle or roomData.End then
                if string.find(currentRoomName, "start") then
                    messagePool = roomData.Start
                elseif string.find(currentRoomName, "end") then
                    messagePool = roomData.End
                else
                    messagePool = roomData.Middle
                end
                if not messagePool then messagePool = roomData.Middle or roomData.Start end
            elseif roomData.messages then
                messagePool = roomData.messages
            end
            break
        end
    end
    
    if not foundSpecialRoom or not messagePool then
        messagePool = GENERIC_ROOM_MESSAGES
    end
    local poolKey = "UI_AutoSector_" .. (foundSpecialRoom and "Special" or "Generic")
    local rawMsg = getRandomMessage(messagePool, poolKey)
    if not rawMsg:match("[!?%.]$") then rawMsg = rawMsg .. "." end
    sendChatMessage("[Sector] " .. rawMsg)
    toggleMenu(true)
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
-- AUTOMATED ENTITY CALLOUTS & MULTI-SPAM DETECTOR
-- ==========================================
local entityKeywords = {
    {"pinkimonium", "Pinkimonium"}, {"pandesmoker", "Pandesmoker"},
    {"anglemonium", "Anglemonium"}, {"frogermonium", "Frogermonium"},
    {"blitzmonium", "Blitzemonium"}, {"blitzemonium", "Blitzemonium"},
    {"pandemonium", "Pandemonium"}, {"ridgepandemonium", "Pandemonium"},
    {"angler", "Angler"}, {"froger", "Froger"}, {"frogger", "Froger"},
    {"blitz", "Blitz"}, {"chain", "Chainsmoker"}, {"chainsmoker", "Chainsmoker"},
    {"pinkie", "Pinkie"}, 
    {"eyefestation", "Eyefestation"}, {"eyefest", "Eyefestation"}, 
    {"eyefesthurt", "Eyefestation"}, {"eyefestationcameraeffect", "Eyefestation"}, 
    {"eyefestveins", "Eyefestation"}, {"eyefestcircle", "Eyefestation"},
    {"divineroot", "Wall Dweller"}, {"di-vine-root", "Wall Dweller"},
    {"dweller", "Wall Dweller"}, {"walldweller", "Wall Dweller"}, {"dwellermodel", "Wall Dweller"},
    {"pipsqueak", "Pipsqueak"}, {"pipsqeuak", "Pipsqueak"}, {"a60", "A60"}, {"bleach", "Bleach"}, {"a200", "A200"},
    {"deathangel", "DeathAngel"}, {"harbinger", "DeathAngel"}, {"mirage", "Mirage"}, {"carnation", "Special"}
}
local function onEntitySpawned(child)
    if not isScriptActive or not isAlive or not warningsEnabled then return end  
    
    -- 1. Discard if this exact sub-object/instance was already processed
    if processedInstances[child] then return end
    processedInstances[child] = true

    local lowerName = string.lower(child.Name) 
    local now = os.clock() 

    -- 2. Dedicated Entity Cooldown Checks
    if lowerName:find("eyefest") or lowerName:find("eyefestation") then 
        if now - lastEyefestCalloutTime < 30 then return end 
        lastEyefestCalloutTime = now 
    elseif lowerName:find("divineroot") or lowerName:find("dweller") then 
        if now - lastDivinerootCalloutTime < 15 then return end 
        lastDivinerootCalloutTime = now 
    elseif lowerName:find("pande") or lowerName:find("monium") then
        if now - lastPandeCalloutTime < PANDE_COOLDOWN then return end
        lastPandeCalloutTime = now
    end

    -- 3. Resolve Entity Category (Angler, Pandemonium, Anglemonium, etc.)
    local targetCategory = nil
    for _, mapping in ipairs(entityKeywords) do 
        if string.find(lowerName, mapping[1]) then 
            targetCategory = mapping[2] 
            break
        end
    end
    if not targetCategory then return end

    -- 4. Anti-Spam Tracking & Callout Logic
    if not entitySpawnHistory[targetCategory] then 
        entitySpawnHistory[targetCategory] = {} 
    end
    local history = entitySpawnHistory[targetCategory]  
    
    for i = #history, 1, -1 do 
        if now - history[i] > SPAM_TIME_WINDOW then 
            table.remove(history, i) 
        end
    end
    table.insert(history, now) 

    local rawMsg = nil
    local lastSpam = lastSpamWarningTime[targetCategory] or 0 
    
    if #history > SPAM_THRESHOLD then 
        if now - lastSpam >= SPAM_COOLDOWN then 
            lastSpamWarningTime[targetCategory] = now 
            local template = getRandomMessage(spamMessages, "AUTO_SPAM") 
            local pluralName = entityPlurals[targetCategory] or (targetCategory .. "s") 
            rawMsg = string.format(template, pluralName) 
        else
            return 
        end
    else
        local searchCategories = {callouts.ENTITY, callouts.OTHERNODES, callouts.PANDEMONIUMVARIANTS} 
        for _, category in ipairs(searchCategories) do 
            for _, item in ipairs(category) do 
                if item.name == targetCategory and item.messages then 
                    rawMsg = getRandomMessage(item.messages, "AUTO_" .. targetCategory) 
                    break
                end
            end
            if rawMsg then break end 
        end
    end

    if rawMsg then 
        if not rawMsg:match("[!?%.]$") then rawMsg = rawMsg .. "." end 
        sendChatMessage("[Warning] " .. rawMsg) 
    end
end

table.insert(connections, workspace.ChildAdded:Connect(onEntitySpawned))
task.defer(function()
    local camera = workspace:WaitForChild("Camera", 10)
    if not isScriptActive or not camera then return end
    local function checkCameraChild(child)
        if not isScriptActive then return end
        local name = string.lower(child.Name)
        if name:find("eyefestation") or name:find("eyefest") then
            onEntitySpawned(child)
        end
    end
    for _, child in ipairs(camera:GetChildren()) do
        task.defer(function() checkCameraChild(child) end)
    end
    table.insert(connections, camera.ChildAdded:Connect(function(child)
        checkCameraChild(child)     
        local descConn
        descConn = child.DescendantAdded:Connect(checkCameraChild)
        table.insert(connections, descConn)     
        local ancestryConn
        ancestryConn = child.AncestryChanged:Connect(function(_, parent)
            if not parent then
                descConn:Disconnect()
                ancestryConn:Disconnect()
            end
        end)
        table.insert(connections, ancestryConn)
    end))
end)
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
    local function checkRoomForEntities(room)
        if not isScriptActive then return end
        for _, d in ipairs(room:GetDescendants()) do
            local name = string.lower(d.Name)
            if name:find("eyefest") or name:find("eyefestation") or name:find("dweller") or name:find("divineroot") then 
                onEntitySpawned(d) 
            end
        end    
        table.insert(connections, room.DescendantAdded:Connect(function(d)
            if not isScriptActive then return end
            local name = string.lower(d.Name)
            if name:find("eyefest") or name:find("eyefestation") or name:find("dweller") or name:find("divineroot") then 
                onEntitySpawned(d) 
            end
        end))
    end
    for _, room in ipairs(roomsFolder:GetChildren()) do
        task.defer(function() checkRoomForEntities(room) end)
    end   
    table.insert(connections, roomsFolder.ChildAdded:Connect(function(room)
        task.wait(0.1)
        if isScriptActive then checkRoomForEntities(room) end
    end))
end)
-- ==========================================
-- ⏱️ BACKGROUND AMBIENT DIALOGUE LOOP
-- ==========================================
ambientThread = task.spawn(function()
    task.wait(math.random(15, 25))
    while isScriptActive and screenGui and screenGui.Parent do
        if not isScriptActive then break end      
        if isAlive and ambienceEnabled then 
            local entry = getRandomDialogue()
            sendChatMessage(entry.prefix .. " " .. entry.text)
        end
        local waitTime = math.random(60, 120)
        task.wait(waitTime)
    end
end)
-- ==========================================
-- ⏱️ PERSISTENT TIMESTAMP TRACKER LOOP
-- ==========================================
timestampThread = task.spawn(function()
    local triggeredMilestones = {}
    while isScriptActive and screenGui and screenGui.Parent do
        task.wait(5)       
        if not isScriptActive or not screenGui or not screenGui.Parent then break end
        if timeTrackerStarted and timestampsEnabled and isAlive then
            local elapsedMinutes = math.floor((os.clock() - scriptStartTime) / 60)
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
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end))
end
makeDraggable(mainFrame, topBar)
makeDraggable(floatingToggle, floatingToggle)
-- ==========================================
-- 🔘 BUTTON & KEYBIND EVENT HANDLERS
-- ==========================================
table.insert(connections, gearBtn.MouseButton1Click:Connect(function()
    if confirmFrame.Visible then return end
    settingsFrame.Visible = not settingsFrame.Visible
    scrollFrame.Visible = not settingsFrame.Visible
    updateDynamicSize()
end))
table.insert(connections, minimizeBtn.MouseButton1Click:Connect(function()
    if confirmFrame.Visible then return end
    isMinimized = not isMinimized
    if isMinimized then
        settingsFrame.Visible = false
        scrollFrame.Visible = false
        resizeMenu(35)
    else
        scrollFrame.Visible = not settingsFrame.Visible
        updateDynamicSize()
    end
end))
table.insert(connections, closeBtn.MouseButton1Click:Connect(function()
    scrollFrame.Visible = false
    settingsFrame.Visible = false
    confirmFrame.Visible = true
    resizeMenu(140)
end))
table.insert(connections, noBtn.MouseButton1Click:Connect(function()
    confirmFrame.Visible = false
    scrollFrame.Visible = not settingsFrame.Visible
    updateDynamicSize()
end))
table.insert(connections, yesBtn.MouseButton1Click:Connect(function()
    isScriptActive = false
    clearBranchConnections()
    for _, conn in ipairs(connections) do
        if conn.Connected then conn:Disconnect() end
    end
    for _, conn in ipairs(charConnections) do
        if conn.Connected then conn:Disconnect() end
    end
    table.clear(connections)
    table.clear(charConnections)
    if screenGui then screenGui:Destroy() end
end))
table.insert(connections, floatingToggle.MouseButton1Click:Connect(function()
    toggleMenu()
end))
table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if isBindingKey then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            menuKeybind = input.KeyCode
            isBindingKey = false
            keybindBtn.Text = "Option F: Menu Keybind [" .. menuKeybind.Name .. "]"
            keybindBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        end
    elseif not gameProcessed and input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == menuKeybind then
            toggleMenu()
        end
    end
end))
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
        local randomIntro = getRandomMessage(introMessages, "INTRO")
        sendChatMessage('[Intro] "' .. randomIntro .. '"')
    end
end)
