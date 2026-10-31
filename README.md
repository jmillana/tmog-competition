# TmogCompetition

Run transmog competitions in a party or raid. Every participant needs the addon installed.

## How it works
1. Form a group. Everyone with the addon shows up as a participant (players without it are listed under "Missing addon").
2. The **group leader** clicks **Shuffle & Start**. A random participant who hasn't showcased yet goes on stage, and voting opens for everyone else.
3. Players vote 1-10. The window shows how many votes are still pending and who hasn't voted yet. Scores stay hidden until the round closes. You can change your vote until then.
4. The leader clicks **Close Voting**. The average score is revealed and added to the ranking.
5. Repeat until everyone has showcased, then click **Announce Winner** (highest average; ties break on vote count).

Nobody showcases twice until the leader clicks **Reset Pool**. **Reset All** clears scores too.

The ranking and winner are **per theme**. When the draw picks a new theme, the ranking, winner and shuffle pool start
fresh so everyone showcases again. Earlier themes stay in the gallery. The leader can't spin while voting is open, and is
asked to confirm before spinning away from a theme whose winner was never announced.

The ranking has a tab per category (theme) plus **Overall**. When every theme is done, the leader clicks
**Finish Competition**: the overall ranking (sum of each player's theme scores) is announced with the top 3 and shown to
everyone. The next Shuffle & Start or spin begins a new competition. Turn on **Restart the round counter for each new
competition** in settings (on by default) to count rounds from 1 again. Reset All always restarts the counter.

Only the group leader can shuffle, start/close rounds, announce the winner and reset. Other clients ignore those messages from anyone else.

## Language and settings
The addon is available in English and Spanish. By default it follows the game client (`esES`/`esMX` → Spanish, anything
else → English). Click the gear icon at the top right of the main window (or `/tmogc settings`) to pick Automatic,
English or Español. The change applies instantly, no reload needed. The settings window also has the chat
announcement and auto-open options. Translations live in `Locale.lua`, where the English text is the key.

## Commands
`/tmogc` opens or closes the window. Also: `/tmogc next | close | winner | resetpool | resetall | sync | announce | autoshow`.

- `announce`: turn chat/raid-warning announcements on or off (leader).
- `autoshow`: turn opening the window automatically when a round starts on or off.
- `sync`: re-announce yourself and ask the leader for the current state.

## Notes
- State is saved (`TmogCompetitionDB`), so a `/reload` mid-competition is safe. Players who reload or join late get the current state from the leader automatically. Late joiners can vote from the next round.
- Run competitions out of combat and outside instanced content. Midnight restricts addon messages there.
- Votes travel as addon messages on the group channel. The addon UI hides scores until a round closes, but they are not encrypted.

## Protocol (prefix `TMOGC`, tab-separated)
| Message | From | Meaning |
|---|---|---|
| `HELLO ver wantReply` | anyone | has the addon; `wantReply=1` asks others to reply and the leader to sync |
| `PING` | leader | everyone re-sends HELLO |
| `ROUND id name` | leader | new round |
| `VOTE id score` | voter | a vote |
| `CLOSE id name avg count total` | leader | official round result |
| `WINNER names avg` | leader | winner(s) |
| `RESETPOOL` / `RESETALL` | leader | resets (Reset All also restarts the round counter) |
| `FINISH names score` / `NEWCOMP restartRounds` | leader | finish (overall winner) / start a new competition |
| `TRCOUNT n` + list `TR` | leader | sync of finished themes (`@theme`, then results) |
| `STATE round phase contestant winners avg` | leader | sync header |
| `L tag id more items` | leader | chunked list (`VOTERS`, `VOTED`, `SHOWN`, `RES`) |
| `OUTFIT race sex more items` | contestant | their outfit (`slot:appearance:secondary:illusion`, chunked) |
| `THEMEADD name` / `THEMEDEL name` | leader | add / remove a theme |
| `THEMESPIN` | leader | everyone's draw opens and starts spinning |
| `THEMERESULT name jitter` | leader | picked theme; every reel slows down and stops on it (jitter is unused) |
| `THEMERESET` | leader | put used themes back in the pool |
| `THEMECUR name` + lists `TPOOL`, `TUSED` | leader | theme sync for late joiners / reloads |

## Theme draw
Open it with the **Themes** button or `/tmogc themes`. Only the raid leader can add or remove themes and spin.
The draw is shown as a vertical reel: the selected theme sits in the highlighted middle row, with one theme above and one
below. With a single theme left, all three rows show it.

1. The leader adds themes (type a name and press Enter or **Add**, or `/tmogc addtheme <name>`).
2. The leader clicks **Spin** (or `/tmogc spin`). Every player's draw opens and starts spinning.
3. About 2 seconds later the leader's addon picks a random theme and sends it to everyone. Every reel slows down and stops with it in the middle,
   and the leader's client announces it in raid chat.
4. The picked theme leaves the pool and becomes the current theme (shown in the main window's title bar).
   **Reset used** puts picked themes back in the draw. Reset All does not touch themes.

## Outfit gallery
When a player goes on stage, their client reads its own outfit (hidden `DressUpModel` → `GetItemTransmogInfoList()`)
and broadcasts the appearance IDs. If they change gear or transmog while on stage, it is re-sent. Every client saves
the outfits, and players who showcased re-send theirs when someone joins late.

Open it with the **Gallery** button or `/tmogc gallery`. It opens automatically for everyone when the winner is announced.
The gallery is saved per player (not synced), so everyone keeps their own history.

- **Top tabs:** **Bookmarks**, then one tab per competition (newest first, the running one marked LIVE). A competition is
  titled with its date and starts with the first round after a Reset All. Right-click a tab to rename or remove it, or click its trash icon to delete it (bookmarks are kept).
- **Sub-tabs:** one per theme picked in that competition. Rounds are filed under the theme that was current.
  Click a theme tab's trash icon to delete that theme's transmogs (with confirmation; bookmarks are kept).
- **Cells:** outfit model (drag to rotate), rank, score and votes, 8 per page.
- **Right-click a transmog:** Bookmark / Remove bookmark, Explore, Remove from gallery.
- **Explore:** lists every piece (icon, slot, item, collected or not). Hover for the item tooltip, Shift-click to link it,
  **Try on** opens the outfit in the dressing room.
- **Clear all** (competition tabs): deletes your saved competitions. Bookmarks are kept.
- **Clear bookmarks** (Bookmarks tab): deletes your bookmarks only.

How each outfit is drawn:
1. Contestant in range: their own body, wearing the outfit they showcased.
2. Out of range: the outfit on their race/sex if the client supports custom race on models.
3. Otherwise: the outfit on your character, labelled "Shown on your character".

During voting the main window shows the contestant live when they're in range, and their shared outfit otherwise.
`/tmogc outfit` re-captures and re-sends your own outfit if something went wrong.
