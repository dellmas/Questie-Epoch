# Questie for Project Epoch

Questie addon optimized for Project Epoch (3.3.5a) with 600+ custom quests.

## Installation

1. Click the green **`< > Code`** button at the top of this page
2. Select **Download ZIP**
3. Extract the downloaded ZIP file
4. Move the `Questie-Epoch-master` folder to your WoW AddOns folder:
   - Default location: `C:\Program Files\Ascension Launcher\resources\epoch_live\Interface\Addons`
5. **Important:** Rename the folder from `Questie-Epoch-master` to just `Questie`

## Features
- Epoch quest database with 600+ custom quests (IDs 26000+)
- Automatic runtime stubs for missing quests - tracker works even without full data
- Developer mode for community quest data collection
- Real-time capture of NPCs, items, and objective locations

## Quest Prefixes in Tracker
- **[Epoch]** - Project Epoch custom quests (ID 26000+) not yet in database
- **[Missing]** - Vanilla/TBC/WotLK quests (ID < 26000) missing from database
- **No prefix** - Fully implemented quests with complete data

## Developer Mode
Automatically captures quest data while you play. Quests showing prefixes need data collection. Credit to @desizt and @esurm for this system.

### Commands
- `/qdc enable/disable` - Toggle data collection
- `/qdc export` - Export ALL captured data for submission
- `/qdc export <questId>` - Export specific quest
- `/qdc show` - View tracked quests
- `/qdc clear` - Clear all data

### Contributing Quest Data
1. Enable dev mode: `/qdc enable`
2. Accept and complete quests with [Epoch] or [Missing] prefixes
3. You'll see a raid warning sound when capturing new quest data
4. Export data: `/qdc export <questId>` or `/qdc export` for all
5. Submit to: https://github.com/trav346/Questie-Epoch/issues

### Additional Commands
- `/epochvalidate` - Run database integrity check
- `/questie` - Open configuration menu

## Support
Report issues or submit quest data on GitHub.

## Credits
Based on original Questie with enhancements for Project Epoch.
Contributors: @Bennylavaa, @desizt, @esurm

## License
GNU General Public License v3.0
