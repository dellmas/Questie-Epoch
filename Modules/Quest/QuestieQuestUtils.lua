---@class QuestieQuestUtils
local QuestieQuestUtils = QuestieLoader:CreateModule("QuestieQuestUtils")

---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")

-- COMPATIBILITY ---
local GetQuestLogIndexByID = QuestieCompat.GetQuestLogIndexByID
local GetQuestLogTitle = QuestieCompat.GetQuestLogTitle

-- Cache for quest objectives to reduce API calls
local objectiveCache = {}
local cacheResetTimer = nil

-- Function to safely get quest objectives without taint
---@param questId number The quest ID to get objectives for
---@param questLogIndex number? Optional quest log index if already known
---@return table? objectives Array of objective data or nil if unavailable
function QuestieQuestUtils:GetQuestObjectivesSafe(questId, questLogIndex)
    -- Check cache first
    if objectiveCache[questId] and objectiveCache[questId].expires > GetTime() then
        return objectiveCache[questId].objectives
    end
    
    -- Get quest log index if not provided
    if not questLogIndex then
        questLogIndex = GetQuestLogIndexByID and GetQuestLogIndexByID(questId)
        if not questLogIndex or questLogIndex == 0 then
            return nil
        end
    end
    
    -- Preserve current selection to avoid taint
    local originalSelection = GetQuestLogSelection and GetQuestLogSelection()
    local objectives = {}
    local success = false
    
    -- Try to get objectives without selecting
    if GetNumQuestLeaderBoards then
        -- First try: Get objectives for the current selection if it matches
        if originalSelection == questLogIndex then
            local numObjectives = GetNumQuestLeaderBoards()
            if numObjectives and numObjectives > 0 then
                success = true
                for i = 1, numObjectives do
                    local description, objType, finished, numFulfilled, numRequired = GetQuestLogLeaderBoard(i)
                    if description then
                        objectives[i] = {
                            description = description,
                            type = objType,
                            finished = finished,
                            numFulfilled = tonumber(numFulfilled) or 0,
                            numRequired = tonumber(numRequired) or 0,
                            index = i
                        }
                    end
                end
            end
        elseif SelectQuestLogEntry then
            -- Second try: Temporarily select the quest
            SelectQuestLogEntry(questLogIndex)
            local numObjectives = GetNumQuestLeaderBoards()
            if numObjectives and numObjectives > 0 then
                success = true
                for i = 1, numObjectives do
                    local description, objType, finished, numFulfilled, numRequired = GetQuestLogLeaderBoard(i)
                    if description then
                        objectives[i] = {
                            description = description,
                            type = objType,
                            finished = finished,
                            numFulfilled = tonumber(numFulfilled) or 0,
                            numRequired = tonumber(numRequired) or 0,
                            index = i
                        }
                    end
                end
            end
            
            -- Restore original selection
            if originalSelection and originalSelection > 0 then
                SelectQuestLogEntry(originalSelection)
            end
        end
    end
    
    if success then
        -- Cache the results
        objectiveCache[questId] = {
            objectives = objectives,
            expires = GetTime() + 1 -- Cache for 1 second
        }
        return objectives
    end
    
    return nil
end

-- Clear cache periodically to prevent memory buildup
function QuestieQuestUtils:ClearObjectiveCache()
    local now = GetTime()
    for questId, data in pairs(objectiveCache) do
        if data.expires < now then
            objectiveCache[questId] = nil
        end
    end
end

-- Get quest info without taint
---@param questId number The quest ID
---@param questLogIndex number? Optional quest log index
---@return string? title, number? level, string? questTag, boolean? isComplete
function QuestieQuestUtils:GetQuestInfoSafe(questId, questLogIndex)
    -- Get quest log index if not provided
    if not questLogIndex then
        questLogIndex = GetQuestLogIndexByID and GetQuestLogIndexByID(questId)
        if not questLogIndex or questLogIndex == 0 then
            return nil, nil, nil, nil
        end
    end
    
    local title, level, questTag, isHeader, _, isComplete = GetQuestLogTitle(questLogIndex)
    if not isHeader and title then
        return title, level, questTag, isComplete
    end
    
    return nil, nil, nil, nil
end

-- Initialize cleanup timer
function QuestieQuestUtils:Initialize()
    if not cacheResetTimer then
        -- Create a frame for periodic cleanup
        local cleanupFrame = CreateFrame("Frame")
        cleanupFrame.elapsed = 0
        cleanupFrame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = self.elapsed + elapsed
            if self.elapsed >= 5 then -- Clean cache every 5 seconds
                self.elapsed = 0
                QuestieQuestUtils:ClearObjectiveCache()
            end
        end)
        cacheResetTimer = cleanupFrame
    end
end

return QuestieQuestUtils