# Questie for Epoch

Fork optimized for Project Epoch (3.3.5a) with 600+ custom quests.

## Features
- Epoch quest database (IDs 26000-26999) - many still need validation
- Developer mode for community data collection
- Real-time capture of NPCs, items, and objective locations

**Known Issue**: Map zoom causes marker displacement (3.3.5a client limitation)

## Developer Mode
Automatically captures quest data while you play. Quests needing validation show "[Epoch]" prefix.

### Commands
- `/qdc enable/disable` - Toggle data collection
- `/qdc export` - Export ALL captured data for submission
- `/qdc export <questId>` - Export specific quest
- `/qdc show` - View tracked quests
- `/qdc clear` - Clear all data

### Contributing
1. Enable dev mode: `/qdc enable`
2. Complete Epoch quests normally
3. Export data: `/qdc export`
4. Submit to: https://github.com/trav346/Questie-for-Epoch/issues

## Support
Report issues or submit quest data on GitHub.

## Credits
Based on original Questie with enhancements for Project Epoch. 
Contributors: @Bennylavaa, @desizt, @esurm

## License
GNU General Public License v3.0