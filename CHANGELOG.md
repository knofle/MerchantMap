# Merchant Map

## Unreleased

- Removed the MM button on the world map, along with its option to show every vendor. Search still pins the vendors you're looking for.
- "Show hidden vendors" is now a checkbox in the options (under Map). With it on, vendors you hid show in grey and alt-click brings them back.

- Items locked to another class (like Warlock grimoires) are no longer marked "Not in stock at last visit" when your class can't see them in the shop. Older marks like that are cleared on your next visit.
- A vendor's full stock window now has a separator line above the items that weren't in stock at the last visit.
- The list for overlapping map pins now says "Shift-click: full stock", which is what shift-click does.
- Fixed a possible Lua error when hovering "Nearest vendor for" before every item name had loaded.
- Lighter after login: the world map no longer redraws its pins while items are being sorted into categories.
- Opening a shop does a little less work.
- The direction arrow no longer sticks to the mouse after dragging it with other buttons held or quick mouse moves.
