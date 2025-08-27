---@class QuestieMapZoomFix
local QuestieMapZoomFix = QuestieLoader:CreateModule("QuestieMapZoomFix")

---@type QuestieMap
local QuestieMap = QuestieLoader:ImportModule("QuestieMap")

local HBDPins = LibStub("HereBeDragonsQuestie-Pins-2.0")

-- Store original positions when icons are created
local iconOriginalPositions = {}
local currentMapScale = 1

function QuestieMapZoomFix:Initialize()
    -- Hook into WorldMapFrame scale changes
    if WorldMapFrame then
        self:HookMapScaling()
    end
    
    -- Hook HBD pin updates to store original positions
    hooksecurefunc(HBDPins, "AddWorldMapIconMap", function(self, pin, icon, mapID, x, y)
        if icon and icon.SetPoint then
            -- Store the original coordinates
            if not iconOriginalPositions[icon] then
                iconOriginalPositions[icon] = {x = x, y = y, mapID = mapID}
            end
        end
    end)
    
    Questie:Debug(Questie.DEBUG_DEVELOP, "[QuestieMapZoomFix] Initialized map zoom fix")
end

function QuestieMapZoomFix:HookMapScaling()
    -- Hook the scroll frame if it exists (used for zooming)
    if WorldMapScrollFrame then
        -- Store original OnMouseWheel handler
        local originalMouseWheel = WorldMapScrollFrame:GetScript("OnMouseWheel")
        
        WorldMapScrollFrame:SetScript("OnMouseWheel", function(self, delta)
            -- Call original handler first
            if originalMouseWheel then
                originalMouseWheel(self, delta)
            end
            
            -- After zoom, recalculate pin positions
            C_Timer.After(0.01, function()
                QuestieMapZoomFix:RecalculatePinPositions()
            end)
        end)
    end
    
    -- Hook into any scale changes
    if WorldMapFrame.ScrollContainer then
        hooksecurefunc(WorldMapFrame.ScrollContainer, "SetScale", function(self, scale)
            if scale ~= currentMapScale then
                currentMapScale = scale
                QuestieMapZoomFix:RecalculatePinPositions()
            end
        end)
    end
end

function QuestieMapZoomFix:RecalculatePinPositions()
    -- Get current map info
    local mapID = WorldMapFrame:GetMapID()
    if not mapID then return end
    
    -- Get the current scale (zoom level)
    local scale = 1
    if WorldMapFrame.ScrollContainer then
        scale = WorldMapFrame.ScrollContainer:GetScale() or 1
    elseif WorldMapScrollFrame then
        scale = WorldMapScrollFrame:GetScale() or 1
    end
    
    -- Recalculate positions for all pins
    for icon, originalPos in pairs(iconOriginalPositions) do
        if icon and icon:IsShown() and originalPos.mapID == mapID then
            -- Get the frame dimensions
            local mapWidth = WorldMapFrame:GetWidth()
            local mapHeight = WorldMapFrame:GetHeight()
            
            -- Adjust coordinates based on zoom
            local adjustedX = originalPos.x
            local adjustedY = originalPos.y
            
            -- When zoomed in, we need to offset the coordinates
            if scale > 1 then
                -- Calculate the zoom center (usually map center unless panning)
                local centerX = 0.5
                local centerY = 0.5
                
                -- Adjust icon position relative to zoom center
                adjustedX = centerX + (originalPos.x - centerX) * scale
                adjustedY = centerY + (originalPos.y - centerY) * scale
            end
            
            -- Apply the adjusted position
            if icon.SetPoint then
                icon:ClearAllPoints()
                icon:SetPoint("CENTER", WorldMapFrame, "TOPLEFT", adjustedX * mapWidth, -adjustedY * mapHeight)
            end
        end
    end
end

-- Clean up stored positions when map changes
function QuestieMapZoomFix:OnMapChanged()
    -- Clear positions for icons that are no longer visible
    local toRemove = {}
    for icon, _ in pairs(iconOriginalPositions) do
        if not icon or not icon:IsShown() then
            table.insert(toRemove, icon)
        end
    end
    
    for _, icon in ipairs(toRemove) do
        iconOriginalPositions[icon] = nil
    end
end

-- Hook map change event
hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
    QuestieMapZoomFix:OnMapChanged()
end)

return QuestieMapZoomFix