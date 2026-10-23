# Merchant Map

## 1.1.7

- Clicking an item now shows where it lives: its categories glow faintly blue in the tree (or the folded category they're in, or Uncategorized).

- Adding an item to a category (drag and drop) or removing it (right-click) now says in chat where the item is now, with a clickable [Undo].
- Items you drop on a category, or that land somewhere after a remove, are marked in soft blue until you've seen them there, and that category glows blue in the tree (also on a folded parent) until then.
- New reset options, with buttons on the options page: /mm reset categories puts the categories back to the defaults and sorts every item again, /mm reset all wipes all saved data and settings.

## 1.1.6

- Pinned vendors just across a zone border now show on the map of the zone you're looking at, wherever they fall inside it.

- Updated to Questie's latest data (QuestieDB 1.0.6): 4 more vendors, 130 more trainers and other service NPCs, and 15 more mailboxes.
- Brought back seven NPCs that had gone missing from search: the transmogrifier Mon'ye, the battlemasters Borook Gallfist and Gruga Bloodblade, and the demon trainers Hraug, Kitha, Gina Lang and Kurgul.

## 1.1.5

- Map pins now stay on the world map during combat instead of disappearing until it ends.

- Fixed "AddOn 'MerchantMap' tried to call the protected function" errors when opening the world map in combat. Clicking an item or NPC no longer opens or moves the world map (that's what caused them), so the "Open the map" option is gone. The vendor still gets the minimap marker, arrow, target marker and optional waypoint, and their pins show when you open the map.

- Removed the MM button on the world map, along with its option to show every vendor. Search still pins the vendors you're looking for.
- "Show hidden vendors" is now a checkbox in the options (under Map). With it on, vendors you hid show in grey and alt-click brings them back.

- Items locked to another class (like Warlock grimoires) are no longer marked "Not in stock at last visit" when your class can't see them in the shop. Older marks like that are cleared on your next visit.
- A vendor's full stock window now has a separator line above the items that weren't in stock at the last visit.
- The list for overlapping map pins now says "Shift-click: full stock", which is what shift-click does.
- Fixed a possible Lua error when hovering "Nearest vendor for" before every item name had loaded.
- Lighter after login: the world map no longer redraws its pins while items are being sorted into categories.
- Opening a shop does a little less work.
- The direction arrow no longer sticks to the mouse after dragging it with other buttons held or quick mouse moves.
