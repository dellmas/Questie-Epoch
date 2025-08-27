---@class QuestieSlash
local QuestieSlash = QuestieLoader:CreateModule("QuestieSlash")

---@type QuestieOptions
local QuestieOptions = QuestieLoader:ImportModule("QuestieOptions")
---@type QuestieJourney
local QuestieJourney = QuestieLoader:ImportModule("QuestieJourney")
---@type QuestieQuest
local QuestieQuest = QuestieLoader:ImportModule("QuestieQuest")
---@type QuestieTracker
local QuestieTracker = QuestieLoader:ImportModule("QuestieTracker")
---@type QuestieSearch
local QuestieSearch = QuestieLoader:ImportModule("QuestieSearch")
---@type QuestieMap
local QuestieMap = QuestieLoader:ImportModule("QuestieMap")
---@type QuestieLib
local QuestieLib = QuestieLoader:ImportModule("QuestieLib")
---@type QuestieDB
local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
---@type l10n
local l10n = QuestieLoader:ImportModule("l10n")
---@type QuestieCombatQueue
local QuestieCombatQueue = QuestieLoader:ImportModule("QuestieCombatQueue")


function QuestieSlash.RegisterSlashCommands()
    Questie:RegisterChatCommand("questieclassic", QuestieSlash.HandleCommands)
    Questie:RegisterChatCommand("questie", QuestieSlash.HandleCommands)
end

function QuestieSlash.HandleCommands(input)
    input = string.trim(input, " ");

    local commands = {}
    for c in string.gmatch(input, "([^%s]+)") do
        table.insert(commands, c)
    end

    local mainCommand = commands[1]
    local subCommand = commands[2]

    -- /questie
    if mainCommand == "" or not mainCommand then
        QuestieCombatQueue:Queue(function()
            QuestieOptions:OpenConfigWindow();
        end)

        if QuestieJourney:IsShown() then
            QuestieJourney.ToggleJourneyWindow();
        end
        return ;
    end

    -- /questie help || /questie ?
    if mainCommand == "help" or mainCommand == "?" then
        print(Questie:Colorize(l10n("Questie Commands"), "yellow"));
        print(Questie:Colorize("/questie - " .. l10n("Toggles the Config window"), "yellow"));
        print(Questie:Colorize("/questie toggle - " .. l10n("Toggles showing questie on the map and minimap"), "yellow"));
        print(Questie:Colorize("/questie tomap [<npcId>/<npcName>/reset] - " .. l10n("Adds manual notes to the map for a given NPC ID or name. If the name is ambiguous multipe notes might be added. Without a second command the target will be added to the map. The 'reset' command removes all notes"), "yellow"));
        print(Questie:Colorize("/questie minimap - " .. l10n("Toggles the Minimap Button for Questie"), "yellow"));
        print(Questie:Colorize("/questie journey - " .. l10n("Toggles the My Journey window"), "yellow"));
        print(Questie:Colorize("/questie tracker [show/hide/reset/debug] - " .. l10n("Toggles the Tracker. Add 'show', 'hide', 'reset', 'debug' to explicit show/hide, reset, or debug the Tracker"), "yellow"));
        print(Questie:Colorize("/questie flex - " .. l10n("Flex the amount of quests you have completed so far"), "yellow"));
        print(Questie:Colorize("/questie doable [questID] - " .. l10n("Prints whether you are eligibile to do a quest"), "yellow"));
        print(Questie:Colorize("/questie version - " .. l10n("Prints Questie and client version info"), "yellow"));
        print(Questie:Colorize("/questie version check - " .. l10n("Compare EpogQuestie versions with all server users"), "yellow"));
        return;
    end

    -- /questie toggle
    if mainCommand == "toggle" then
        Questie.db.profile.enabled = (not Questie.db.profile.enabled)
        QuestieQuest:ToggleNotes(Questie.db.profile.enabled);

        -- Close config window if it's open to avoid desyncing the Checkbox
        QuestieOptions:HideFrame();
        return;
    end

    if mainCommand == "reload" then
        QuestieQuest:SmoothReset()
        return
    end

    -- /questie minimap
    if mainCommand == "minimap" then
        Questie.db.profile.minimap.hide = not Questie.db.profile.minimap.hide;

        if Questie.db.profile.minimap.hide then
            Questie.minimapConfigIcon:Hide("Questie");
        else
            Questie.minimapConfigIcon:Show("Questie");
        end
        return;
    end

    -- /questie journey (or /questie journal, because of a typo)
    if mainCommand == "journey" or mainCommand == "journal" then
        QuestieJourney.ToggleJourneyWindow();
        QuestieOptions:HideFrame();
        return;
    end

    if mainCommand == "tracker" then
        if subCommand == "show" then
            QuestieTracker:Enable()
        elseif subCommand == "hide" then
            QuestieTracker:Disable()
        elseif subCommand == "reset" then
            QuestieTracker:ResetLocation()
        elseif subCommand == "debug" then
            -- Debug command to diagnose tracker issues
            local debugOutput = {}
            table.insert(debugOutput, "=== QUESTIE TRACKER DEBUG INFO ===")
            table.insert(debugOutput, "Version: " .. GetAddOnMetadata("Questie", "Version"))
            table.insert(debugOutput, "Please copy ALL text below and share on GitHub")
            table.insert(debugOutput, "")
            
            -- Enable debug mode temporarily for this session
            Questie.db.profile.debugEnabled = true
            Questie.db.profile.debugEnabledPrint = true
            Questie.db.profile.debugLevel = 7
            table.insert(debugOutput, "Debug mode: ENABLED")
            table.insert(debugOutput, "")
            
            table.insert(debugOutput, "TRACKER STATUS:")
            table.insert(debugOutput, "  Started: " .. tostring(QuestieTracker.started or false))
            table.insert(debugOutput, "  Enabled: " .. tostring(Questie.db and Questie.db.profile and Questie.db.profile.trackerEnabled or false))
            
            if Questie.db and Questie.db.char then
                table.insert(debugOutput, "  TrackerHiddenQuests: " .. type(Questie.db.char.TrackerHiddenQuests))
                table.insert(debugOutput, "  TrackedQuests: " .. type(Questie.db.char.TrackedQuests))
                table.insert(debugOutput, "  AutoUntrackedQuests: " .. type(Questie.db.char.AutoUntrackedQuests))
            else
                table.insert(debugOutput, "  ERROR: Database char data not available!")
            end
            table.insert(debugOutput, "")
            
            -- Check frame visibility
            table.insert(debugOutput, "FRAME STATUS:")
            if Questie_BaseFrame then
                table.insert(debugOutput, "  Exists: Yes")
                table.insert(debugOutput, "  Visible: " .. tostring(Questie_BaseFrame:IsVisible()))
                table.insert(debugOutput, "  Shown: " .. tostring(Questie_BaseFrame:IsShown()))
                local point, relativeTo, relativePoint, x, y = Questie_BaseFrame:GetPoint()
                table.insert(debugOutput, string.format("  Position: %s (%.1f, %.1f)", tostring(point), x or 0, y or 0))
                table.insert(debugOutput, string.format("  Size: %.0fx%.0f", Questie_BaseFrame:GetWidth(), Questie_BaseFrame:GetHeight()))
                
                local screenWidth = GetScreenWidth()
                local screenHeight = GetScreenHeight()
                if x and y and (x > screenWidth or x < -screenWidth or y > screenHeight or y < -screenHeight) then
                    table.insert(debugOutput, "  WARNING: Frame appears OFF-SCREEN!")
                    table.insert(debugOutput, "  Try: /questie tracker reset")
                end
                
                -- Check alwaysShowTracker setting
                table.insert(debugOutput, "  AlwaysShowTracker: " .. tostring(Questie.db.profile.alwaysShowTracker or false))
            else
                table.insert(debugOutput, "  ERROR: Base frame does NOT exist!")
            end
            table.insert(debugOutput, "")
            
            -- Check for quest issues
            table.insert(debugOutput, "QUEST LOG CHECK:")
            local questCount = 0
            local failedQuests = {}
            for i = 1, GetNumQuestLogEntries() do
                local title, level, _, _, _, _, _, questId = GetQuestLogTitle(i)
                if questId and questId > 0 then
                    questCount = questCount + 1
                    local success, questData = pcall(function() return QuestieDB.GetQuest(questId) end)
                    if not success or not questData then
                        table.insert(failedQuests, string.format("  FAILED: Quest %d '%s'", questId, title or "Unknown"))
                    end
                end
            end
            table.insert(debugOutput, "  Total quests: " .. questCount)
            if #failedQuests > 0 then
                table.insert(debugOutput, "  Failed to load:")
                for _, msg in ipairs(failedQuests) do
                    table.insert(debugOutput, msg)
                end
            else
                table.insert(debugOutput, "  All quests loaded successfully")
            end
            table.insert(debugOutput, "")
            
            -- Check if tracker is hidden due to no quests
            if questCount == 0 and not Questie.db.profile.alwaysShowTracker then
                table.insert(debugOutput, "ISSUE FOUND: Tracker hidden because quest log is empty!")
                table.insert(debugOutput, "  Solution 1: Accept a quest to see the tracker")
                table.insert(debugOutput, "  Solution 2: Enable 'Always Show Tracker' in options")
                table.insert(debugOutput, "")
                table.insert(debugOutput, "ACTION: Temporarily enabling 'Always Show Tracker'...")
                Questie.db.profile.alwaysShowTracker = true
                
                -- Force update the tracker
                if QuestieTracker.started then
                    QuestieTracker:Update()
                end
            end
            
            -- Try to reinitialize if needed
            if not QuestieTracker.started then
                table.insert(debugOutput, "ACTION: Attempting to reinitialize tracker...")
                QuestieTracker.Initialize()
            end
            
            -- Create copyable window (based on export window code)
            local outputText = table.concat(debugOutput, "\n")
            
            -- Create frame if it doesn't exist
            if not QuestieDebugFrame then
                local f = CreateFrame("Frame", "QuestieDebugFrame", UIParent)
                f:SetFrameStrata("DIALOG")
                f:SetWidth(600)
                f:SetHeight(400)
                f:SetPoint("CENTER")
                f:SetMovable(true)
                f:EnableMouse(true)
                f:RegisterForDrag("LeftButton")
                f:SetScript("OnDragStart", f.StartMoving)
                f:SetScript("OnDragStop", f.StopMovingOrSizing)
                
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
                title:SetText("|cFF00FF00Questie Debug Output|r")
                
                -- Instructions
                local step1 = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                step1:SetPoint("TOP", title, "BOTTOM", 0, -8)
                step1:SetText("|cFFFFFFFFStep 1:|r Click 'Select All' button below")
                
                local step2 = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                step2:SetPoint("TOP", step1, "BOTTOM", 0, -4)
                step2:SetText("|cFFFFFFFFStep 2:|r Copy (Ctrl+C) and paste into GitHub issue #1")
                
                -- Scroll frame
                local scrollFrame = CreateFrame("ScrollFrame", "QuestieDebugScrollFrame", f, "UIPanelScrollFrameTemplate")
                scrollFrame:SetPoint("TOPLEFT", 20, -80)
                scrollFrame:SetPoint("BOTTOMRIGHT", -40, 60)
                
                -- Edit box
                local editBox = CreateFrame("EditBox", "QuestieDebugEditBox", scrollFrame)
                editBox:SetMultiLine(true)
                editBox:SetMaxLetters(99999)
                editBox:SetSize(540, 800)
                editBox:SetFont("Interface\\AddOns\\Questie\\Fonts\\VeraMono.ttf", 10)
                editBox:SetAutoFocus(false)
                editBox:SetScript("OnEscapePressed", function() f:Hide() end)
                editBox:SetScript("OnTextChanged", function(self, userInput)
                    if userInput then
                        self:SetText(outputText)
                        self:HighlightText()
                    end
                end)
                
                scrollFrame:SetScrollChild(editBox)
                f.editBox = editBox
                
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
                
                -- Help text
                local helpText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                helpText:SetPoint("BOTTOM", copyButton, "TOP", 60, 5)
                helpText:SetText("|cFFFFFF00Tip: If Ctrl+C doesn't work, unbind it in Key Bindings|r")
                
                -- Close button
                local closeButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
                closeButton:SetPoint("BOTTOMRIGHT", -40, 20)
                closeButton:SetWidth(100)
                closeButton:SetHeight(25)
                closeButton:SetText("Close")
                closeButton:SetScript("OnClick", function() f:Hide() end)
            end
            
            QuestieDebugFrame.editBox:SetText(outputText)
            QuestieDebugFrame.editBox:HighlightText(0, 0)
            QuestieDebugFrame:Show()
            
            Questie:Print("|cFF00FF00Debug window opened - Click 'Select All' then press Ctrl+C to copy|r")
        else
            QuestieTracker:Toggle()
        end
        return
    end

    if mainCommand == "tomap" then
        if not subCommand then
            subCommand = UnitName("target")
        end

        if subCommand ~= nil then
            if subCommand == "reset" then
                QuestieMap:ResetManualFrames()
                return
            end

            local conversionTry = tonumber(subCommand)
            if conversionTry then -- We've got an ID
                subCommand = conversionTry
                local result = QuestieSearch:Search(subCommand, "npc", "int")
                if result then
                    for npcId, _ in pairs(result) do
                        QuestieMap:ShowNPC(npcId)
                    end
                end
                return
            elseif type(subCommand) == "string" then
                local result = QuestieSearch:Search(subCommand, "npc")
                if result then
                    for npcId, _ in pairs(result) do
                        QuestieMap:ShowNPC(npcId)
                    end
                end
                return
            end
        end
    end

    if mainCommand == "flex" then
        local questCount = 0
        for _, _ in pairs(Questie.db.char.complete) do
            questCount = questCount + 1
        end
        if GetDailyQuestsCompleted then
            questCount = questCount - GetDailyQuestsCompleted() -- We don't care about daily quests
        end
        SendChatMessage(l10n("has completed a total of %d quests", questCount) .. "!", "EMOTE")
        return
    end

    if mainCommand == "version" then
        -- Simple version display
        local gameType = ""
        if Questie.IsWotlk then
            gameType = "Wrath"
        elseif Questie.IsSoD then -- seasonal checks must be made before non-seasonal for that client, since IsEra resolves true in SoD
            gameType = "SoD"
        elseif Questie.IsEra then
            gameType = "Era"
        end

        Questie:Print("Questie " .. QuestieLib:GetAddonVersionString() .. ", Client " .. GetBuildInfo() .. " " .. gameType .. ", Locale " .. GetLocale())
        print("|cFFFFFF00[Questie-Epoch]|r Check for updates at Github: https://github.com/trav346/Questie-Epoch")
        return
    end

    if mainCommand == "doable" or mainCommand == "eligible" or mainCommand == "eligibility" then
        if not subCommand then
            print(Questie:Colorize("[Questie] ", "yellow") .. "Usage: /questie " .. mainCommand .. " <questID>")
            do return end
        elseif QuestieDB.QueryQuestSingle(tonumber(subCommand), "name") == nil then
            print(Questie:Colorize("[Questie] ", "yellow") .. "Invalid quest ID")
            return
        end

        Questie:Print("[Eligibility] " .. tostring(QuestieDB.IsDoableVerbose(tonumber(subCommand), false, true, false)))

        return
    end

    print(Questie:Colorize("[Questie] ", "yellow") .. l10n("Invalid command. For a list of options please type: ") .. Questie:Colorize("/questie help", "yellow"));
end
