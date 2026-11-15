# GatheringGoldCalculator

A World of Warcraft: Forever addon that shows how much gold your gathering is worth, using [Auctionator](https://www.curseforge.com/wow/addons/auctionator) prices. If an item has no auction price, it uses the vendor sell price.

Works with **Mining, Herbalism, Skinning and Fishing**.

## Features

- **Floating text:** every time you gather, the loot's value floats up under your character, like `+ 7s 00c`. The g, s and c are gold, silver and copper colored.
- **Gathering Profit box:** a small text-only window that shows your last loot, your last mining node (all its taps added up), the session total and gold per hour. It fades out after 1 minute without gathering. Drag it wherever you like.
- **Sessions:** a session starts with your first gather and ends after 10 minutes without gathering anything. All four professions count toward the same session.
- **History window** (open it with the minimap button):
  - **Lifetime:** your lifetime total and every session, showing date, length, gathers and gold.
  - **Resources:** pick a profession from the dropdown to see every item you've gathered with it. The three sortable columns are Resource (sorted by tier), Count and Value. It opens on the profession you gathered with last.
- **Per character:** each character has their own history. Window positions and sorting are shared across your account.

## Commands

| Command | What it does |
| --- | --- |
| `/ggc` | Open or close the history window (`/mgc` also works) |
| `/ggc box` | Show or hide the Gathering Profit box |
| `/ggc test 70000` | Play a test floating text (value in copper, not saved) |
| `/ggc end` | End the current session now |
| `/ggc claim` | Add history saved before per-character tracking to this character |

## Install

Copy the `GatheringGoldCalculator` folder into `World of Warcraft\_forever_\Interface\AddOns\` and restart the game. Auctionator is optional but recommended. Without it, items are valued at vendor price.
