# Questie for Epoch

Questie addon optimized for Project Epoch (3.3.5a) with 600+ custom quests.

## Features
- Epoch quest database (IDs 26000-26999) - many still need validation
- NEW: Developer mode for community quest data collection
- NEW: Real-time capture of NPCs, items, and objective locations with devmode enabled.

**Known Issue**: Map zoom causes marker displacement (3.3.5a client limitation). Still researching a fix.

## Developer Mode
Automatically captures quest data while you play. Quests needing validation show "[Epoch]" prefix. Credit to @desizt and @esurm for this clever addition.

### Commands
- `/qdc enable/disable` - Toggle data collection
- `/qdc export` - Export ALL captured data for submission
- `/qdc export <questId>` - Export specific quest
- `/qdc show` - View tracked quests
- `/qdc clear` - Clear all data

### Contributing
1. Enable dev mode: `/qdc enable`
2. Complete Epoch quests normally
3. A raid warning sound and a chatlog print will occur when you've accepted a quest not in the Epoch database, if dev mode is enabled.
4. Export data: `/qdc export`
5. Submit to: https://github.com/trav346/Questie-Epoch/issues NOTE: you must have a github account to submit issues.

## Support
Report issues or submit quest data on GitHub.

## Credits
Based on original Questie with enhancements for Project Epoch. 
Contributors: @Bennylavaa, @desizt, @esurm

## License
GNU General Public License v3.0
