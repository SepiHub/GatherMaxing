# GatherMaxing

A World of Warcraft: Forever addon that shows how much gold your gathering is worth, using [Auctionator](https://www.curseforge.com/wow/addons/auctionator) or [TradeSkillMaster](https://www.curseforge.com/wow/addons/tradeskill-master) prices. By default Auctionator is checked first, then TSM (market value, then recent, then min buyout); you can pick a different price source from the minimap right-click menu. If there's no auction price, it uses the vendor sell price.

Works with **Mining, Herbalism, Skinning and Fishing**.

## Features

- **Floating text:** every time you gather, the loot's value floats up under your character. The g, s and c are gold, silver and copper colored. There are two modes:
  - **Individual** (default): one line per item with its count, icon and value, like `2x[Iron Ore]5s 10c` then `3x[Heavy Stone]3s 91c`, appearing 0.2 seconds apart.
  - **Combined:** one line with the value of everything you looted, like `+ 7s 00c`.
- **Gathering Profit box:** a small text-only window that shows your last loot, your last mining node (all its taps added up), the session total and gold per hour. It fades out after 1 minute without gathering. Drag it wherever you like.
- **Node tooltips:** mouse over a mining node, herb or skinnable corpse to see the skill it needs, like `Requires Mining 125`. The line is colored like a recipe: red if you can't gather it yet, then orange, yellow, green and gray as skill-ups get rarer. Once you've gathered that kind of node, the tooltip also shows its average value at today's prices, like `~12s 40c per node (8 gathered)`.
- **Unlock messages:** when a skill-up lets you gather something new, a chat message tells you, like `GatherMaxing: Mining 155 - you can now mine Gold Vein!`, `you can now harvest Fadeleaf` or `you can now skin corpses up to level 30`. This covers nodes, herbs and corpse levels for skinning, not smelting.
- **Sessions:** a session starts with your first gather and ends after 10 minutes without gathering anything. All four professions count toward the same session.
- **Main window** (left-click the minimap button): three buttons along the bottom switch between **Lifetime**, **Resources** and **Skill Book**. It opens on the Skill Book the first time, then on whichever tab you closed it on.
  - **Lifetime:** your lifetime total and every session, showing date, length, gathers and gold. Click a session to see everything you gathered in it, with each item's count, total value and the price per item at the time, so you can see how prices change over time.
  - **Resources:** pick a profession from the dropdown to see every item you've gathered with it. The three sortable columns are Resource (sorted by tier), Count and Value. It opens on the profession you gathered with last.
  - **Skill Book:** lists everything a gathering profession unlocks, by skill level: training ranks (and the character level they need), every mining node and herb, smelting recipes, and which corpse levels you can skin. Each skill number is colored for your current skill, a gold "You are here" line marks where you are, and the top shows what you unlock next. Pick the profession from the dropdown; hover a row for details. Click **Trainers** to see where to train instead: trainers for your faction (plus neutral ones), grouped by the highest rank they teach, closest to you first, with a rough distance in meters. Capital cities are shown in gold (and come first if the game can't tell distances). On Forever, every gathering trainer outside the starting areas teaches all ranks up to Artisan; Fishing gets Expert from a book and Artisan from a quest. Click a trainer to open the world map with a pin (a gold circle with an X) on them; click the pin (or the trainer again) to remove it. Trainer locations come from Warcraft Tavern's WoW Forever trainer guide.
- **Price history:** click any resource (in the Skill Book, the Resources tab or a session's details) to open a window with its price over time: a line graph (hover it for each day's price) for the last 7 days, 30 days or all time, plus the change, average, lowest and highest price, this week's change, vendor price, how much you've gathered and, with TSM, TSM's market, historical and region values. GatherMaxing saves one auction price per resource each day you play (at login, every 15 minutes and after you close the auction house); older days come from the prices your sessions were valued at. TSM tracks prices better than Auctionator, since its prices update through the TSM app without scanning the auction house.
- **Minimap right-click menu:**
  - **Toggle session tracker:** hides or shows the Gathering Profit box. While it's off, sessions, history and the floating text still work as normal in the background.
  - **Combined mode:** checked for combined floating text, unchecked for individual lines.

  The menu stays open when you click a toggle, so you can change several at once.
  - **Edit floating text position:** shows a box that plays sample text. Drag the box to move the floating text (it snaps to the middle of the screen, shown by a line that turns gold), and drag its bottom-right corner to make the text bigger or smaller. Right-click the box to reset it. Click the checkmark in its corner (or untick the option) to finish.
  - **Price source:** where prices come from. **Auto** (the default) uses Auctionator, then TSM. You can also pick Auctionator only, a TSM source (Market Value, Min Buyout, Recent Value, Historical Price, Region Market Value Avg, Region Historical Price, Region Sale Avg), **Custom price source** to type any TSM price string (like `0.5 * DBRegionMarketAvg`), or vendor price only. Sources whose addon isn't loaded are grayed out. Items with no price from the picked source use the vendor price. Saved history keeps the prices it had; tooltips, the Skill Book and new gathers use the new source.
  - **Start new session:** ends the current session (saving it to history) and starts a fresh one.
- **Per character:** each character has their own history. Window positions and sorting are shared across your account.

## Commands

| Command | What it does |
| --- | --- |
| `/gmax` | Open or close the main window, on the tab you last used (the older `/ggc` and `/mgc` also work) |
| `/gmax book` | Open or close the Skill Book |
| `/gmax edit` | Turn floating text edit mode on or off (move and resize it) |
| `/gmax box` | Show or hide the Gathering Profit box once (works even with the tracker off) |
| `/gmax test 70000` | Play a test floating text in the current mode (value in copper, not saved) |
| `/gmax end` | End the current session now |
| `/gmax new` | End the current session and start a new one |
| `/gmax tracker` | Turn the session tracker (Gathering Profit box) on or off |
| `/gmax claim` | Add history saved before per-character tracking to this character |

## Install

Copy the `GatherMaxing` folder into `World of Warcraft\_forever_\Interface\AddOns\` and restart the game. Auctionator or TSM is optional but recommended. Without either, or before you've scanned the auction house with one, items are valued at vendor price. In that case a red note in the Gathering Profit box and in chat when you log in reminds you to install one and run a scan.

## License

[MIT](LICENSE)
