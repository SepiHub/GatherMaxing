# GatheringGoldCalculator

A World of Warcraft: Forever addon that shows how much gold your gathering is worth, using [Auctionator](https://www.curseforge.com/wow/addons/auctionator) prices. If an item has no auction price, it uses the vendor sell price.

Works with **Mining, Herbalism, Skinning and Fishing**.

## Features

- **Floating text:** every time you gather, the loot's value floats up under your character. The g, s and c are gold, silver and copper colored. There are two modes:
  - **Combined** (default): one line with the value of everything you looted, like `+ 7s 00c`.
  - **Individual:** one line per item with its count, icon and value, like `+ 2 [Iron Ore] 5s 10c` then `+ 3 [Heavy Stone] 3s 91c`, appearing 0.1 seconds apart.
- **Gathering Profit box:** a small text-only window that shows your last loot, your last mining node (all its taps added up), the session total and gold per hour. It fades out after 1 minute without gathering. Drag it wherever you like.
- **Sessions:** a session starts with your first gather and ends after 10 minutes without gathering anything. All four professions count toward the same session.
- **History window** (open it with the minimap button):
  - **Lifetime:** your lifetime total and every session, showing date, length, gathers and gold.
  - **Resources:** pick a profession from the dropdown to see every item you've gathered with it. The three sortable columns are Resource (sorted by tier), Count and Value. It opens on the profession you gathered with last.
- **Minimap right-click menu:**
  - **Toggle session tracker:** hides or shows the Gathering Profit box. While it's off, sessions, history and the floating text still work as normal in the background.
  - **Combined mode:** checked for combined floating text, unchecked for individual lines.
  - **Start new session:** ends the current session (saving it to history) and starts a fresh one.
- **Per character:** each character has their own history. Window positions and sorting are shared across your account.

## Commands

| Command | What it does |
| --- | --- |
| `/ggc` | Open or close the history window (`/mgc` also works) |
| `/ggc box` | Show or hide the Gathering Profit box once (works even with the tracker off) |
| `/ggc test 70000` | Play a test floating text in the current mode (value in copper, not saved) |
| `/ggc end` | End the current session now |
| `/ggc new` | End the current session and start a new one |
| `/ggc tracker` | Turn the session tracker (Gathering Profit box) on or off |
| `/ggc claim` | Add history saved before per-character tracking to this character |

## Install

Copy the `GatheringGoldCalculator` folder into `World of Warcraft\_forever_\Interface\AddOns\` and restart the game. Auctionator is optional but recommended. Without it, items are valued at vendor price.
