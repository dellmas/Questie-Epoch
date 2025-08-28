---@class TaskQueue
local TaskQueue = QuestieLoader:CreateModule("TaskQueue")
local _TaskQueue = TaskQueue.private

_TaskQueue.queue = {}
_TaskQueue.frame = nil

function TaskQueue:OnUpdate()
    local val = table.remove(_TaskQueue.queue, 1)
    if val then 
        val()
    else
        -- Queue is empty, hide the frame to stop OnUpdate calls
        if _TaskQueue.frame then
            _TaskQueue.frame:Hide()
        end
    end
end

function TaskQueue:Queue(...)
    for _,val in pairs({...}) do
        table.insert(_TaskQueue.queue, val)
    end
    -- Show the frame to start processing if it's hidden
    if _TaskQueue.frame and not _TaskQueue.frame:IsShown() then
        _TaskQueue.frame:Show()
    end
end

local taskQueueEventFrame = CreateFrame("Frame", "QuestieTaskQueueEventFrame", UIParent)
taskQueueEventFrame:SetScript("OnUpdate", TaskQueue.OnUpdate)
_TaskQueue.frame = taskQueueEventFrame
-- Start with the frame hidden since the queue is empty
taskQueueEventFrame:Hide()