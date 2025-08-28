# API Improvements TODO List

## Overview
This document tracks opportunities to replace custom code with native WoW 3.3.5a APIs in the Questie codebase. Each item is categorized by impact level and includes specific implementation details.

## Important Note
**WoW Version**: 3.3.5a (Interface 30300)
**Limitation**: Many modern C_* APIs don't exist in 3.3.5a. We need to verify API availability before implementing changes.

---

## HIGH IMPACT IMPROVEMENTS

### 1. Quest Watch System Overhaul
**Files**: 
- `Modules/Tracker/QuestieTracker.lua` (lines 2168-2189)
- `Modules/Tracker/TrackerUtils.lua`

**Current Issue**:
- Completely overrides native `IsQuestWatched` function
- Maintains custom tracking tables (`TrackedQuests`, `AutoUntrackedQuests`)
- Bypasses Blizzard's quest watch system entirely

**Proposed Solution**:
- [ ] Investigate if we can work WITH the native watch system instead of replacing it
- [ ] Use native `AddQuestWatch(questIndex)` and `RemoveQuestWatch(questIndex)`
- [ ] Hook into native functions instead of overriding them
- [ ] Maintain compatibility with auto-tracking feature

**Benefits**:
- Reduce memory overhead from custom tables
- Better integration with default UI
- Reduce potential for bugs
- Cleaner codebase

**Risks**:
- May lose some custom functionality
- Need to ensure backward compatibility

---

### 2. Quest Objective Parsing Without Taint
**Files**:
- `Modules/Quest/QuestieQuest.lua` (lines 253-279)
- `Modules/Quest/QuestieQuestPrivates.lua`
- `Modules/QuestieDataCollector.lua`

**Current Issue**:
- Uses `SelectQuestLogEntry(index)` which can cause taint
- Requires manual quest selection to get objectives
- Iterates through objectives with `GetQuestLogLeaderBoard(i)`

**Proposed Solution**:
- [ ] Check if `GetQuestLogLeaderBoard` works without `SelectQuestLogEntry` in 3.3.5a
- [ ] Create wrapper function that preserves current selection
- [ ] Cache objective data to reduce API calls
- [ ] Investigate if we can get objectives directly by questID

**Benefits**:
- Eliminate taint issues
- Faster objective retrieval
- More reliable quest data

---

## MEDIUM IMPACT IMPROVEMENTS

### 3. Optimize Quest Log Iteration
**Files**:
- `Modules/QuestieDataCollector.lua` (multiple locations)
- `Modules/Tracker/QuestieTracker.lua`
- `Modules/QuestieSlash.lua`
- `Modules/Quest/QuestieQuest.lua`

**Current Issue**:
- Iterates through all quests with `for i = 1, GetNumQuestLogEntries()`
- Calls `GetQuestLogTitle(i)` for every quest every time
- No caching of quest log data

**Proposed Solution**:
- [ ] Implement quest log caching system
- [ ] Only update cache on QUEST_LOG_UPDATE event
- [ ] Use batch operations where possible
- [ ] Create helper functions for common patterns

**Code Locations to Update**:
- [ ] `QuestieDataCollector:InitializeFromQuestLog()` - Full quest log scan
- [ ] `QuestieTracker:Update()` - Quest tracking updates
- [ ] `QuestieSlash:HandleTrackCommand()` - Manual tracking commands
- [ ] `QuestieQuest:GetAllQuestIDs()` - Quest ID collection

**Benefits**:
- Significant performance improvement with large quest logs
- Reduced API call overhead
- Better responsiveness

---

### 4. Timer System Modernization
**Files**:
- `Modules/Tracker/TrackerQuestTimers.lua` (lines 48-57)
- `Modules/Tracker/TrackerFadeTicker.lua`
- `Modules/TaskQueue.lua`

**Current Issue**:
- Manual elapsed time tracking in OnUpdate
- Constant OnUpdate overhead even when not needed
- Multiple different timer implementations

**Proposed Solution**:
- [ ] Check if C_Timer exists in 3.3.5a (likely doesn't)
- [ ] Create centralized timer management system
- [ ] Use frame pooling for timer frames
- [ ] Implement smart OnUpdate that disables when not needed

**Implementation Plan**:
```lua
-- Proposed centralized timer system
QuestieTimer = {
    timers = {},
    frame = CreateFrame("Frame"),
    elapsed = 0
}

function QuestieTimer:Schedule(seconds, callback)
    -- Add to timer list
    -- Enable OnUpdate if needed
end

function QuestieTimer:Cancel(timerId)
    -- Remove from timer list
    -- Disable OnUpdate if no timers
end
```

**Benefits**:
- Better performance
- Cleaner code organization
- Easier to debug timer issues

---

## LOW IMPACT IMPROVEMENTS

### 5. TaskQueue Optimization
**Files**:
- `Modules/TaskQueue.lua` (lines 6-18)

**Current Issue**:
- Runs OnUpdate constantly even with empty queue
- Processes only one task per frame

**Proposed Solution**:
- [ ] Disable OnUpdate when queue is empty
- [ ] Process multiple lightweight tasks per frame
- [ ] Add task prioritization
- [ ] Implement task batching

**Benefits**:
- Minor performance improvement
- Better task scheduling

---

### 6. Gossip/Quest NPC Detection
**Files**:
- `Modules/QuestieDataCollector.lua`
- `Modules/Auto/QuestieAuto.lua`

**Current Issue**:
- Custom event handling for NPC interactions
- May miss some quest availability detection

**Proposed Solution**:
- [ ] Better utilize `GetGossipActiveQuests()` and `GetGossipAvailableQuests()`
- [ ] Use `GetNumGossipActiveQuests()` and `GetNumGossipAvailableQuests()`
- [ ] Implement proper gossip option handling

**Benefits**:
- More reliable quest detection
- Better auto-accept/turn-in functionality

---

## ADDITIONAL IMPROVEMENTS TO INVESTIGATE

### 7. Quest Completion State
- [ ] Verify proper use of `IsQuestCompletable()`
- [ ] Check if `GetQuestLogCompletionText()` provides useful data
- [ ] Investigate `IsCurrentQuestFailed()` for better failure handling

### 8. Quest Item Management
- [ ] Use `GetQuestItemLink(type, index)` for better item tracking
- [ olved use `GetNumQuestItems()` for validation
- [ ] Implement `GetQuestItemInfo(type, index)` for detailed item data

### 9. Daily Quest Handling
- [ ] Implement `GetDailyQuestsCompleted()` tracking
- [ ] Use `IsQuestDaily(questID)` for daily quest detection
- [ ] Add `GetQuestResetTime()` for reset notifications

### 10. Party Quest Sharing
- [ ] Investigate `IsUnitOnQuest(questIndex, unit)` for party tracking
- [ ] Implement `QuestLogPushQuest()` for quest sharing features

---

## IMPLEMENTATION PRIORITY

1. **Phase 1 - Research** (No code changes)
   - [ ] Document which APIs are actually available in 3.3.5a
   - [ ] Test API behavior in-game
   - [ ] Identify any undocumented limitations

2. **Phase 2 - High Impact** (Major improvements)
   - [ ] Quest objective parsing without taint
   - [ ] Quest watch system integration

3. **Phase 3 - Performance** (Speed improvements)
   - [ ] Quest log iteration optimization
   - [ ] Timer system improvements

4. **Phase 4 - Polish** (Minor improvements)
   - [ ] TaskQueue optimization
   - [ ] Additional API utilization

---

## TESTING REQUIREMENTS

For each change:
- [ ] Test with empty quest log
- [ ] Test with full quest log (25 quests)
- [ ] Test with mix of regular and daily quests
- [ ] Test auto-tracking functionality
- [ ] Test manual tracking/untracking
- [ ] Test with quest objectives of all types
- [ ] Test memory usage before/after
- [ ] Test performance with `/run collectgarbage("collect")`

---

## NOTES

- Remember that C_Timer and other modern APIs don't exist in 3.3.5a
- Some APIs may behave differently than documented
- Always maintain backward compatibility
- Keep the custom Epoch quest handling intact
- Test thoroughly with Project Epoch specific quests

---

## Code Review Checklist

Before implementing any change:
- [ ] Verify API exists in 3.3.5a
- [ ] Check for taint issues
- [ ] Ensure Epoch compatibility
- [ ] Document behavior differences
- [ ] Add error handling
- [ ] Update relevant comments
- [ ] Test edge cases

---

*Last Updated: [Current Date]*
*Version: 1.0.33*
*Target WoW Version: 3.3.5a (30300)*