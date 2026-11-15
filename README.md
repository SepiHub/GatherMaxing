# GatherMaxing

A World of Warcraft: Forever addon that shows how much gold your gathering is worth, using [Auctionator](https://www.curseforge.com/wow/addons/auctionator) prices. If an item has no auction price, it uses the vendor sell price.

Works with **Mining, Herbalism, Skinning and Fishing**.

## Features

- **Floating text:** every time you gather, the loot's value floats up under your character. The g, s and c are gold, silver and copper colored. There are two modes:
  - **Individual** (default): one line per item with its count, icon and value, like `2x[Iron Ore]5s 10c` then `3x[Heavy Stone]3s 91c`, appearing 0.2 seconds apart.
  - **Combined:** one line with the value of everything you looted, like `+ 7s 00c`.
- **Gathering Profit box:** a small text-only window that shows your last loot, your last mining node (all its taps added up), the session total and gold per hour. It fades out after 1 minute without gathering. Drag it wherever you like.
- **Sessions:** a session starts with your first gather and ends after 10 minutes without gathering anything. All four professions count toward the same session.
- **History window** (open it with the minimap button):
  - **Lifetime:** your lifetime total and every session, showing date, length, gathers and gold. Click a session to see everything you gathered in it, with each item's count, total value and the price per item at the time, so you can see how prices change over time.
  - **Resources:** pick a profession from the dropdown to see every item you've gathered with it. The three sortable columns are Resource (sorted by tier), Count and Value. It opens on the profession you gathered with last.
- **Minimap right-click menu:**
  - **Toggle session tracker:** hides or shows the Gathering Profit box. While it's off, sessions, history and the floating text still work as normal in the background.
  - **Combined mode:** checked for combined floating text, unchecked for individual lines.

  The menu stays open when you click a toggle, so you can change several at once.
  - **Edit floating text position:** shows a box that plays sample text. Drag the box to move the floating text (it snaps to the middle of the screen, shown by a line that turns gold), and drag its bottom-right corner to make the text bigger or smaller. Right-click the box to reset it. Click the checkmark in its corner (or untick the option) to finish.
  - **Start new session:** ends the current session (saving it to history) and starts a fresh one.
- **Per character:** each character has their own history. Window positions and sorting are shared across your account.

## Commands

| Command | What it does |
| --- | --- |
| `/gmax` | Open or close the history window (the older `/ggc` and `/mgc` also work) |
| `/gmax edit` | Turn floating text edit mode on or off (move and resize it) |
| `/gmax box` | Show or hide the Gathering Profit box once (works even with the tracker off) |
| `/gmax test 70000` | Play a test floating text in the current mode (value in copper, not saved) |
| `/gmax end` | End the current session now |
| `/gmax new` | End the current session and start a new one |
| `/gmax tracker` | Turn the session tracker (Gathering Profit box) on or off |
| `/gmax claim` | Add history saved before per-character tracking to this character |

## Install

Copy the `GatherMaxing` folder into `World of Warcraft\_forever_\Interface\AddOns\` and restart the game. Auctionator is optional but recommended. Without it, or before you've run an Auctionator scan at the auction house, items are valued at vendor price. In that case a red note in the Gathering Profit box and in chat when you log in reminds you to install Auctionator and run a scan.

## License

[MIT](LICENSE)
