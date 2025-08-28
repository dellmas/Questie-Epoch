---@class QuestieDataCollector
local QuestieDataCollector = QuestieLoader:CreateModule("QuestieDataCollector")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib")

-- Import QuestieCompat for proper WoW 3.3.5 API compatibility
local QuestieCompat = _G.QuestieCompat or {}

-- SavedVariables table for collected data
-- This will be initialized after ADDON_LOADED event

local _activeTracking = {} -- Currently tracking these quest IDs
local _lastQuestGiver = nil -- Store last NPC interacted with
local _questAcceptCoords = {} -- Store coordinates when accepting quests
local _originalTooltipSettings = nil -- Store original tooltip settings for restoration
local _recentKills = {} -- Store recent combat kills for objective correlation
local _initialized = false -- Track if we've initialized
local _currentLootSource = nil -- Track what we're currently looting from
local _lastInteractedObject = nil -- Track last object we moused over
local _trackAllEpochQuests = true -- Track all Epoch quests (26xxx range) by default

function QuestieDataCollector:Initialize()
    -- Prevent double initialization
    if _initialized then
        return
    end
    
    -- Only initialize if explicitly enabled
    if not Questie or not Questie.db or not Questie.db.profile.enableDataCollection then
        return
    end
    
    -- Create or ensure the global SavedVariable exists
    -- This happens AFTER SavedVariables are loaded
    if type(QuestieDataCollection) ~= "table" then
        _G.QuestieDataCollection = {}
    end
    if not QuestieDataCollection.quests then
        QuestieDataCollection.quests = {}
    end
    if not QuestieDataCollection.version then
        QuestieDataCollection.version = 1
    end
    if not QuestieDataCollection.sessionStart then
        QuestieDataCollection.sessionStart = date("%Y-%m-%d %H:%M:%S")
    end
    
    -- Count tracked quests
    local questCount = 0
    for _ in pairs(QuestieDataCollection.quests) do
        questCount = questCount + 1
    end
    
    -- Silently initialized
    
    -- Hook into events
    QuestieDataCollector:RegisterEvents()
    
    -- Enable tooltip IDs
    QuestieDataCollector:EnableTooltipIDs()
    
    _initialized = true
    
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Questie Data Collector]|r DEVELOPER MODE ACTIVE - Tracking missing quest data", 1, 0, 0)
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Use /qdc for commands. Disable in Advanced settings when done.|r", 1, 1, 0)
    
    -- Check existing quests in log
    QuestieDataCollector:CheckExistingQuests()
end

function QuestieDataCollector:CheckExistingQuests()
    -- Scan quest log for any missing (Epoch) quests
    local startTime = debugprofilestop()
    local trackedCount = 0
    local numEntries = GetNumQuestLogEntries()
    -- Silently scan quest log
    
    for i = 1, numEntries do
        -- Use QuestieCompat version which handles WoW 3.3.5 properly
        local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID = QuestieCompat.GetQuestLogTitle(i)
        
        if not isHeader and questID then
            -- Make a local copy to avoid any potential corruption
            local safeQuestID = questID
            
            -- Ensure questID is a number (sometimes it comes as a table)
            if type(safeQuestID) == "table" then
                -- Debug: Log what fields the table has
                if Questie.db.profile.debugDataCollector then
                    local fields = {}
                    for k,v in pairs(safeQuestID) do
                        table.insert(fields, tostring(k) .. "=" .. tostring(v))
                    end
                    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DataCollector Debug]|r questID is table with fields: " .. table.concat(fields, ", "), 1, 0, 0)
                end
                
                -- Try to extract ID from table
                local extractedID = safeQuestID.Id or safeQuestID.ID or safeQuestID.id or safeQuestID.questID or safeQuestID.QuestID
                if extractedID and type(extractedID) == "number" then
                    safeQuestID = extractedID
                else
                    -- If we can't extract a valid ID, skip this quest
                    safeQuestID = nil
                end
            elseif type(safeQuestID) ~= "number" then
                safeQuestID = tonumber(safeQuestID)
            end
            
            -- Only proceed if we have a valid numeric questID
            if safeQuestID and type(safeQuestID) == "number" and safeQuestID > 0 then
                questID = safeQuestID  -- Reassign to the safe copy (don't redeclare)
                -- Final safety check before calling GetQuest
                if type(questID) ~= "number" then
                    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DataCollector ERROR]|r questID passed check but is still " .. type(questID), 1, 0, 0)
                    -- Continue to next iteration instead of return
                else
                    -- Use pcall to catch any errors from GetQuest
                    local success, questData = pcall(function()
                        return QuestieDB.GetQuest(questID)  -- Use dot notation, not colon
                    end)
                    
                    if not success then
                        -- GetQuest failed, skip this quest silently
                        if Questie.db.profile.debugDataCollector then
                            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DataCollector]|r GetQuest failed for questID: " .. tostring(questID), 1, 0, 0)
                        end
                    else
                        -- Now process the quest data
                        local needsTracking = false
                        local trackReason = nil
                        local isEpochQuest = (questID >= 26000 and questID < 27000)
                        
                        if isEpochQuest then
                            if not questData then
                                needsTracking = true
                                trackReason = "missing Epoch quest"
                            elseif questData.name and string.find(questData.name, "%[Epoch%]") then
                                needsTracking = true
                                trackReason = "has [Epoch] prefix"
                            elseif _trackAllEpochQuests then
                                -- Track all Epoch quests to improve their data
                                needsTracking = true
                                trackReason = "is Epoch quest (26xxx)"
                            end
                        end
                        
                        if needsTracking then
                            -- This quest needs data collection
                            -- Silently track quest
                            if not _activeTracking[questID] then
                                _activeTracking[questID] = true
                                trackedCount = trackedCount + 1
                                
                                -- Initialize quest data if not exists
                                if not QuestieDataCollection.quests[questID] then
                                    QuestieDataCollection.quests[questID] = {
                                        id = questID,
                                        name = title or ("Quest " .. questID),
                                        level = level,
                                        objectives = {},
                                        npcs = {},
                                        items = {},
                                        objects = {},
                                        sessionStart = date("%Y-%m-%d %H:%M:%S"),
                                        wasAlreadyAccepted = true,  -- Flag that this quest was in log when addon loaded
                                        incompleteData = true  -- We don't have quest giver info
                                    }
                                    -- Silently track quest
                                end
                            end
                        end
                    end -- end of success check
                end -- end of type check
            end -- Close questID > 0 check
        end
    end
    
    if trackedCount > 0 then
        local elapsed = debugprofilestop() - startTime
        -- Finished scanning quest log
    end
end

function QuestieDataCollector:RegisterEvents()
    -- Only create event frame if it doesn't exist
    if QuestieDataCollector.eventFrame then
        return -- Already registered
    end
    
    local eventFrame = CreateFrame("Frame")
    QuestieDataCollector.eventFrame = eventFrame
    
    -- Register all needed events
    eventFrame:RegisterEvent("QUEST_ACCEPTED")
    eventFrame:RegisterEvent("QUEST_TURNED_IN")
    eventFrame:RegisterEvent("QUEST_COMPLETE")
    eventFrame:RegisterEvent("QUEST_LOG_UPDATE")
    eventFrame:RegisterEvent("GOSSIP_SHOW")
    eventFrame:RegisterEvent("QUEST_DETAIL")
    eventFrame:RegisterEvent("CHAT_MSG_LOOT")
    eventFrame:RegisterEvent("UI_INFO_MESSAGE")
    eventFrame:RegisterEvent("ITEM_PUSH")
    eventFrame:RegisterEvent("LOOT_OPENED")
    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("LOOT_OPENED")
    eventFrame:RegisterEvent("ITEM_PUSH")
    
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        QuestieDataCollector:HandleEvent(event, ...)
    end)
    
    -- Hook interact with target to capture NPC data
    hooksecurefunc("InteractUnit", function(unit)
        if UnitExists(unit) and not UnitIsPlayer(unit) then
            QuestieDataCollector:CaptureNPCData(unit)
        end
    end)
    
    -- Hook tooltip functions to capture IDs
    QuestieDataCollector:SetupTooltipHooks()
    
    -- Hook game object interactions
    QuestieDataCollector:SetupObjectTracking()
    
    -- Enable ID display in tooltips when data collection is active
    if Questie.db.profile.enableDataCollection then
        QuestieDataCollector:EnableTooltipIDs()
    end
end

function QuestieDataCollector:EnableTooltipIDs()
    -- Store original settings
    if not _originalTooltipSettings then
        _originalTooltipSettings = {
            itemID = Questie.db.profile.enableTooltipsItemID,
            npcID = Questie.db.profile.enableTooltipsNPCID,
            objectID = Questie.db.profile.enableTooltipsObjectID,
            questID = Questie.db.profile.enableTooltipsQuestID
        }
    end
    
    -- Enable all ID displays for data collection
    Questie.db.profile.enableTooltipsItemID = true
    Questie.db.profile.enableTooltipsNPCID = true
    Questie.db.profile.enableTooltipsObjectID = true
    Questie.db.profile.enableTooltipsQuestID = true
    
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[DATA COLLECTOR] Tooltip IDs enabled for data collection|r", 1, 1, 0)
end

function QuestieDataCollector:RestoreTooltipIDs()
    -- Restore original settings
    if _originalTooltipSettings then
        Questie.db.profile.enableTooltipsItemID = _originalTooltipSettings.itemID
        Questie.db.profile.enableTooltipsNPCID = _originalTooltipSettings.npcID
        Questie.db.profile.enableTooltipsObjectID = _originalTooltipSettings.objectID
        Questie.db.profile.enableTooltipsQuestID = _originalTooltipSettings.questID
        _originalTooltipSettings = nil
    end
end

function QuestieDataCollector:SetupTooltipHooks()
    -- Hook GameTooltip to capture item/NPC info when shown
    GameTooltip:HookScript("OnTooltipSetItem", function(self)
        if not Questie.db.profile.enableDataCollection then return end
        
        local name, link = self:GetItem()
        if link then
            local itemId = tonumber(string.match(link, "item:(%d+)"))
            if itemId then
                QuestieDataCollector:CaptureItemData(itemId, name, link)
            end
        end
    end)
    
    GameTooltip:HookScript("OnTooltipSetUnit", function(self)
        if not Questie.db.profile.enableDataCollection then return end
        
        local name, unit = self:GetUnit()
        if unit and not UnitIsPlayer(unit) then
            local guid = UnitGUID(unit)
            if guid then
                local npcId = tonumber(string.match(guid, "Creature%-0%-%d+%-%d+%-%d+%-(%d+)%-")) or 
                              tonumber(string.match(guid, "Creature%-0%-%d+%-%d+%-(%d+)%-"))
                if npcId then
                    QuestieDataCollector:CaptureTooltipNPCData(npcId, name)
                end
            end
        end
    end)
    
    -- Hook container item tooltips (bags)
    hooksecurefunc(GameTooltip, "SetBagItem", function(self, bag, slot)
        if not Questie.db.profile.enableDataCollection then return end
        
        local texture, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bag, slot)
        if link then
            local itemId = tonumber(string.match(link, "item:(%d+)"))
            local name = GetItemInfo(link)
            if itemId and name then
                QuestieDataCollector:CaptureItemData(itemId, name, link)
            end
        end
    end)
end

function QuestieDataCollector:CaptureItemData(itemId, name, link)
    -- Store item data for active quests
    for questId, _ in pairs(_activeTracking) do
        if QuestieDataCollection.quests[questId] then
            if not QuestieDataCollection.quests[questId].items then
                QuestieDataCollection.quests[questId].items = {}
            end
            
            -- Check if this item is a quest objective
            local questLogIndex = QuestieDataCollector:GetQuestLogIndexById(questId)
            if questLogIndex then
                SelectQuestLogEntry(questLogIndex)
                local numObjectives = GetNumQuestLeaderBoards(questLogIndex)
                
                for i = 1, numObjectives do
                    local text, objectiveType, finished = GetQuestLogLeaderBoard(i, questLogIndex)
                    if objectiveType == "item" and string.find(text, name) then
                        QuestieDataCollection.quests[questId].items[itemId] = {
                            name = name,
                            objectiveIndex = i,
                            link = link
                        }
                        
                        -- Update objective with item ID
                        if QuestieDataCollection.quests[questId].objectives[i] then
                            QuestieDataCollection.quests[questId].objectives[i].itemId = itemId
                            QuestieDataCollection.quests[questId].objectives[i].itemName = name
                        end
                    end
                end
            end
        end
    end
end

function QuestieDataCollector:CaptureTooltipNPCData(npcId, name)
    -- Store NPC data for active quests
    for questId, _ in pairs(_activeTracking) do
        if QuestieDataCollection.quests[questId] then
            if not QuestieDataCollection.quests[questId].npcs then
                QuestieDataCollection.quests[questId].npcs = {}
            end
            
            -- Store with current location
            local coords = QuestieDataCollector:GetPlayerCoords()
            QuestieDataCollection.quests[questId].npcs[npcId] = {
                name = name,
                coords = coords,
                zone = GetRealZoneText(),
                timestamp = time()
            }
        end
    end
end

function QuestieDataCollector:HandleEvent(event, ...)
    if event == "QUEST_ACCEPTED" then
        local questLogIndex, questId = ...
        -- In 3.3.5a, second param might be questId or nil
        if not questId or questId == 0 then
            questId = QuestieDataCollector:GetQuestIdFromLogIndex(questLogIndex)
        end
        QuestieDataCollector:OnQuestAccepted(questId)
        
    elseif event == "QUEST_TURNED_IN" then
        local questId = ...
        QuestieDataCollector:OnQuestTurnedIn(questId)
        
    elseif event == "QUEST_COMPLETE" then
        QuestieDataCollector:OnQuestComplete()
        
    elseif event == "GOSSIP_SHOW" or event == "QUEST_DETAIL" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFCCCCCC[DEBUG] " .. event .. " event fired!|r", 0.8, 0.8, 0.8)
        QuestieDataCollector:CaptureNPCData("target")
        
    elseif event == "CHAT_MSG_LOOT" then
        local message = ...
        QuestieDataCollector:OnLootReceived(message)
        
    elseif event == "UI_INFO_MESSAGE" then
        local message = ...
        QuestieDataCollector:OnUIInfoMessage(message)
        
    elseif event == "QUEST_LOG_UPDATE" then
        QuestieDataCollector:OnQuestLogUpdate()
        
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        QuestieDataCollector:OnCombatLogEvent(...)
        
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        if UnitExists("mouseover") and not UnitIsPlayer("mouseover") then
            QuestieDataCollector:TrackMob("mouseover")
        end
        
    elseif event == "PLAYER_TARGET_CHANGED" then
        if UnitExists("target") and not UnitIsPlayer("target") and not UnitIsFriend("player", "target") then
            QuestieDataCollector:TrackMob("target")
        end
        
    elseif event == "LOOT_OPENED" then
        QuestieDataCollector:OnLootOpened()
        
    elseif event == "ITEM_PUSH" then
        local bagSlot, iconFileID = ...
        QuestieDataCollector:OnItemPush(bagSlot)
    end
end

function QuestieDataCollector:GetQuestIdFromLogIndex(index)
    local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questId = QuestieCompat.GetQuestLogTitle(index)
    
    -- Ensure questId is a number
    if type(questId) == "table" then
        -- Try to extract ID from table
        local extractedID = questId.Id or questId.ID or questId.id or questId.questID or questId.QuestID
        if extractedID and type(extractedID) == "number" then
            questId = extractedID
        else
            questId = nil
        end
    elseif type(questId) ~= "number" then
        questId = tonumber(questId)
    end
    
    if questId and questId > 0 then
        return questId
    end
    
    -- Try to find quest ID by matching title in quest log
    for i = 1, GetNumQuestLogEntries() do
        local qTitle, qLevel, _, qIsHeader, _, _, _, qId = QuestieCompat.GetQuestLogTitle(i)
        
        -- Ensure qId is a number
        if type(qId) == "table" then
            local extractedID = qId.Id or qId.ID or qId.id or qId.questID or qId.QuestID
            if extractedID and type(extractedID) == "number" then
                qId = extractedID
            else
                qId = nil
            end
        elseif type(qId) ~= "number" then
            qId = tonumber(qId)
        end
        
        if not qIsHeader and qTitle == title and qLevel == level then
            if qId and qId > 0 then
                return qId
            end
        end
    end
    
    return nil
end

function QuestieDataCollector:TrackMob(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) then return end
    
    local name = UnitName(unit)
    local guid = UnitGUID(unit)
    
    if guid and UnitCanAttack("player", unit) then
        -- Extract NPC ID using same method as quest givers
        local npcId = tonumber(guid:sub(6, 12), 16)
        
        if npcId then
            local coords = QuestieDataCollector:GetPlayerCoords()
            
            -- Count how many quests track this mob
            local trackedForQuests = {}
            local isNewMob = false
            
            -- Check all active tracked quests
            for questId, _ in pairs(_activeTracking or {}) do
                local questData = QuestieDataCollection.quests[questId]
                if questData then
                    -- Store in the quest's npcs table
                    questData.npcs = questData.npcs or {}
                    
                    -- Only store each NPC once per quest
                    if not questData.npcs[npcId] then
                        questData.npcs[npcId] = {
                            name = name,
                            coords = coords,
                            zone = GetRealZoneText(),
                            subzone = GetSubZoneText(),
                            level = UnitLevel(unit),
                            timestamp = time()
                        }
                        table.insert(trackedForQuests, questId)
                        isNewMob = true
                    end
                    
                    -- Also check if this mob matches any objectives (more flexible matching)
                    for _, objective in ipairs(questData.objectives or {}) do
                        if objective.type == "monster" then
                            -- Try to match the mob name in the objective text
                            -- Remove common words like "slain", "killed", etc. for better matching
                            local cleanText = string.lower(objective.text or "")
                            local cleanName = string.lower(name)
                            
                            if string.find(cleanText, cleanName) or string.find(cleanText, string.gsub(cleanName, "s$", "")) then
                                -- Store mob location with the quest objective
                                objective.mobLocations = objective.mobLocations or {}
                                
                                -- Check if we already have this location
                                local alreadyTracked = false
                                for _, loc in ipairs(objective.mobLocations) do
                                    if loc.npcId == npcId then
                                        alreadyTracked = true
                                        break
                                    end
                                end
                                
                                if not alreadyTracked then
                                    table.insert(objective.mobLocations, {
                                        npcId = npcId,
                                        name = name,
                                        coords = coords,
                                        zone = GetRealZoneText(),
                                        subzone = GetSubZoneText(),
                                        level = UnitLevel(unit)
                                    })
                                    
                                    DEFAULT_CHAT_FRAME:AddMessage("|cFF00AA00[DATA] Linked " .. name .. " to objective: " .. objective.text .. "|r", 0, 0.7, 0)
                                end
                            end
                        end
                    end
                end
            end
            
            -- Show consolidated message for all quests that tracked this mob
            if isNewMob and #trackedForQuests > 0 then
                if #trackedForQuests > 3 then
                    DEFAULT_CHAT_FRAME:AddMessage("|cFF888800[DATA] Tracked " .. name .. " (ID: " .. npcId .. 
                        ") for " .. #trackedForQuests .. " quests at [" .. (coords.x or 0) .. ", " .. (coords.y or 0) .. "]|r", 0.5, 0.5, 0)
                else
                    DEFAULT_CHAT_FRAME:AddMessage("|cFF888800[DATA] Tracked " .. name .. " (ID: " .. npcId .. 
                        ") for quests: " .. table.concat(trackedForQuests, ", ") .. " at [" .. (coords.x or 0) .. ", " .. (coords.y or 0) .. "]|r", 0.5, 0.5, 0)
                end
            end
        end
    end
end

function QuestieDataCollector:CaptureNPCData(unit)
    if not UnitExists(unit) then 
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DEBUG] Unit doesn't exist: " .. tostring(unit) .. "|r", 1, 0, 0)
        return 
    end
    
    if UnitIsPlayer(unit) then 
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DEBUG] Unit is a player, not an NPC|r", 1, 0, 0)
        return 
    end
    
    local name = UnitName(unit)
    local guid = UnitGUID(unit)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[DEBUG] Capturing NPC: " .. (name or "nil") .. " GUID: " .. (guid or "nil") .. "|r", 0, 1, 1)
    
    if guid then
        -- WoW 3.3.5 GUID format: 0xF13000085800126C
        -- Use same extraction as QuestieCompat.UnitGUID
        local npcId = tonumber(guid:sub(6, 12), 16)
        
        DEFAULT_CHAT_FRAME:AddMessage("|cFFCCCCCC[DEBUG] Extracted NPC ID: " .. (npcId or "nil") .. " from GUID: " .. guid .. "|r", 0.8, 0.8, 0.8)
        
        if npcId then
            local coords = QuestieDataCollector:GetPlayerCoords()
            _lastQuestGiver = {
                name = name,
                npcId = npcId,
                coords = coords,
                zone = GetRealZoneText(),
                subzone = GetSubZoneText(),
                timestamp = time()
            }
            
            -- Debug output to verify NPC capture
            -- NPC captured silently
        end
    end
end

function QuestieDataCollector:GetPlayerCoords()
    -- Use Questie's coordinate system for better compatibility
    local QuestieCoords = QuestieLoader:ImportModule("QuestieCoords")
    if QuestieCoords and QuestieCoords.GetPlayerMapPosition then
        local position = QuestieCoords.GetPlayerMapPosition()
        if position and position.x and position.y and (position.x > 0 or position.y > 0) then
            return {x = math.floor(position.x * 1000) / 10, y = math.floor(position.y * 1000) / 10}
        end
    end
    
    -- Fallback to direct API if QuestieCoords not available
    local x, y = GetPlayerMapPosition("player")
    if x and y and (x > 0 or y > 0) then
        return {x = math.floor(x * 1000) / 10, y = math.floor(y * 1000) / 10}
    end
    
    -- Return approximate coordinates based on zone if map position fails
    return {x = 0, y = 0}
end

function QuestieDataCollector:OnQuestAccepted(questId)
    if not questId then return end
    
    -- Ensure questId is a number (sometimes it comes as a table)
    if type(questId) == "table" then
        -- Debug: Log what fields the table has
        if Questie.db.profile.debugDataCollector then
            local fields = {}
            for k,v in pairs(questId) do
                table.insert(fields, tostring(k) .. "=" .. tostring(v))
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DataCollector Debug]|r OnQuestAccepted questId is table with fields: " .. table.concat(fields, ", "), 1, 0, 0)
        end
        
        -- Try to extract ID from table
        local extractedID = questId.Id or questId.ID or questId.id or questId.questID or questId.QuestID
        if extractedID and type(extractedID) == "number" then
            questId = extractedID
        else
            -- If we can't extract a valid ID, skip
            return
        end
    elseif type(questId) ~= "number" then
        questId = tonumber(questId)
        if not questId then return end
    end
    
    -- Double-check that data collection is enabled
    if not Questie.db.profile.enableDataCollection then
        return
    end
    
    -- Ensure we're initialized
    if not QuestieDataCollection or not QuestieDataCollection.quests then
        QuestieDataCollector:Initialize()
    end
    
    -- Only track Epoch quests (26000-26999) or quests with [Epoch] prefix
    local questData = QuestieDB.GetQuest(questId)  -- Use dot notation, not colon
    local isEpochQuest = (questId >= 26000 and questId < 27000)
    local hasEpochPrefix = questData and questData.name and string.find(questData.name, "%[Epoch%]")
    local isMissingFromDB = not questData
    
    -- Only track if it's an Epoch quest that's missing or has placeholder data
    if isEpochQuest and (isMissingFromDB or hasEpochPrefix) then
        -- ALERT! Missing quest detected!
        local questTitle = QuestieCompat.GetQuestLogTitle(QuestieDataCollector:GetQuestLogIndexById(questId))
        
        -- Alert player about missing quest
        DEFAULT_CHAT_FRAME:AddMessage("===========================================", 0, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[QUESTIE] Missing Epoch quest detected!|r", 0, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Quest: " .. (questTitle or "Unknown") .. " (ID: " .. questId .. ")|r", 1, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Please complete this quest to help us improve the database!|r", 1, 1, 0)
        
        -- Initialize collection data for this quest
        if not QuestieDataCollection.quests[questId] then
            QuestieDataCollection.quests[questId] = {
                id = questId,
                name = questTitle,
                acceptTime = time(),
                level = nil,
                zone = GetRealZoneText(),
                faction = UnitFactionGroup("player"),  -- "Alliance" or "Horde"
                race = select(2, UnitRace("player")),
                class = select(2, UnitClass("player")),
                objectives = {},
                items = {},
                npcs = {}
            }
        else
            -- Quest already exists, just update accept time and clear duplicate objectives
            QuestieDataCollection.quests[questId].acceptTime = time()
            -- Reset objectives to prevent duplicates
            QuestieDataCollection.quests[questId].objectives = {}
        end
        
        -- Capture quest giver data
        if _lastQuestGiver and (time() - _lastQuestGiver.timestamp < 5) then
            QuestieDataCollection.quests[questId].questGiver = _lastQuestGiver
            -- Quest giver captured
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Tip: Target the quest giver when accepting to capture their location|r", 1, 1, 0)
        end
        
        -- Get quest details from log
        local questLogIndex = QuestieDataCollector:GetQuestLogIndexById(questId)
        if questLogIndex then
            SelectQuestLogEntry(questLogIndex)
            local _, level = QuestieCompat.GetQuestLogTitle(questLogIndex)
            QuestieDataCollection.quests[questId].level = level
            
            -- Get objectives
            local numObjectives = GetNumQuestLeaderBoards(questLogIndex)
            for i = 1, numObjectives do
                local text, objectiveType, finished = GetQuestLogLeaderBoard(i, questLogIndex)
                table.insert(QuestieDataCollection.quests[questId].objectives, {
                    text = text,
                    type = objectiveType,
                    index = i,
                    completed = finished
                })
            end
        end
        
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00When complete, submit data at: https://github.com/trav346/Questie-Epoch/issues|r", 1, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("===========================================", 0, 1, 1)
        
        _activeTracking[questId] = true
    end
end

function QuestieDataCollector:GetQuestLogIndexById(questId)
    for i = 1, GetNumQuestLogEntries() do
        local _, _, _, isHeader, _, _, _, qId = QuestieCompat.GetQuestLogTitle(i)
        if not isHeader then
            if qId == questId then
                return i
            end
        end
    end
    return nil
end

function QuestieDataCollector:OnQuestTurnedIn(questId)
    -- This event might not fire properly in 3.3.5, but keep it as fallback
    if not questId or not QuestieDataCollection.quests[questId] then return end
    
    -- Capture turn-in NPC
    if _lastQuestGiver and (time() - _lastQuestGiver.timestamp < 5) then
        QuestieDataCollection.quests[questId].turnInNpc = _lastQuestGiver
        
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[DATA] Turn-in NPC Captured: " .. _lastQuestGiver.name .. " (ID: " .. _lastQuestGiver.npcId .. ")|r", 0, 1, 0)
        
        -- Show hyperlink notification
        local questName = QuestieDataCollection.quests[questId].name or "Unknown Quest"
        DEFAULT_CHAT_FRAME:AddMessage("===========================================" , 0, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[QUESTIE] Quest completed! Please " .. CreateQuestDataLink(questId, "[Export]") .. " your captured data to GitHub!|r", 0, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Quest: " .. questName .. " (ID: " .. questId .. ")|r", 1, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("===========================================" , 0, 1, 1)
        
        PlaySound("QUESTCOMPLETED")
    end
    
    _activeTracking[questId] = nil
end

function QuestieDataCollector:OnQuestComplete()
    -- Capture the NPC we're turning in to
    QuestieDataCollector:CaptureNPCData("target")
    
    -- Try to identify which quest is being turned in
    -- In 3.3.5, we need to scan the quest log for quests that are complete
    local questId = nil
    local questName = nil
    
    for i = 1, GetNumQuestLogEntries() do
        local title, _, _, _, _, isComplete, _, qID = QuestieCompat.GetQuestLogTitle(i)
        -- Use our tracked quests to identify Epoch quests
        if isComplete and _activeTracking[qID] then
            questId = qID
            questName = title
            break
        end
    end
    
    if questId and QuestieDataCollection.quests[questId] then
        -- Capture turn-in NPC
        if _lastQuestGiver and (time() - _lastQuestGiver.timestamp < 5) then
            QuestieDataCollection.quests[questId].turnInNpc = _lastQuestGiver
            
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[DATA] Turn-in NPC Captured: " .. _lastQuestGiver.name .. " (ID: " .. _lastQuestGiver.npcId .. ")|r", 0, 1, 0)
            
            -- Show hyperlink notification instead of auto-popup
            DEFAULT_CHAT_FRAME:AddMessage("===========================================" , 0, 1, 1)
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[QUESTIE] Quest completed! Please " .. CreateQuestDataLink(questId, "[Export]") .. " your captured data to GitHub!|r", 0, 1, 0)
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Quest: " .. questName .. " (ID: " .. questId .. ")|r", 1, 1, 0)
            DEFAULT_CHAT_FRAME:AddMessage("===========================================" , 0, 1, 1)
            
            -- Play a subtle sound to notify completion
            PlaySound("QUESTCOMPLETED")
        end
    end
end

function QuestieDataCollector:OnCombatLogEvent(...)
    local timestamp, eventType, _, sourceGUID, sourceName, _, _, destGUID, destName = ...
    
    -- Track when player kills something
    if eventType == "PARTY_KILL" or eventType == "UNIT_DIED" then
        if sourceGUID == UnitGUID("player") and destGUID then
            -- Extract NPC ID from GUID
            local npcId = tonumber(destGUID:sub(9, 12), 16)
            if npcId then
                -- Store recent kill for correlation with quest updates
                _recentKills = _recentKills or {}
                table.insert(_recentKills, {
                    npcId = npcId,
                    name = destName,
                    timestamp = time(),
                    coords = QuestieDataCollector:GetPlayerCoords(),
                    zone = GetRealZoneText(),
                    subzone = GetSubZoneText()
                })
                
                -- Keep only last 10 kills
                if #_recentKills > 10 then
                    table.remove(_recentKills, 1)
                end
            end
        end
    end
end

function QuestieDataCollector:OnQuestLogUpdate()
    -- Check all tracked quests for objective changes
    for questId, _ in pairs(_activeTracking) do
        if QuestieDataCollection.quests[questId] then
            local questLogIndex = QuestieDataCollector:GetQuestLogIndexById(questId)
            if questLogIndex then
                SelectQuestLogEntry(questLogIndex)
                local numObjectives = GetNumQuestLeaderBoards(questLogIndex)
                
                for i = 1, numObjectives do
                    local text, objectiveType, finished = GetQuestLogLeaderBoard(i, questLogIndex)
                    local objData = QuestieDataCollection.quests[questId].objectives[i]
                    
                    if objData and objData.lastText ~= text then
                        -- Objective has changed
                        objData.lastText = text
                        objData.type = objectiveType
                        
                        if not objData.progressLocations then
                            objData.progressLocations = {}
                        end
                        
                        local locData = {
                            coords = QuestieDataCollector:GetPlayerCoords(),
                            zone = GetRealZoneText(),
                            subzone = GetSubZoneText(),
                            text = text,
                            timestamp = time()
                        }
                        
                        -- Special handling for exploration objectives
                        if objectiveType == "event" or objectiveType == "area" then
                            locData.action = "Explored area"
                            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[DATA] Exploration objective captured at [" .. 
                                (locData.coords and locData.coords.x or 0) .. ", " .. 
                                (locData.coords and locData.coords.y or 0) .. "] in " .. 
                                (locData.subzone or locData.zone or "Unknown") .. "|r", 0, 1, 0)
                        -- Try to correlate with recent kills for monster objectives
                        elseif objectiveType == "monster" and _recentKills and #_recentKills > 0 then
                            -- Check most recent kill (within 2 seconds)
                            local recentKill = _recentKills[#_recentKills]
                            if time() - recentKill.timestamp <= 2 then
                                locData.npcId = recentKill.npcId
                                locData.npcName = recentKill.name
                                locData.action = "Killed " .. recentKill.name .. " (ID: " .. recentKill.npcId .. ")"
                                objData.objectiveType = "kill"
                                
                                -- Store NPC info for this objective
                                if not objData.npcs then
                                    objData.npcs = {}
                                end
                                objData.npcs[recentKill.npcId] = recentKill.name
                            end
                        elseif objectiveType == "item" then
                            objData.objectiveType = "item"
                            locData.action = "Item collection"
                            
                            -- Check if we have a target for source info
                            if UnitExists("target") then
                                local targetGUID = UnitGUID("target")
                                if targetGUID then
                                    local npcId = tonumber(targetGUID:sub(9, 12), 16)
                                    if npcId then
                                        locData.sourceNpcId = npcId
                                        locData.sourceNpcName = UnitName("target")
                                        locData.action = locData.action .. " from " .. UnitName("target") .. " (ID: " .. npcId .. ")"
                                    end
                                end
                            end
                        elseif objectiveType == "object" then
                            objData.objectiveType = "object"
                            locData.action = "Object interaction"
                        elseif objectiveType == "event" then
                            objData.objectiveType = "event"
                            locData.action = "Event/Exploration completed"
                            
                            -- Special handling for exploration/discovery objectives
                            if string.find(string.lower(text or ""), "explore") or 
                               string.find(string.lower(text or ""), "discover") or
                               string.find(string.lower(text or ""), "find") or
                               string.find(string.lower(text or ""), "reach") then
                                
                                -- Mark this as a discovery/exploration point
                                objData.discoveryPoint = {
                                    coords = locData.coords,
                                    zone = locData.zone,
                                    subzone = locData.subzone,
                                    completedText = text,
                                    timestamp = time()
                                }
                                
                                DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[DATA] DISCOVERY POINT CAPTURED!|r", 0, 1, 1)
                                DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF  Objective: " .. text .. "|r", 0, 1, 1)
                                DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF  Exact coords: [" .. locData.coords.x .. ", " .. locData.coords.y .. "]|r", 0, 1, 1)
                                DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF  Zone: " .. locData.zone .. (locData.subzone ~= "" and " (" .. locData.subzone .. ")" or "") .. "|r", 0, 1, 1)
                            end
                        end
                        
                        table.insert(objData.progressLocations, locData)
                        
                        -- Objective progress tracked silently
                        if locData.action then
                            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00  Action: " .. locData.action .. "|r", 0, 1, 0)
                        end
                        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00  Location: [" .. locData.coords.x .. ", " .. locData.coords.y .. "] in " .. locData.zone .. "|r", 0, 1, 0)
                    end
                end
            end
        end
    end
end

function QuestieDataCollector:OnLootReceived(message)
    -- Parse loot message for item info
    local itemLink = string.match(message, "|c.-|Hitem:.-|h%[.-%]|h|r")
    if itemLink then
        local itemId = tonumber(string.match(itemLink, "item:(%d+):"))
        local itemName = string.match(itemLink, "%[(.-)%]")
        
        if itemId and itemName then
            -- Use current loot source if available (from LOOT_OPENED)
            if _currentLootSource and (time() - _currentLootSource.timestamp < 3) then
                -- We know exactly what we looted from
                for questId, _ in pairs(_activeTracking or {}) do
                    local questData = QuestieDataCollection.quests[questId]
                    if questData then
                        for objIndex, objective in ipairs(questData.objectives or {}) do
                            if objective.type == "item" and string.find(string.lower(objective.text or ""), string.lower(itemName)) then
                                -- Quest item received!
                                objective.itemLootData = objective.itemLootData or {}
                                
                                local lootEntry = {
                                    itemId = itemId,
                                    itemName = itemName,
                                    sourceType = _currentLootSource.type,
                                    sourceId = _currentLootSource.id,
                                    sourceName = _currentLootSource.name,
                                    coords = _currentLootSource.coords,
                                    zone = _currentLootSource.zone,
                                    subzone = _currentLootSource.subzone,
                                    timestamp = time()
                                }
                                
                                table.insert(objective.itemLootData, lootEntry)
                                
                                -- Update quest progress location
                                objective.progressLocations = objective.progressLocations or {}
                                table.insert(objective.progressLocations, {
                                    coords = _currentLootSource.coords,
                                    zone = _currentLootSource.zone,
                                    subzone = _currentLootSource.subzone,
                                    text = objective.text,
                                    action = "Looted " .. itemName .. " from " .. _currentLootSource.name,
                                    timestamp = time()
                                })
                                
                                if _currentLootSource.type == "mob" then
                                    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[DATA] Confirmed: '" .. itemName .. 
                                        "' (ID: " .. itemId .. ") from mob " .. _currentLootSource.name .. "|r", 0, 1, 0)
                                else
                                    DEFAULT_CHAT_FRAME:AddMessage("|cFF00AAFF[DATA] Confirmed: '" .. itemName .. 
                                        "' (ID: " .. itemId .. ") from object " .. _currentLootSource.name .. "|r", 0, 0.67, 1)
                                end
                            end
                        end
                    end
                end
            elseif _recentKills and #_recentKills > 0 then
                -- Fallback: Check recent kills
                local mostRecentKill = _recentKills[#_recentKills]
                if (time() - mostRecentKill.timestamp) < 5 then
                    -- Link this item drop to the mob
                    for questId, questData in pairs(QuestieDataCollection.quests or {}) do
                        for _, objective in ipairs(questData.objectives or {}) do
                            if objective.type == "item" and string.find(string.lower(objective.text or ""), string.lower(itemName)) then
                                objective.itemSources = objective.itemSources or {}
                                table.insert(objective.itemSources, {
                                    itemId = itemId,
                                    itemName = itemName,
                                    sourceNpcId = mostRecentKill.npcId,
                                    sourceNpcName = mostRecentKill.name,
                                    coords = mostRecentKill.coords,
                                    zone = mostRecentKill.zone,
                                    subzone = mostRecentKill.subzone
                                })
                                
                                DEFAULT_CHAT_FRAME:AddMessage("|cFF00AA00[DATA] Quest item '" .. itemName .. 
                                    "' likely from " .. mostRecentKill.name .. " (ID: " .. mostRecentKill.npcId .. ")|r", 0, 0.7, 0)
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Trigger quest log check when loot is received
    QuestieDataCollector:OnQuestLogUpdate()
end

function QuestieDataCollector:SetupObjectTracking()
    -- Track when player interacts with game objects
    _lastInteractedObject = nil
    
    -- Hook the tooltip to capture object names and IDs when mousing over
    GameTooltip:HookScript("OnShow", function(self)
        if Questie.db.profile.enableDataCollection then
            local name = GameTooltipTextLeft1:GetText()
            if name and not UnitExists("mouseover") then
                -- This might be a game object
                -- Look for object ID in the tooltip lines
                local objectId = nil
                for i = 1, self:NumLines() do
                    local text = _G["GameTooltipTextLeft" .. i]:GetText()
                    if text then
                        -- Look for ID pattern like "ID: 4000003" or just "4000003"
                        local id = string.match(text, "ID:%s*(%d+)") or string.match(text, "^(%d+)$")
                        if id then
                            objectId = tonumber(id)
                            break
                        end
                    end
                end
                
                _lastInteractedObject = {
                    name = name,
                    id = objectId,
                    coords = QuestieDataCollector:GetPlayerCoords(),
                    zone = GetRealZoneText(),
                    subzone = GetSubZoneText(),
                    timestamp = time()
                }
                
                if objectId then
                    DEFAULT_CHAT_FRAME:AddMessage("|cFF8888FF[DATA] Hovering object: " .. name .. " (ID: " .. objectId .. ")|r", 0.5, 0.5, 1)
                end
            end
        end
    end)
end

function QuestieDataCollector:OnLootOpened()
    local coords = QuestieDataCollector:GetPlayerCoords()
    local zone = GetRealZoneText()
    local subzone = GetSubZoneText()
    
    -- Determine loot source type
    local lootSourceType = nil
    local lootSourceId = nil
    local lootSourceName = nil
    
    -- Check if we're looting a corpse (mob)
    if UnitExists("target") and UnitIsDead("target") then
        lootSourceType = "mob"
        lootSourceName = UnitName("target")
        local guid = UnitGUID("target")
        if guid then
            lootSourceId = tonumber(guid:sub(6, 12), 16)
        end
        
        DEFAULT_CHAT_FRAME:AddMessage("|cFFAA8800[DATA] Looting mob: " .. lootSourceName .. 
            " (ID: " .. (lootSourceId or "unknown") .. ") at [" .. coords.x .. ", " .. coords.y .. "]|r", 0.67, 0.53, 0)
    else
        -- This is likely an object interaction
        lootSourceType = "object"
        -- Try to get object name from loot window
        local lootName = GetLootSourceInfo(1)
        if lootName then
            lootSourceName = lootName
        elseif _lastInteractedObject and (time() - _lastInteractedObject.timestamp < 2) then
            lootSourceName = _lastInteractedObject.name
            lootSourceId = _lastInteractedObject.id
        else
            lootSourceName = "Unknown Object"
        end
        
        DEFAULT_CHAT_FRAME:AddMessage("|cFF8888FF[DATA] Looting object: " .. lootSourceName .. 
            " at [" .. coords.x .. ", " .. coords.y .. "]|r", 0.5, 0.5, 1)
        
        -- Store object data in any active quest that might use this object
        local activeCount = 0
        for _ in pairs(_activeTracking or {}) do
            activeCount = activeCount + 1
        end
        
        if activeCount == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DATA] Warning: No quests being tracked! Use /qdc rescan|r", 1, 0, 0)
        else
            for questId, _ in pairs(_activeTracking or {}) do
                local questData = QuestieDataCollection.quests[questId]
                if questData then
                    questData.objects = questData.objects or {}
                    
                    -- Use object name as key, but store ID if we have it
                    if not questData.objects[lootSourceName] then
                        questData.objects[lootSourceName] = {
                            name = lootSourceName,
                            id = lootSourceId,
                            locations = {}
                        }
                    elseif lootSourceId and not questData.objects[lootSourceName].id then
                        -- Update ID if we didn't have it before
                        questData.objects[lootSourceName].id = lootSourceId
                    end
                    
                    -- Add this location if not already tracked
                    local locKey = string.format("%.1f,%.1f", coords.x, coords.y)
                    if not questData.objects[lootSourceName].locations[locKey] then
                        questData.objects[lootSourceName].locations[locKey] = {
                            coords = coords,
                            zone = zone,
                            subzone = subzone,
                            timestamp = time()
                        }
                        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[DATA] Tracked object '" .. lootSourceName .. 
                            "' for quest " .. questId .. " at [" .. coords.x .. ", " .. coords.y .. "]|r", 0, 1, 1)
                    end
                end
            end
        end
    end
    
    -- Store loot source for item tracking
    _currentLootSource = {
        type = lootSourceType,
        id = lootSourceId,
        name = lootSourceName,
        coords = coords,
        zone = zone,
        subzone = subzone,
        timestamp = time()
    }
    
    -- Check all loot items
    local numItems = GetNumLootItems()
    for i = 1, numItems do
        local lootIcon, lootName, lootQuantity, rarity, locked = GetLootSlotInfo(i)
        if lootName then
            local itemLink = GetLootSlotLink(i)
            if itemLink then
                local itemId = tonumber(string.match(itemLink, "item:(%d+):"))
                
                -- Check if this is a quest item
                local isQuestItem = false
                local matchedQuestId = nil
                local matchedObjIndex = nil
                
                -- Check by name matching
                for questId, _ in pairs(_activeTracking or {}) do
                    local questData = QuestieDataCollection.quests[questId]
                    if questData then
                        for objIndex, objective in ipairs(questData.objectives or {}) do
                            if objective.type == "item" and (
                                string.find(string.lower(objective.text or ""), string.lower(lootName)) or
                                string.find(string.lower(lootName), string.lower(objective.lastText or ""))
                            ) then
                                isQuestItem = true
                                matchedQuestId = questId
                                matchedObjIndex = objIndex
                                break
                            end
                        end
                        if isQuestItem then break end
                    end
                end
                
                if isQuestItem and matchedQuestId then
                    local questData = QuestieDataCollection.quests[matchedQuestId]
                    if questData and questData.objectives and questData.objectives[matchedObjIndex] then
                        local objective = questData.objectives[matchedObjIndex]
                        -- This is a quest item!
                        objective.itemLootData = objective.itemLootData or {}
                        
                        local lootEntry = {
                            itemId = itemId,
                            itemName = lootName,
                            sourceType = lootSourceType,  -- "mob" or "object"
                            sourceId = lootSourceId,
                            sourceName = lootSourceName,
                            coords = coords,
                            zone = zone,
                            subzone = subzone,
                            timestamp = time()
                        }
                        
                        table.insert(objective.itemLootData, lootEntry)
                        
                        -- Also store in quest's items table
                        questData.items = questData.items or {}
                        questData.items[itemId] = {
                            name = lootName,
                            objectiveIndex = matchedObjIndex,
                            sources = questData.items[itemId] and questData.items[itemId].sources or {}
                        }
                        table.insert(questData.items[itemId].sources, lootEntry)
                        
                        if lootSourceType == "mob" then
                            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[DATA] Quest item '" .. lootName .. 
                                "' (ID: " .. itemId .. ") from mob: " .. lootSourceName .. "|r", 0, 1, 0)
                        else
                            DEFAULT_CHAT_FRAME:AddMessage("|cFF00AAFF[DATA] Quest item '" .. lootName .. 
                                "' (ID: " .. itemId .. ") from object: " .. lootSourceName .. "|r", 0, 0.67, 1)
                        end
                    end
                end
            end
        end
    end
end

function QuestieDataCollector:OnItemPush(bagSlot)
    -- Track when quest items are received from objects
    if _lastInteractedObject and (time() - _lastInteractedObject.timestamp < 3) then
        -- Get item info from the bag slot
        C_Timer.After(0.1, function()
            for bag = 0, 4 do
                for slot = 1, GetContainerNumSlots(bag) do
                    local itemLink = GetContainerItemLink(bag, slot)
                    if itemLink then
                        local itemName = string.match(itemLink, "%[(.-)%]")
                        -- Check if this is a quest item
                        for questId, questData in pairs(QuestieDataCollection.quests or {}) do
                            for _, objective in ipairs(questData.objectives or {}) do
                                if objective.type == "item" and string.find(objective.text or "", itemName or "") then
                                    objective.objectSources = objective.objectSources or {}
                                    table.insert(objective.objectSources, {
                                        objectName = _lastInteractedObject.name,
                                        itemName = itemName,
                                        coords = _lastInteractedObject.coords,
                                        zone = _lastInteractedObject.zone,
                                        subzone = _lastInteractedObject.subzone
                                    })
                                    
                                    DEFAULT_CHAT_FRAME:AddMessage("|cFF00AAFF[DATA] Quest item '" .. itemName .. 
                                        "' obtained from object: " .. _lastInteractedObject.name .. "|r", 0, 0.7, 1)
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
end

function QuestieDataCollector:OnUIInfoMessage(message)
    -- Capture exploration and discovery objectives
    for questId, _ in pairs(_activeTracking) do
        local questData = QuestieDataCollection.quests[questId]
        if questData then
            local coords = QuestieDataCollector:GetPlayerCoords()
            local zone = GetRealZoneText()
            local subzone = GetSubZoneText()
            
            -- Check if this message is related to quest progress
            -- Common patterns: "Explored X", "Discovered X", "X Explored", "X Discovered", location names
            if message and message ~= "" then
                -- Initialize explorations table if needed
                questData.explorations = questData.explorations or {}
                
                -- Store the exploration event
                local explorationData = {
                    message = message,
                    coords = coords,
                    zone = zone,
                    subzone = subzone,
                    timestamp = time()
                }
                table.insert(questData.explorations, explorationData)
                
                -- Also check objectives for exploration/event types
                for objIndex, objective in ipairs(questData.objectives or {}) do
                    if objective.type == "event" or objective.type == "object" or 
                       string.find(string.lower(objective.text or ""), "explore") or
                       string.find(string.lower(objective.text or ""), "discover") or
                       string.find(string.lower(objective.text or ""), "find") or
                       string.find(string.lower(objective.text or ""), "reach") then
                        
                        -- Store as progress location
                        objective.progressLocations = objective.progressLocations or {}
                        table.insert(objective.progressLocations, {
                            coords = coords,
                            zone = zone,
                            subzone = subzone,
                            text = objective.text,
                            action = "Discovery: " .. message,
                            timestamp = time()
                        })
                        
                        -- Store specific discovery coordinates
                        objective.discoveryCoords = objective.discoveryCoords or {}
                        table.insert(objective.discoveryCoords, {
                            coords = coords,
                            zone = zone,
                            subzone = subzone,
                            trigger = message,
                            timestamp = time()
                        })
                        
                        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF[DATA] Discovery objective progress: " .. message .. "|r", 0, 1, 1)
                        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF  Location: [" .. coords.x .. ", " .. coords.y .. "] in " .. zone .. 
                            (subzone ~= "" and " (" .. subzone .. ")" or "") .. "|r", 0, 1, 1)
                    end
                end
                
                -- Always log exploration messages for Epoch quests
                if string.find(message, "Explored") or string.find(message, "Discovered") or 
                   string.find(message, "Reached") or string.find(message, "Found") then
                    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[DATA] Exploration captured: " .. message .. " at [" .. 
                        string.format("%.1f, %.1f", coords.x, coords.y) .. "]|r", 0, 1, 0)
                end
            end
        end
    end
end


-- Export function to generate database entry
function QuestieDataCollector:ExportQuest(questId)
    local data = QuestieDataCollection.quests[questId]
    if not data then
        DEFAULT_CHAT_FRAME:AddMessage("No data collected for quest " .. questId, 1, 0, 0)
        return
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("=== QUEST DATA EXPORT FOR #" .. questId .. " ===", 0, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("Quest: " .. (data.name or "Unknown"), 1, 1, 0)
    
    -- Quest giver info
    if data.questGiver then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("Quest Giver: %s (ID: %d) at %.1f, %.1f in %s",
            data.questGiver.name, data.questGiver.npcId, 
            data.questGiver.coords.x, data.questGiver.coords.y,
            data.questGiver.zone or "Unknown"), 0, 1, 0)
    end
    
    -- Turn in info
    if data.turnInNpc then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("Turn In: %s (ID: %d) at %.1f, %.1f in %s",
            data.turnInNpc.name, data.turnInNpc.npcId,
            data.turnInNpc.coords.x, data.turnInNpc.coords.y,
            data.turnInNpc.zone or "Unknown"), 0, 1, 0)
    end
    
    -- Objectives
    if data.objectives and #data.objectives > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("Objectives:", 0, 1, 1)
        for _, obj in ipairs(data.objectives) do
            DEFAULT_CHAT_FRAME:AddMessage("  - " .. obj, 1, 1, 1)
        end
    end
    
    -- Mobs tracked
    if data.mobs and next(data.mobs) then
        DEFAULT_CHAT_FRAME:AddMessage("Mobs:", 0, 1, 1)
        for mobId, mobData in pairs(data.mobs) do
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s (ID: %d) Level %s",
                mobData.name, mobId, mobData.level or "?"), 1, 1, 1)
            if mobData.coords and #mobData.coords > 0 then
                DEFAULT_CHAT_FRAME:AddMessage("    Locations:", 0.8, 0.8, 0.8)
                for i = 1, math.min(3, #mobData.coords) do
                    local coord = mobData.coords[i]
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("      %.1f, %.1f", coord.x, coord.y), 0.8, 0.8, 0.8)
                end
                if #mobData.coords > 3 then
                    DEFAULT_CHAT_FRAME:AddMessage("      ... and " .. (#mobData.coords - 3) .. " more locations", 0.8, 0.8, 0.8)
                end
            end
        end
    end
    
    -- Items looted
    if data.items and next(data.items) then
        DEFAULT_CHAT_FRAME:AddMessage("Items:", 0, 1, 1)
        for itemId, itemData in pairs(data.items) do
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s (ID: %d)",
                itemData.name, itemId), 1, 1, 1)
            if itemData.source then
                DEFAULT_CHAT_FRAME:AddMessage("    Source: " .. itemData.source, 0.8, 0.8, 0.8)
            end
        end
    end
    
    -- Objects interacted
    if data.objects and next(data.objects) then
        DEFAULT_CHAT_FRAME:AddMessage("Objects:", 0, 1, 1)
        for objName, objData in pairs(data.objects) do
            if objData.id then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s (ID: %d)", objName, objData.id), 1, 1, 1)
            else
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s", objName), 1, 1, 1)
            end
            if objData.locations then
                DEFAULT_CHAT_FRAME:AddMessage("    Locations:", 0.8, 0.8, 0.8)
                local locCount = 0
                for locKey, locData in pairs(objData.locations) do
                    locCount = locCount + 1
                    if locCount <= 3 then
                        DEFAULT_CHAT_FRAME:AddMessage(string.format("      %.1f, %.1f in %s", 
                            locData.coords.x, locData.coords.y, locData.zone or "Unknown"), 0.8, 0.8, 0.8)
                    end
                end
                if locCount > 3 then
                    DEFAULT_CHAT_FRAME:AddMessage("      ... and " .. (locCount - 3) .. " more locations", 0.8, 0.8, 0.8)
                end
            end
        end
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("=== END EXPORT ===", 0, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("Copy this data to create a GitHub issue", 0, 1, 0)
end

-- This slash command handler is replaced by the more complete one below

-- Helper function for creating clickable quest data links
local function CreateQuestDataLink(questId, questName)
    local linkText = "|cFF00FF00|Hquestiedata:" .. questId .. "|h[Click here to submit quest data for: " .. (questName or "Quest " .. questId) .. "]|h|r"
    return linkText
end

function QuestieDataCollector:ShowTrackedQuests()
    DEFAULT_CHAT_FRAME:AddMessage("=== Tracked Quest Data ===", 0, 1, 1)
    local incompleteCount = 0
    local completeCount = 0
    
    for questId, data in pairs(QuestieDataCollection.quests) do
        local status = _activeTracking[questId] and "|cFF00FF00[ACTIVE]|r" or "|cFFFFFF00[COMPLETE]|r"
        
        -- Add warning for incomplete data
        if data.wasAlreadyAccepted or data.incompleteData then
            status = status .. " |cFFFF0000[INCOMPLETE DATA]|r"
            incompleteCount = incompleteCount + 1
        else
            completeCount = completeCount + 1
        end
        
        DEFAULT_CHAT_FRAME:AddMessage(string.format("%s %d: %s", status, questId, data.name or "Unknown"), 1, 1, 1)
        
        if data.questGiver then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  Giver: %s (%d) at [%.1f, %.1f]", 
                data.questGiver.name, data.questGiver.npcId, 
                data.questGiver.coords.x, data.questGiver.coords.y), 0.7, 0.7, 0.7)
        elseif data.wasAlreadyAccepted then
            DEFAULT_CHAT_FRAME:AddMessage("  |cFFFF0000Quest Giver: MISSING (quest was already accepted)|r", 1, 0.5, 0)
        end
        
        if data.turnInNpc then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  Turn-in: %s (%d) at [%.1f, %.1f]", 
                data.turnInNpc.name, data.turnInNpc.npcId,
                data.turnInNpc.coords.x, data.turnInNpc.coords.y), 0.7, 0.7, 0.7)
        end
    end
    
    DEFAULT_CHAT_FRAME:AddMessage(string.format("\nTotal: %d quests (%d complete, %d incomplete)", 
        completeCount + incompleteCount, completeCount, incompleteCount), 1, 1, 0)
    
    if incompleteCount > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000To get complete data: Abandon and re-accept quests marked as INCOMPLETE|r", 1, 0.5, 0)
    end
end

function QuestieDataCollector:ShowQuestSelectionWindow()
    -- Show ALL captured quest data in one window
    QuestieDataCollector:ShowExportWindow()
end

function QuestieDataCollector:ShowExportableQuests()
    local activeQuests = {}
    local completedQuests = {}
    
    -- Debug: Check what we're working with
    local totalCount = 0
    for _ in pairs(QuestieDataCollection.quests or {}) do
        totalCount = totalCount + 1
    end
    
    if totalCount == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[QUESTIE] No quest data found! Try /qdc debug to check status.|r", 1, 0, 0)
        return
    end
    
    -- Separate active and completed quests
    for questId, data in pairs(QuestieDataCollection.quests or {}) do
        if _activeTracking and _activeTracking[questId] then
            table.insert(activeQuests, {id = questId, data = data})
        else
            table.insert(completedQuests, {id = questId, data = data})
        end
    end
    
    if #activeQuests == 0 and #completedQuests == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[QUESTIE] No quest data captured yet.|r", 0, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Accept and complete some [Epoch] quests to collect data!|r", 1, 1, 0)
        return
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("===========================================", 0, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[QUESTIE] Captured Quest Data:|r", 0, 1, 0)
    DEFAULT_CHAT_FRAME:AddMessage("===========================================", 0, 1, 1)
    
    -- Show completed quests first (ready for export)
    if #completedQuests > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00COMPLETED QUESTS (Ready for Export):|r", 0, 1, 0)
        table.sort(completedQuests, function(a, b) return a.id < b.id end)
        
        for _, quest in ipairs(completedQuests) do
            local questName = quest.data.name or "Unknown Quest"
            local questId = quest.id
            
            -- Show quest with clickable export link
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFFFFFF00%d: %s - |r" .. CreateQuestDataLink(questId, "[Export]"), questId, questName), 1, 1, 0)
            
            -- Show data summary inline
            local hasGiver = quest.data.questGiver and "Giver" or ""
            local hasTurnIn = quest.data.turnInNpc and "Turn-in" or ""
            local npcCount = 0
            local itemCount = 0
            local objectCount = 0
            
            if quest.data.npcs then
                for _ in pairs(quest.data.npcs) do npcCount = npcCount + 1 end
            end
            if quest.data.items then
                for _ in pairs(quest.data.items) do itemCount = itemCount + 1 end
            end
            if quest.data.objects then
                for _ in pairs(quest.data.objects) do objectCount = objectCount + 1 end
            end
            
            local dataParts = {}
            if hasGiver ~= "" then table.insert(dataParts, hasGiver) end
            if hasTurnIn ~= "" then table.insert(dataParts, hasTurnIn) end
            if npcCount > 0 then table.insert(dataParts, npcCount .. " NPCs") end
            if itemCount > 0 then table.insert(dataParts, itemCount .. " Items") end
            if objectCount > 0 then table.insert(dataParts, objectCount .. " Objects") end
            
            if #dataParts > 0 then
                DEFAULT_CHAT_FRAME:AddMessage("    Data: " .. table.concat(dataParts, ", "), 0.7, 0.7, 0.7)
            end
        end
        DEFAULT_CHAT_FRAME:AddMessage("", 1, 1, 1)
    end
    
    -- Show active quests (still being tracked)
    if #activeQuests > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00ACTIVE QUESTS (Still Tracking):|r", 1, 1, 0)
        table.sort(activeQuests, function(a, b) return a.id < b.id end)
        
        for _, quest in ipairs(activeQuests) do
            local questName = quest.data.name or "Unknown Quest"
            local questId = quest.id
            
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cFF888888%d: %s|r", questId, questName), 0.5, 0.5, 0.5)
            
            -- Show what data we have so far
            local dataParts = {}
            if quest.data.questGiver then table.insert(dataParts, "Giver") end
            if quest.data.npcs then 
                local count = 0
                for _ in pairs(quest.data.npcs) do count = count + 1 end
                if count > 0 then table.insert(dataParts, count .. " NPCs") end
            end
            if quest.data.items then
                local count = 0
                for _ in pairs(quest.data.items) do count = count + 1 end
                if count > 0 then table.insert(dataParts, count .. " Items") end
            end
            
            if #dataParts > 0 then
                DEFAULT_CHAT_FRAME:AddMessage("    Collected so far: " .. table.concat(dataParts, ", "), 0.5, 0.5, 0.5)
            else
                DEFAULT_CHAT_FRAME:AddMessage("    No data collected yet", 0.5, 0.5, 0.5)
            end
        end
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("===========================================", 0, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Click [Export] links to submit quest data to GitHub|r", 1, 1, 0)
end

-- Community contribution popup
function QuestieDataCollector:ShowContributionPopup()
    StaticPopupDialogs["QUESTIE_CONTRIBUTE_DATA"] = {
        text = "|cFF00FF00Help Improve Questie for Project Epoch!|r\n\nWe've detected you're playing on Project Epoch. Many quests are missing from our database.\n\nWould you like to help the community by automatically collecting quest data? This will:\n\n• Alert you when accepting missing quests\n• Capture NPC locations and IDs\n• Enable tooltip IDs to show item/NPC/object IDs\n• Track where quest objectives are completed\n• Generate data for GitHub contributions\n\n|cFFFFFF00Your data will only be saved locally.|r",
        button1 = "Yes, I'll Help!",
        button2 = "No Thanks",
        OnAccept = function()
            Questie.db.profile.enableDataCollection = true
            Questie.db.profile.dataCollectionPrompted = true
            QuestieDataCollector:Initialize()
            QuestieDataCollector:EnableTooltipIDs()
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[Questie] Thank you for contributing! Data collection is now active.|r", 0, 1, 0)
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Tooltip IDs have been enabled to help with data collection.|r", 1, 1, 0)
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00When you complete a missing quest, we'll show you the data to submit.|r", 1, 1, 0)
        end,
        OnCancel = function()
            Questie.db.profile.dataCollectionPrompted = true
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[Questie] Data collection disabled. You can enable it later in Advanced settings.|r", 1, 1, 0)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = false,
        preferredIndex = 3,
    }
    StaticPopup_Show("QUESTIE_CONTRIBUTE_DATA")
end

-- Export window for completed quests
function QuestieDataCollector:ShowExportWindow(questId)
    -- If no questId specified, show ALL quests
    if not questId then
        -- Check if we have any data at all
        if not QuestieDataCollection or not QuestieDataCollection.quests or not next(QuestieDataCollection.quests) then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[QUESTIE] No quest data to export. Complete some Epoch quests first!|r", 1, 0, 0)
            return
        end
    else
        -- Specific quest requested
        if not QuestieDataCollection or not QuestieDataCollection.quests then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[QUESTIE] No quest data available!|r", 1, 0, 0)
            return
        end
        
        local data = QuestieDataCollection.quests[questId]
        if not data then 
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[QUESTIE] No data for quest " .. questId .. "!|r", 1, 0, 0)
            return 
        end
    end
    
    -- Create frame if it doesn't exist
    if not QuestieDataCollectorExportFrame then
        local f = CreateFrame("Frame", "QuestieDataCollectorExportFrame", UIParent)
        f:SetFrameStrata("DIALOG")
        f:SetWidth(600)
        f:SetHeight(400)
        f:SetPoint("CENTER")
        
        -- Use Questie's frame style
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })
        
        -- Title
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -20)
        title:SetText("|cFF00FF00Quest Data Ready for Submission!|r")
        f.title = title
        
        -- Step instructions
        local step1 = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        step1:SetPoint("TOP", title, "BOTTOM", 0, -8)
        step1:SetText("|cFFFFFFFFStep 1:|r Click 'Select All' button below")
        
        local step2 = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        step2:SetPoint("TOP", step1, "BOTTOM", 0, -4)
        step2:SetText("|cFFFFFFFFStep 2:|r Copy (Ctrl+C) and paste into GitHub issue")
        
        local step3 = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        step3:SetPoint("TOP", step2, "BOTTOM", 0, -4)
        step3:SetText("|cFFFFFFFFStep 3:|r After submitting, click 'Close & Purge Data'")
        step3:SetTextColor(1, 0.8, 0)
        
        -- Scroll frame for data
        local scrollFrame = CreateFrame("ScrollFrame", "QuestieDataCollectorScrollFrame", f, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 20, -80)
        scrollFrame:SetPoint("BOTTOMRIGHT", -40, 50)
        
        local editBox = CreateFrame("EditBox", "QuestieDataCollectorEditBox", scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetFontObject(ChatFontNormal)
        editBox:SetWidth(540)
        editBox:SetAutoFocus(false)
        editBox:EnableMouse(true)
        -- Don't clear focus immediately - allow selection and copying
        editBox:SetScript("OnEditFocusGained", function(self) 
            self:HighlightText()  -- Auto-select all text when focused
        end)
        editBox:SetScript("OnEscapePressed", function() f:Hide() end)
        -- Prevent editing while allowing selection
        editBox:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                -- If user tries to type, restore original text
                self:SetText(self.originalText or "")
                self:HighlightText()
            end
        end)
        
        -- Set a large initial height for the edit box to enable scrolling
        editBox:SetHeight(2000)
        
        -- Enable mouse wheel scrolling
        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll()
            local maxScroll = self:GetVerticalScrollRange()
            local scrollStep = 30
            
            if delta > 0 then
                -- Scroll up
                self:SetVerticalScroll(math.max(0, current - scrollStep))
            else
                -- Scroll down
                self:SetVerticalScroll(math.min(maxScroll, current + scrollStep))
            end
        end)
        
        scrollFrame:SetScrollChild(editBox)
        f.editBox = editBox
        f.scrollFrame = scrollFrame
        
        -- Select All button
        local copyButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        copyButton:SetPoint("BOTTOMLEFT", 40, 20)
        copyButton:SetWidth(120)
        copyButton:SetHeight(25)
        copyButton:SetText("Select All")
        copyButton:SetScript("OnClick", function()
            editBox:SetFocus()
            editBox:HighlightText()
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00Text selected! Now press Ctrl+C to copy.|r", 0, 1, 0)
        end)
        
        -- Help text about keybind conflicts
        local helpText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        helpText:SetPoint("BOTTOM", copyButton, "TOP", 60, 5)
        helpText:SetText("|cFFFFFF00Tip: If Ctrl+C doesn't work, unbind it in Key Bindings|r")
        helpText:SetTextColor(1, 1, 0, 0.7)
        
        -- Close & Purge Data button
        local purgeButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        purgeButton:SetPoint("BOTTOMRIGHT", -40, 20)
        purgeButton:SetWidth(140)
        purgeButton:SetHeight(25)
        purgeButton:SetText("Close & Purge Data")
        purgeButton:SetScript("OnClick", function()
            -- Clear ALL quest data from the saved variable
            _G.QuestieDataCollection = {
                quests = {},
                enableDataCollection = QuestieDataCollection and QuestieDataCollection.enableDataCollection or false
            }
            -- Also clear the local reference
            QuestieDataCollection = _G.QuestieDataCollection
            
            -- Force the cleared state to be saved immediately
            -- This ensures the empty state persists after reload
            local db = Questie.db.global
            if db then
                db.dataCollectionQuests = {}
            end
            
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[QUESTIE] Thank you for contributing! All quest data has been purged and saved.|r", 0, 1, 0)
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00The data has been cleared. You can safely reload if needed.|r", 1, 1, 0)
            f:Hide()
        end)
        
        -- Close button
        local closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeButton:SetPoint("TOPRIGHT", -5, -5)
        closeButton:SetScript("OnClick", function() f:Hide() end)
        
        f:Hide()
    end
    
    -- Generate export data
    local exportText = ""
    
    if questId then
        -- Single quest export
        local data = QuestieDataCollection.quests[questId]
        exportText = QuestieDataCollector:GenerateExportText(questId, data)
    else
        -- Export ALL quests
        local questList = {}
        for qId, _ in pairs(QuestieDataCollection.quests) do
            -- Only include Epoch quests
            if qId >= 26000 and qId < 27000 then
                table.insert(questList, qId)
            end
        end
        
        -- Sort by quest ID
        table.sort(questList)
        
        if #questList == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[QUESTIE] No Epoch quest data to export!|r", 1, 0, 0)
            return
        end
        
        -- Generate combined export text
        exportText = "=== BATCH QUEST DATA SUBMISSION ===\n"
        exportText = exportText .. "Total Quests: " .. #questList .. "\n\n"
        exportText = exportText .. "=== HOW TO SUBMIT THIS DATA ===\n"
        exportText = exportText .. "1. Select all text in this window (click 'Select All' button)\n"
        exportText = exportText .. "2. Copy it (Ctrl+C)\n"
        exportText = exportText .. "3. Go to: https://github.com/trav346/Questie-Epoch/issues\n"
        exportText = exportText .. "   (Note: You'll need a free GitHub account to submit)\n"
        exportText = exportText .. "4. Click 'New Issue'\n"
        -- Create comma-separated list of quest IDs for the title
        local questIdList = table.concat(questList, ", ")
        exportText = exportText .. "5. Title: 'Missing Quests: " .. questIdList .. "'\n"
        exportText = exportText .. "6. Paste this entire text in the description\n"
        exportText = exportText .. "7. Click 'Submit new issue'\n\n"
        
        for _, qId in ipairs(questList) do
            local data = QuestieDataCollection.quests[qId]
            exportText = exportText .. "════════════════════════════════════════\n"
            exportText = exportText .. QuestieDataCollector:GenerateExportText(qId, data)
            exportText = exportText .. "\n"
        end
    end
    
    -- Update and show frame
    QuestieDataCollectorExportFrame.editBox:SetText(exportText)
    QuestieDataCollectorExportFrame.editBox.originalText = exportText  -- Store for OnTextChanged handler
    QuestieDataCollectorExportFrame.editBox:SetCursorPosition(0)  -- Start at top of text
    
    -- Reset scroll position to top
    if QuestieDataCollectorExportFrame.scrollFrame then
        QuestieDataCollectorExportFrame.scrollFrame:SetVerticalScroll(0)
    end
    
    QuestieDataCollectorExportFrame:Show()
end

function QuestieDataCollector:GenerateExportText(questId, data, skipInstructions)
    local text = ""
    
    if not skipInstructions then
        text = "=== HOW TO SUBMIT THIS DATA ===\n"
        text = text .. "1. Select all text in this window (click 'Select All' button)\n"
        text = text .. "2. Copy it (Ctrl+C)\n"
        text = text .. "3. Go to: https://github.com/trav346/Questie-Epoch/issues\n"
        text = text .. "   (Note: You'll need a free GitHub account to submit)\n"
        text = text .. "4. Click 'New Issue'\n"
        text = text .. "5. Title: 'Missing Quest: " .. (data.name or "Unknown") .. " (" .. questId .. ")'\n"
        text = text .. "6. Paste this entire text in the description\n"
        text = text .. "7. Click 'Submit new issue'\n\n"
    end
    
    text = text .. "=== QUEST DATA ===\n\n"
    
    -- Add warning if quest has incomplete data
    if data.wasAlreadyAccepted or data.incompleteData then
        text = text .. "⚠️ WARNING: INCOMPLETE DATA ⚠️\n"
        text = text .. "This quest was already in the quest log when the addon was installed.\n"
        text = text .. "Quest giver NPC information is missing.\n"
        text = text .. "Please abandon and re-accept this quest for complete data.\n\n"
    end
    
    text = text .. "Quest ID: " .. questId .. "\n"
    text = text .. "Quest Name: " .. (data.name or "Unknown") .. "\n"
    text = text .. "Level: " .. (data.level or "Unknown") .. "\n"
    text = text .. "Zone: " .. (data.zone or "Unknown") .. "\n"
    -- Use current player's faction if not stored in data
    text = text .. "Faction: " .. (data.faction or UnitFactionGroup("player") or "Unknown") .. "\n\n"
    
    if data.questGiver then
        text = text .. "QUEST GIVER:\n"
        text = text .. "  NPC: " .. data.questGiver.name .. " (ID: " .. data.questGiver.npcId .. ")\n"
        text = text .. "  Location: [" .. data.questGiver.coords.x .. ", " .. data.questGiver.coords.y .. "]\n"
        text = text .. "  Zone: " .. data.questGiver.zone .. "\n\n"
    end
    
    if data.objectives and #data.objectives > 0 then
        text = text .. "OBJECTIVES:\n"
        for i, obj in ipairs(data.objectives) do
            text = text .. "  " .. i .. ". " .. obj.text .. " (" .. (obj.type or "unknown") .. ")\n"
            
            -- Show item IDs if collected
            if obj.itemId then
                text = text .. "     Item: " .. obj.itemName .. " (ID: " .. obj.itemId .. ")\n"
            end
            
            -- Show NPC IDs for kill objectives
            if obj.npcs then
                text = text .. "     NPCs: "
                for npcId, npcName in pairs(obj.npcs) do
                    text = text .. npcName .. " (ID: " .. npcId .. ") "
                end
                text = text .. "\n"
            end
            
            -- Show progress locations
            if obj.progressLocations and #obj.progressLocations > 0 then
                text = text .. "     Progress locations:\n"
                for _, loc in ipairs(obj.progressLocations) do
                    text = text .. "       - [" .. loc.coords.x .. ", " .. loc.coords.y .. "] in " .. loc.zone
                    if loc.action then
                        text = text .. " - " .. loc.action
                    end
                    text = text .. "\n"
                end
            end
        end
        text = text .. "\n"
    end
    
    -- Only show quest items (items that are objective requirements)
    if data.items then
        local questItems = {}
        for itemId, itemInfo in pairs(data.items) do
            if itemInfo.objectiveIndex then  -- Only quest items have objective index
                questItems[itemId] = itemInfo
            end
        end
        
        if next(questItems) then
            text = text .. "QUEST ITEMS:\n"
            for itemId, itemInfo in pairs(questItems) do
                text = text .. "  " .. itemInfo.name .. " (ID: " .. itemId .. ")\n"
                
                -- Show drop sources if available
                if itemInfo.sources and #itemInfo.sources > 0 then
                    local mobSources = {}
                    local objectSources = {}
                    
                    for _, source in ipairs(itemInfo.sources) do
                        if source.sourceType == "mob" and source.sourceName then
                            mobSources[source.sourceName] = source.sourceId or true
                        elseif source.sourceType == "object" and source.sourceName then
                            objectSources[source.sourceName] = true
                        end
                    end
                    
                    for mobName, mobId in pairs(mobSources) do
                        if type(mobId) == "number" then
                            text = text .. "    Drops from: " .. mobName .. " (ID: " .. mobId .. ")\n"
                        else
                            text = text .. "    Drops from: " .. mobName .. "\n"
                        end
                    end
                    
                    for objName, _ in pairs(objectSources) do
                        text = text .. "    From object: " .. objName .. "\n"
                    end
                end
            end
            text = text .. "\n"
        end
    end
    
    if data.turnInNpc then
        text = text .. "TURN-IN NPC:\n"
        text = text .. "  NPC: " .. data.turnInNpc.name .. " (ID: " .. data.turnInNpc.npcId .. ")\n"
        text = text .. "  Location: [" .. data.turnInNpc.coords.x .. ", " .. data.turnInNpc.coords.y .. "]\n"
        text = text .. "  Zone: " .. data.turnInNpc.zone .. "\n\n"
    end
    
    text = text .. "DATABASE ENTRIES:\n"
    text = text .. "-- Add to epochQuestDB.lua:\n"
    
    local questGiver = data.questGiver and "{{" .. data.questGiver.npcId .. "}}" or "nil"
    local turnIn = data.turnInNpc and "{{" .. data.turnInNpc.npcId .. "}}" or "nil"
    
    text = text .. string.format('[%d] = {"%s",%s,%s,nil,%d,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,85,nil,nil,nil,nil,nil,nil,0,nil,nil,nil,nil,nil,nil},\n\n',
        questId, data.name or "Unknown", questGiver, turnIn, data.level or 1)
    
    if data.questGiver then
        text = text .. "-- Add to epochNpcDB.lua:\n"
        text = text .. string.format('[%d] = {"%s",nil,nil,%d,%d,0,{[85]={{%.1f,%.1f}}},nil,85,{%d},nil,nil,nil,nil,0},\n',
            data.questGiver.npcId, data.questGiver.name, data.level or 1, data.level or 1,
            data.questGiver.coords.x, data.questGiver.coords.y, questId)
    end
    
    if data.turnInNpc and (not data.questGiver or data.turnInNpc.npcId ~= data.questGiver.npcId) then
        text = text .. string.format('[%d] = {"%s",nil,nil,%d,%d,0,{[85]={{%.1f,%.1f}}},nil,85,nil,{%d},nil,nil,nil,0},\n',
            data.turnInNpc.npcId, data.turnInNpc.name, data.level or 1, data.level or 1,
            data.turnInNpc.coords.x, data.turnInNpc.coords.y, questId)
    end
    
    return text
end

-- Create clickable hyperlink for quest data submission
-- Hook for custom hyperlink handling
local originalSetItemRef = SetItemRef
SetItemRef = function(link, text, button)
    if string.sub(link, 1, 11) == "questiedata" then
        local questId = tonumber(string.sub(link, 13))
        if questId then
            QuestieDataCollector:ShowExportWindow(questId)
        end
    else
        originalSetItemRef(link, text, button)
    end
end

-- Modified turn-in handler to show export window
local originalOnQuestTurnedIn = QuestieDataCollector.OnQuestTurnedIn
function QuestieDataCollector:OnQuestTurnedIn(questId)
    originalOnQuestTurnedIn(self, questId)
    
    -- If this was a tracked quest and data collection is enabled
    if questId and QuestieDataCollection.quests[questId] and Questie.db.profile.enableDataCollection then
        local questData = QuestieDataCollection.quests[questId]
        local questName = questData.name or "Unknown Quest"
        
        -- Play subtle sound for quest completion
        PlaySound("QUESTCOMPLETED")
        
        -- Print hyperlink notification in chat (no auto-popup)
        DEFAULT_CHAT_FRAME:AddMessage("===========================================", 0, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[QUESTIE] Quest completed! Please " .. CreateQuestDataLink(questId, "[Export]") .. " your captured data to GitHub!|r", 0, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Quest: " .. questName .. " (ID: " .. questId .. ")|r", 1, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("===========================================", 0, 1, 1)
    end
end

-- Auto-initialize on first load if enabled
local autoInitFrame = CreateFrame("Frame")
autoInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
autoInitFrame:RegisterEvent("ADDON_LOADED")
autoInitFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Questie" then
        -- Try initializing as soon as Questie loads
        C_Timer.After(0.1, function()
            if Questie and Questie.db and Questie.db.profile.enableDataCollection then
                if not _initialized then
                    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[DATA COLLECTOR] Initializing after Questie load...|r", 1, 1, 0)
                    QuestieDataCollector:Initialize()
                end
            end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        -- Fallback initialization if ADDON_LOADED didn't work
        C_Timer.After(0.5, function()
            if Questie and Questie.db and Questie.db.profile.enableDataCollection then
                if not _initialized then
                    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[DATA COLLECTOR] Auto-initializing after login...|r", 1, 1, 0)
                    QuestieDataCollector:Initialize()
                else
                    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[DATA COLLECTOR] Already initialized|r", 0, 1, 0)
                end
            end
        end)
    end
end)

-- Register slash commands for debugging and control
SLASH_QUESTIEDATACOLLECTOR1 = "/qdc"
SlashCmdList["QUESTIEDATACOLLECTOR"] = function(msg)
    local cmd = string.lower(msg)
    
    if cmd == "enable" then
        Questie.db.profile.enableDataCollection = true
        Questie.db.profile.dataCollectionPrompted = true
        QuestieDataCollector:Initialize()
        QuestieDataCollector:EnableTooltipIDs()
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[DATA COLLECTOR] ENABLED!|r", 0, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Abandon and re-accept quests to collect data|r", 1, 1, 0)
        
    elseif cmd == "disable" then
        Questie.db.profile.enableDataCollection = false
        QuestieDataCollector:RestoreTooltipIDs()
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DATA COLLECTOR] DISABLED|r", 1, 0, 0)
        
    elseif cmd == "status" then
        DEFAULT_CHAT_FRAME:AddMessage("=== DATA COLLECTOR STATUS ===", 0, 1, 1)
        if Questie.db.profile.enableDataCollection then
            DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00Status: ENABLED|r", 0, 1, 0)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000Status: DISABLED|r", 1, 0, 0)
        end
        
        if QuestieDataCollection and QuestieDataCollection.quests then
            local count = 0
            for _ in pairs(QuestieDataCollection.quests) do count = count + 1 end
            DEFAULT_CHAT_FRAME:AddMessage("Tracked quests: " .. count, 1, 1, 1)
        else
            DEFAULT_CHAT_FRAME:AddMessage("No data collected yet", 1, 1, 0)
        end
        
    elseif cmd == "test" then
        -- Force test with current target quest
        DEFAULT_CHAT_FRAME:AddMessage("Testing with quest 26926...", 0, 1, 1)
        QuestieDataCollector:OnQuestAccepted(26926)
        
    elseif cmd == "active" then
        -- Show actively tracked quests
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00=== Actively Tracked Quests ===|r", 1, 1, 0)
        local count = 0
        for questId, _ in pairs(_activeTracking or {}) do
            count = count + 1
            local questData = QuestieDataCollection.quests[questId]
            if questData then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  %d: %s", questId, questData.name or "Unknown"), 0, 1, 0)
            else
                DEFAULT_CHAT_FRAME:AddMessage(string.format("  %d: (no data yet)", questId), 1, 0.5, 0)
            end
        end
        if count == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000No quests currently being tracked! Use /qdc rescan|r", 1, 0, 0)
        else
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Total: %d quest(s) being tracked", count), 0.7, 0.7, 0.7)
        end
    
    elseif cmd == "questlog" then
        -- Show all quests in quest log
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00=== Quest Log ===|r", 1, 1, 0)
        for i = 1, GetNumQuestLogEntries() do
            local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID = QuestieCompat.GetQuestLogTitle(i)
            if not isHeader and questID and questID > 0 then
                local color = "|cFFFFFFFF"
                if questID >= 26000 and questID < 27000 then
                    color = "|cFFFF00FF" -- Magenta for Epoch quests
                end
                DEFAULT_CHAT_FRAME:AddMessage(string.format("%s  %d: %s (Level %d)|r", color, questID, title or "Unknown", level or 0), 1, 1, 1)
            end
        end
    
    elseif string.sub(cmd, 1, 5) == "track" then
        -- Manually track a specific quest for testing
        local questId = tonumber(string.sub(cmd, 7))
        if questId then
            -- Check if quest is in quest log
            local inQuestLog = false
            local questTitle = nil
            for i = 1, GetNumQuestLogEntries() do
                local title, level, _, isHeader, _, _, _, qId = QuestieCompat.GetQuestLogTitle(i)
                if not isHeader and qId == questId then
                    inQuestLog = true
                    questTitle = title
                    break
                end
            end
            
            if inQuestLog then
                _activeTracking[questId] = true
                -- Initialize quest data if not exists
                if not QuestieDataCollection.quests[questId] then
                    QuestieDataCollection.quests[questId] = {
                        id = questId,
                        name = questTitle,
                        acceptTime = time(),
                        zone = GetRealZoneText(),
                        objectives = {},
                        npcs = {},
                        items = {},
                        objects = {},
                        sessionStart = date("%Y-%m-%d %H:%M:%S")
                    }
                end
                DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[DATA] Now tracking quest " .. questId .. ": " .. (questTitle or "Unknown") .. "|r", 0, 1, 0)
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DATA] Quest " .. questId .. " not found in your quest log|r", 1, 0, 0)
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Usage: /qdc track <questId>|r", 1, 1, 0)
        end
        
    elseif string.sub(cmd, 1, 6) == "export" then
        -- Export specific quest or show selection window
        local questId = tonumber(string.sub(cmd, 8))
        DEFAULT_CHAT_FRAME:AddMessage("|cFFCCCCCC[DEBUG] Export command received. QuestId: " .. tostring(questId) .. "|r", 0.8, 0.8, 0.8)
        if questId then
            -- Export specific quest: /qdc export 26934
            DEFAULT_CHAT_FRAME:AddMessage("|cFFCCCCCC[DEBUG] Calling ShowExportWindow with questId: " .. questId .. "|r", 0.8, 0.8, 0.8)
            QuestieDataCollector:ShowExportWindow(questId)
        else
            -- No quest ID specified, show selection window
            DEFAULT_CHAT_FRAME:AddMessage("|cFFCCCCCC[DEBUG] Calling ShowQuestSelectionWindow|r", 0.8, 0.8, 0.8)
            QuestieDataCollector:ShowQuestSelectionWindow()
        end
        
    elseif string.sub(cmd, 1, 6) == "turnin" then
        -- Manual turn-in capture: /qdc turnin <questId>
        local questId = tonumber(string.sub(cmd, 8))
        if questId and QuestieDataCollection.quests[questId] then
            -- Capture current target as turn-in NPC
            if UnitExists("target") and not UnitIsPlayer("target") then
                local name = UnitName("target")
                local guid = UnitGUID("target")
                local npcId = nil
                
                if guid then
                    npcId = tonumber(guid:sub(6, 12), 16)
                end
                
                if npcId then
                    local coords = QuestieDataCollector:GetPlayerCoords()
                    QuestieDataCollection.quests[questId].turnInNpc = {
                        npcId = npcId,
                        name = name,
                        coords = coords,
                        zone = GetRealZoneText(),
                        subzone = GetSubZoneText(),
                        timestamp = time()
                    }
                    
                    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[DATA] Turn-in NPC manually captured: " .. name .. " (ID: " .. npcId .. ")|r", 0, 1, 0)
                    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00Quest " .. questId .. " now has complete data!|r", 0, 1, 0)
                else
                    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DATA] Error: Could not get NPC ID from target|r", 1, 0, 0)
                end
            else
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DATA] Error: Target an NPC first|r", 1, 0, 0)
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[DATA] Usage: /qdc turnin <questId> (while targeting the turn-in NPC)|r", 1, 0, 0)
        end
        
    elseif cmd == "clear" then
        QuestieDataCollection = {quests = {}, version = 1, sessionStart = date("%Y-%m-%d %H:%M:%S")}
        _activeTracking = {} -- Also clear active tracking
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[DATA COLLECTOR] All quest data cleared.|r", 0, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00Do /reload to save the cleared state.|r", 1, 1, 0)
        
    elseif cmd == "rescan" then
        -- Re-scan quest log for missing quests
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[QuestieDataCollector] Starting rescan...|r", 1, 1, 0)
        _activeTracking = {} -- Clear current tracking
        QuestieDataCollector:CheckExistingQuests()
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[QuestieDataCollector] Re-scanned quest log for missing quests|r", 0, 1, 0)
    elseif cmd == "test" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[QDC Test] Checking if collector is working...|r", 1, 1, 0)
        DEFAULT_CHAT_FRAME:AddMessage("  Initialized: " .. tostring(_initialized), 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("  Enabled: " .. tostring(Questie and Questie.db and Questie.db.profile.enableDataCollection), 1, 1, 1)
        local count = 0
        for k,v in pairs(_activeTracking or {}) do count = count + 1 end
        DEFAULT_CHAT_FRAME:AddMessage("  Tracking: " .. count .. " quests", 1, 1, 1)
        
    elseif cmd == "debug" then
        -- Toggle debug mode
        if not Questie.db.profile.debugDataCollector then
            Questie.db.profile.debugDataCollector = true
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Questie Data Collector]|r Debug mode ENABLED - will show table quest IDs", 1, 0, 0)
        else
            Questie.db.profile.debugDataCollector = false
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[Questie Data Collector]|r Debug mode DISABLED", 1, 0, 0)
        end
        DEFAULT_CHAT_FRAME:AddMessage("QuestieDataCollection table:", 0, 1, 1)
        if QuestieDataCollection then
            DEFAULT_CHAT_FRAME:AddMessage("  Exists: YES", 0, 1, 0)
            DEFAULT_CHAT_FRAME:AddMessage("  Type: " .. type(QuestieDataCollection), 1, 1, 1)
            if QuestieDataCollection.quests then
                local count = 0
                for k,v in pairs(QuestieDataCollection.quests) do 
                    count = count + 1
                    DEFAULT_CHAT_FRAME:AddMessage("    Quest " .. k .. ": " .. (v.name or "Unknown"), 1, 1, 1)
                end
                DEFAULT_CHAT_FRAME:AddMessage("  Total quests: " .. count, 1, 1, 1)
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("  Exists: NO", 1, 0, 0)
        end
        
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FFFF=== QUESTIE DATA COLLECTOR ===|r", 0, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc enable - Enable data collection", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc disable - Disable data collection", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc status - Check current status", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc export - Open export window for first Epoch quest", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc export <id> - Export specific quest data", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc turnin <id> - Manually capture turn-in NPC (target NPC first)", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc clear - Clear all data", 1, 1, 1)
        DEFAULT_CHAT_FRAME:AddMessage("/qdc rescan - Re-scan quest log for missing quests", 1, 1, 1)
    end
end

return QuestieDataCollector