# Changelog

## 1.3.2
- 🎃 The Lanterns of Light really work now. When the final fight began, the lanterns lost the hidden tag that tells them apart, so the game took all four for the same lantern: the first one caught without its 1/4, the other three did nothing, and Blair's shield never fell. Each lantern now knows which one it is, turns into a bonfire, and counts toward the four.
- 🎁 Pre-renewal: the Halloween Spooky Pack from Jakk's shop did nothing when opened (the Pre-renewal item has no contents). It now gives the same draw as on Renewal: Battle Manuals, Life Insurance, Enriched Oridecon, Kafra Cards, Megaphones, Old Purple Boxes, Immortal Stew, a Bloody Branch, or, rarely, a Succubus or Incubus Card or an Evolved Pipe or Pair of Red Ribbon.

## 1.3.1
Fixes from your feedback:
- 🕯️ The Lanterns of Light no longer stop working after the first one. Their 2-second bar could end a hair early on the client, and the server counted that as cancelled, so the lantern never caught. Each lantern now runs its own bar, timed by the server, and holds you still while it burns; hits and freezes can't interrupt it.
- 👻 Every Lost Child still out is marked on your minimap (orange) until someone finds them, so you don't have to click a navigation link in the middle of a fight.
- 🏦 Jakk keeps a coin bank for your account. A stack of Halloween Coins stops at 30,000, so the Sealed Card Album II (150,000) could never be bought. Now the coins you carry go into the bank when you shop, the shop spends from the bank, and you can take coins out again whenever you like.

## 1.3.0
Trick or treat: new things to fight, find and light on every night.
- Jack-o'-Champions: 2 pumpkin-crowned champions of each horde monster lead every horde (large, 6x the HP). Each counts for 10 kills and pays everyone on the map 10 Halloween Coins.
- The Lost Children: 6 little ghosts, 2 in each horde (at 30% and 70%). Casper points everyone to each one with a navigation link; any member can send them home within 4 minutes. Each one found sweetens the party (Blessing and Increase Agility, Lv 10, 3 minutes) and pays everyone 10 coins; all six add a Halloween Box and 50 coins to everyone's hoard, and Casper has something to say.
- Candy bowls: 8 bowls on doorsteps around town, placed anew every night. One knock each: a treat (candy for the party, 15 coins), a big treat (40 coins for everyone, a full heal), or a trick (a Jack-o'-Champion jumps out, or the pumpkin explodes: 40% HP and a short stun).
- The Lanterns of Light: Blair's true form is immune while her shadows shield her. Clicking each of the 4 jack-o'-lanterns around the portal and standing still 2 seconds lights it; the 4th burns the shield away for 60 seconds, then the shadows snuff them out again.
- Every night gets a grade from its time and falls (S, A, B, C), shown at Blair's hoard, with a bonus for S (a Halloween Box and 100 coins), A (50 coins) and B (20 coins).
- The fastest night under each moon (and your own) on Casper's board in Niflheim; a new record is announced to the whole server.

## 1.2.1
- Halloween Town is now open source under the GNU General Public License v3.0 (LICENSE, in the mod folder). The portraits and the minimap are not covered.
- The mod's README is the full guide (the story, the moons, the rewards) instead of the old 1.1.0 notes.
- From this release on, the zip is built by GitHub from the repository. Nothing in the game changes.

## 1.2.0
- Halloween Exchanger: new prizes, the October Spooky Crate (17317) and the October Spooky Box (17307), 50 Halloween Coins each.
- Halloween Tickets (7941): Blair's final form gives every member of the run 333 (Blue Moon), 456 (Blood Moon) or 666 (Eclipse). The Halloween Exchanger trades them for Cash Points, 3 tickets for 1 CP.
- Pre-renewal: Halloween Coins work. The coin (6658) only exists on Renewal servers, so on Pre-renewal the hordes and bosses dropped none and the Halloween Exchanger's shop didn't load. The mod now adds the coin on Pre-renewal servers (`pre-renewal/db/item_db.yml`).

## 1.1.0
- Eclipse, Horde 3: Polluted Earth Spirit (22209, Lv 264) is replaced by Lude Gal (20939, Lv 213), the evolved pumpkin-headed ghost of Niflheim. Same counts (700 spawned, 666 to slay).
- Safe zone: while monsters roam the town (the hordes and the road to the old hill), none may stay within 10 cells of the sky portal (261,158), where players arrive and come back after dying. They are moved elsewhere in town, not killed, so kill counts and coins are unaffected. Off during the final fight.

## 1.0.0
- First release.
