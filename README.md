 💡 Known Issues

  - Some Epoch quests still have placeholder data - please use /qdc enable to help collect data
  - Map icons may not appear for quests with incomplete NPC/object data
  - I've discovered Project Epoch has modified numerous existing vanilla quests with, for example, making them cross faction when originally the were faction exlusive. This is causing major conflicts for the original Questie database from vanilla->wrath, so some quests may behave oddly, but the quest data collection system should still capture relevant info and warn you if you've accepted a quest not in the database.
  
v1.0.53
New feature!

 -Auto Waypoint has been added thanks to @fing3rguns. To enable, /questie -> Tracker -> tick box for Auto Waypoint in Tom Tom section. (must have Tom Tom installed and enabled)

  🎉 Major Improvements

  Quest Tracker Reliability

  - Fixed critical tracker crashes when encountering missing Epoch quest data
  - Implemented runtime quest stubbing - tracker now works even for quests not in the database
  - Fixed "attempt to compare number with table" errors that prevented tracker from loading
  - Resolved tracker showing only 5 of 25 quests - fixed AutoUntrackedQuests filtering logic
  - Added /questie tracker clear command to reset untracked quest list

  Database Improvements

  - Added 200+ missing Project Epoch quests with proper data
  - Fixed quest stubbing mechanism to include all 30 required fields (was only 18)
  - Added automatic database corruption detection and recovery
  - Fixed nil comparison errors when quests have missing sourceItemId values

  Community Data Collection System

  - Added exploration objective tracking for area/event type quests
  - Fixed mob data not appearing in quest exports
  - Fixed data purge button to properly clear SavedVariables
  - Added quest giver capture for incomplete data detection
  - Improved coordinate tracking for all objective types

  📊 Quest Data Updates

  New Quests Added

  - Call to Skirmish: Ashenvale (26364)
  - Call to Skirmish: Hillsbrad Foothills (26366)
  - A Lost Warrior quest chain (26795, 26796)
  - WANTED: Archmage Zygor (26824)
  - Scarlet Intelligence (26941)
  - Northshore Mine (26937) - corrected with Dark Ooze mobs
  - Plus 195+ other Epoch quests

  Fixed Quests

  - Northshore Mine (26937): Now correctly shows Dark Ooze (45895) as target instead of wrong mob
  - A Box of Relics (26926): Properly configured as exploration + item collection quest
  - Removed placeholder "[Epoch]" prefixes from properly implemented quests

  NPC Corrections

  - Fixed Jasper Greene NPC ID (45885, not 45886)
  - Added Tog'thar in Hillsbrad Foothills
  - Added Dark Ooze with proper spawn locations
  - Corrected 50+ other NPC entries

  🛠️ Technical Fixes

  Memory and Performance

  - Fixed memory leaks in quest tracking
  - Improved database validation performance
  - Reduced tracker update frequency for better FPS

  Error Handling

  - Added defensive nil checks throughout codebase
  - Improved error messages for debugging
  - Added diagnostic commands for troubleshooting

  📝 Documentation

  - Added installation instructions with clear steps
  - Updated README with current features
  - Removed outdated version information

  🔧 Developer Tools

  New Commands

  - /questie tracker clear - Reset auto-untracked quests
  - /epochvalidate - Validate database integrity
  - /qdc export <questId> - Export specific quest data
  - /qdc show - View all tracked quest data

  Data Collection Improvements

  - Exploration objectives now tracked with exact trigger coordinates
  - Mob kill locations properly exported
  - Item drop sources linked to specific mobs
  - Object interactions captured with coordinates

  🐛 Bug Fixes

  - Fixed tracker not showing when no quests in log
  - Fixed map pin displacement when using zoom addons (Magnify compatibility)
  - Fixed quest stubbing failures for runtime-generated quests
  - Fixed SavedVariables corruption on reload
  - Fixed quest prefixes showing incorrectly ([Epoch] vs [Missing])
  - Fixed tracker initialization errors with corrupted saved data


  🙏 Contributors

  Special thanks to:
  - @Bennylavaa for testing and bug reports
  - @desizt and @esurm for the original data collection system
  - All players submitting quest data through GitHub

  ---
  To Update: Download from GitHub, extract to your AddOns folder, and rename from Questie-Epoch-master to Questie
