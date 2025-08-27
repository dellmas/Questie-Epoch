---@class EpochDatabaseValidator
local EpochDatabaseValidator = QuestieLoader:CreateModule("EpochDatabaseValidator")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")

local validationErrors = {}
local validationWarnings = {}

function EpochDatabaseValidator:Initialize()
    -- This module validates Epoch database integrity
    return true
end

function EpochDatabaseValidator:ValidateEpochData()
    validationErrors = {}
    validationWarnings = {}
    
    Questie:Print("[Epoch Validator] Starting database validation...")
    
    -- Load the raw Epoch data with error handling
    local success, epochQuestData, epochNpcData, epochItemData, epochObjectData
    
    success, epochQuestData = pcall(function()
        return QuestieDB._epochQuestData or _G.epochQuestData
    end)
    
    if not success or not epochQuestData then
        Questie:Print("[Epoch Validator] |cFFFF0000ERROR: Could not load Epoch quest database!|r")
        table.insert(validationErrors, "Epoch quest database not found or failed to load!")
        self:PrintValidationResults()
        return false
    end
    
    Questie:Print("[Epoch Validator] Loaded quest data, checking NPCs...")
    
    success, epochNpcData = pcall(function()
        return QuestieDB._epochNpcData or _G.epochNpcData
    end)
    
    if not success or not epochNpcData then
        Questie:Print("[Epoch Validator] |cFFFFFF00Warning: NPC database not loaded|r")
    end
    
    success, epochItemData = pcall(function()
        return QuestieDB._epochItemData or _G.epochItemData
    end)
    
    success, epochObjectData = pcall(function()
        return QuestieDB._epochObjectData or _G.epochObjectData
    end)
    
    -- Count entries for progress tracking
    local questCount = 0
    local npcCount = 0
    
    if epochQuestData then
        for _ in pairs(epochQuestData) do
            questCount = questCount + 1
        end
    end
    
    if epochNpcData then
        for _ in pairs(epochNpcData) do
            npcCount = npcCount + 1
        end
    end
    
    Questie:Print(string.format("[Epoch Validator] Found %d quests and %d NPCs to validate", questCount, npcCount))
    
    -- Validate quest data with error handling
    if epochQuestData then
        local ok, err = pcall(function()
            self:ValidateQuests(epochQuestData, epochNpcData, epochItemData, epochObjectData)
        end)
        if not ok then
            Questie:Print("[Epoch Validator] |cFFFF0000ERROR during quest validation!|r")
            Questie:Print("[Epoch Validator] Error details: " .. tostring(err))
        end
    end
    
    -- Validate NPC data with error handling
    if epochNpcData then
        local ok, err = pcall(function()
            self:ValidateNPCs(epochNpcData, epochQuestData)
        end)
        if not ok then
            Questie:Print("[Epoch Validator] |cFFFF0000ERROR during NPC validation!|r")
            Questie:Print("[Epoch Validator] Error details: " .. tostring(err))
        end
    end
    
    -- Print results
    self:PrintValidationResults()
    
    return #validationErrors == 0
end

function EpochDatabaseValidator:ValidateQuests(questData, npcData, itemData, objectData)
    local questCount = 0
    local validatedQuests = {}
    local processed = 0
    local maxToProcess = 1000  -- Process more quests (increase if needed)
    
    for questId, quest in pairs(questData) do
        questCount = questCount + 1
        processed = processed + 1
        
        -- Show progress every 50 quests
        if processed % 50 == 0 then
            Questie:Print(string.format("[Epoch Validator] Processing quest %d/%d...", processed, questCount))
        end
        
        -- Limit processing to prevent hanging
        if processed > maxToProcess then
            Questie:Print(string.format("[Epoch Validator] Validated first %d quests (sampling mode)", maxToProcess))
            break
        end
        
        validatedQuests[questId] = true
        
        -- Check quest structure
        if type(quest) ~= "table" then
            table.insert(validationErrors, string.format("Quest %d is not a table!", questId))
        elseif #quest < 1 then
            table.insert(validationErrors, string.format("Quest %d has no data!", questId))
        else
            local questName = quest[1]
            local startedBy = quest[2]  -- NPCs that start the quest
            local finishedBy = quest[3] -- NPCs that end the quest
            
            -- Validate quest name
            if not questName or questName == "" then
                table.insert(validationErrors, string.format("Quest %d has no name!", questId))
            end
            
            -- Validate quest starter NPCs
            if startedBy and type(startedBy) == "table" then
                for idx, npcEntry in pairs(startedBy) do
                    -- Check if it's a nested table (which might be wrong)
                    if type(npcEntry) == "table" then
                        -- This could be {{npcId}} instead of {npcId}
                        if #npcEntry > 0 and type(npcEntry[1]) == "number" then
                            -- It's a table containing NPC ID - this might be wrong format
                            table.insert(validationErrors, string.format("Quest %d (%s) has NESTED TABLE in starters[%d]: should be %d not {%d}", 
                                questId, questName or "?", idx, npcEntry[1], npcEntry[1]))
                        else
                            table.insert(validationErrors, string.format("Quest %d (%s) has invalid nested table in starters[%d]", 
                                questId, questName or "?", idx))
                        end
                    elseif type(npcEntry) ~= "number" then
                        table.insert(validationErrors, string.format("Quest %d (%s) has invalid starter NPC type: %s", 
                            questId, questName or "?", type(npcEntry)))
                    elseif npcData and not npcData[npcEntry] then
                        table.insert(validationWarnings, string.format("Quest %d (%s) references missing starter NPC %d", 
                            questId, questName or "?", npcEntry))
                    end
                end
            end
            
            -- Validate quest ender NPCs
            if finishedBy and type(finishedBy) == "table" then
                for idx, npcEntry in pairs(finishedBy) do
                    -- Check if it's a nested table (which might be wrong)
                    if type(npcEntry) == "table" then
                        -- This could be {{npcId}} instead of {npcId}
                        if #npcEntry > 0 and type(npcEntry[1]) == "number" then
                            -- It's a table containing NPC ID - this might be wrong format
                            table.insert(validationErrors, string.format("Quest %d (%s) has NESTED TABLE in enders[%d]: should be %d not {%d}", 
                                questId, questName or "?", idx, npcEntry[1], npcEntry[1]))
                        else
                            table.insert(validationErrors, string.format("Quest %d (%s) has invalid nested table in enders[%d]", 
                                questId, questName or "?", idx))
                        end
                    elseif type(npcEntry) ~= "number" then
                        table.insert(validationErrors, string.format("Quest %d (%s) has invalid ender NPC type: %s", 
                            questId, questName or "?", type(npcEntry)))
                    elseif npcData and not npcData[npcEntry] then
                        table.insert(validationWarnings, string.format("Quest %d (%s) references missing ender NPC %d", 
                            questId, questName or "?", npcEntry))
                    end
                end
            end
            
            -- Check for quest objectives (position 9)
            local objectives = quest[9]
            if objectives and type(objectives) == "table" then
                -- Validate kill objectives
                if objectives[1] and type(objectives[1]) == "table" then
                    for _, objective in pairs(objectives[1]) do
                        if type(objective) == "table" then
                            local npcId = objective[1]
                            if npcId and type(npcId) == "number" and npcData and not npcData[npcId] then
                                table.insert(validationWarnings, string.format("Quest %d (%s) has kill objective for missing NPC %d", 
                                    questId, questName or "?", npcId))
                            end
                        end
                    end
                end
                
                -- Validate item objectives
                if objectives[3] and type(objectives[3]) == "table" then
                    for _, objective in pairs(objectives[3]) do
                        if type(objective) == "table" then
                            local itemId = objective[1]
                            if itemId and type(itemId) == "number" and itemData and not itemData[itemId] then
                                table.insert(validationWarnings, string.format("Quest %d (%s) has objective for missing item %d", 
                                    questId, questName or "?", itemId))
                            end
                        end
                    end
                end
            end
        end
    end
    
    Questie:Debug(DEBUG_INFO, string.format("[Epoch Validator] Validated %d quests", questCount))
end

function EpochDatabaseValidator:ValidateNPCs(npcData, questData)
    local npcCount = 0
    local validatedNPCs = {}
    local processed = 0
    local maxToProcess = 1000  -- Process more quests (increase if needed)
    
    for npcId, npc in pairs(npcData) do
        npcCount = npcCount + 1
        processed = processed + 1
        
        -- Show progress every 50 NPCs
        if processed % 50 == 0 then
            Questie:Print(string.format("[Epoch Validator] Processing NPC %d/%d...", processed, npcCount))
        end
        
        -- Limit processing to prevent hanging
        if processed > maxToProcess then
            Questie:Print(string.format("[Epoch Validator] Validated first %d NPCs (sampling mode)", maxToProcess))
            break
        end
        
        validatedNPCs[npcId] = true
        
        -- Check NPC structure
        if type(npc) ~= "table" then
            table.insert(validationErrors, string.format("NPC %d is not a table!", npcId))
        elseif #npc < 1 then
            table.insert(validationErrors, string.format("NPC %d has no data!", npcId))
        else
            local npcName = npc[1]
            local questStarts = npc[10]  -- Quests this NPC starts
            local questEnds = npc[11]    -- Quests this NPC ends
            
            -- Validate NPC name
            if not npcName or npcName == "" then
                table.insert(validationErrors, string.format("NPC %d has no name!", npcId))
            end
            
            -- Validate quest starts
            if questStarts then
                if type(questStarts) ~= "table" then
                    table.insert(validationErrors, string.format("NPC %d (%s) has invalid questStarts field (not a table): %s", 
                        npcId, npcName or "?", type(questStarts)))
                else
                    for _, questId in pairs(questStarts) do
                        if type(questId) ~= "number" then
                            table.insert(validationErrors, string.format("NPC %d (%s) has non-numeric quest in starts: %s", 
                                npcId, npcName or "?", tostring(questId)))
                        elseif questData and not questData[questId] then
                            table.insert(validationWarnings, string.format("NPC %d (%s) starts missing quest %d", 
                                npcId, npcName or "?", questId))
                        elseif questData and questData[questId] then
                            -- Verify the quest actually lists this NPC as a starter
                            local quest = questData[questId]
                            local starters = quest[2]
                            local found = false
                            if starters and type(starters) == "table" then
                                for _, starterId in pairs(starters) do
                                    if starterId == npcId then
                                        found = true
                                        break
                                    end
                                end
                            end
                            if not found then
                                table.insert(validationWarnings, string.format("NPC %d (%s) claims to start quest %d, but quest doesn't list this NPC", 
                                    npcId, npcName or "?", questId))
                            end
                        end
                    end
                end
            end
            
            -- Validate quest ends
            if questEnds then
                if type(questEnds) ~= "table" then
                    table.insert(validationErrors, string.format("NPC %d (%s) has invalid questEnds field (not a table): %s", 
                        npcId, npcName or "?", type(questEnds)))
                else
                    for _, questId in pairs(questEnds) do
                        if type(questId) ~= "number" then
                            table.insert(validationErrors, string.format("NPC %d (%s) has non-numeric quest in ends: %s", 
                                npcId, npcName or "?", tostring(questId)))
                        elseif questData and not questData[questId] then
                            table.insert(validationWarnings, string.format("NPC %d (%s) ends missing quest %d", 
                                npcId, npcName or "?", questId))
                        elseif questData and questData[questId] then
                            -- Verify the quest actually lists this NPC as an ender
                            local quest = questData[questId]
                            local enders = quest[3]
                            local found = false
                            if enders and type(enders) == "table" then
                                for _, enderId in pairs(enders) do
                                    if enderId == npcId then
                                        found = true
                                        break
                                    end
                                end
                            end
                            if not found then
                                table.insert(validationWarnings, string.format("NPC %d (%s) claims to end quest %d, but quest doesn't list this NPC", 
                                    npcId, npcName or "?", questId))
                            end
                        end
                    end
                end
            end
        end
    end
    
    Questie:Debug(DEBUG_INFO, string.format("[Epoch Validator] Validated %d NPCs", npcCount))
end

function EpochDatabaseValidator:PrintValidationResults()
    if #validationErrors > 0 then
        Questie:Print("[Epoch Validator] |cFFFF0000ERRORS FOUND:|r")
        for i = 1, math.min(10, #validationErrors) do
            Questie:Print("  |cFFFF0000ERROR:|r " .. validationErrors[i])
        end
        if #validationErrors > 10 then
            Questie:Print(string.format("  ... and %d more errors", #validationErrors - 10))
        end
    end
    
    if #validationWarnings > 0 then
        Questie:Print("[Epoch Validator] |cFFFFFF00Warnings found:|r")
        for i = 1, math.min(5, #validationWarnings) do
            Questie:Debug(DEBUG_INFO, "  WARNING: " .. validationWarnings[i])
        end
        if #validationWarnings > 5 then
            Questie:Debug(DEBUG_INFO, string.format("  ... and %d more warnings", #validationWarnings - 5))
        end
    end
    
    if #validationErrors == 0 and #validationWarnings == 0 then
        Questie:Print("[Epoch Validator] |cFF00FF00All Epoch database checks passed!|r")
    else
        Questie:Print(string.format("[Epoch Validator] Found %d errors and %d warnings", #validationErrors, #validationWarnings))
    end
end

-- Slash command for manual validation
SLASH_EPOCHVALIDATE1 = "/epochvalidate"
SlashCmdList["EPOCHVALIDATE"] = function()
    EpochDatabaseValidator:ValidateEpochData()
end

return EpochDatabaseValidator