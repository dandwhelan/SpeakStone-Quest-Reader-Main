# Changelog

## Unreleased

### Changed

- **The addon is now called SpeakStone**, not SpeakStone Narration. The folder,
  saved variables and the function voice packs call to register themselves keep
  their old names, so existing installs, settings and packs carry over
  untouched.
- **Blizzard's own voice lines now take priority.** Where the game has voiced a
  line, that recording plays and SpeakStone waits its turn; it speaks over the
  silence where there is none. Previously the game's Dialog channel was muted by
  default. The old behaviour is still one checkbox away, and the pause before
  SpeakStone speaks is now a slider rather than a hardcoded two seconds. Only
  the default changed -- if you have played before, your existing setting is
  kept as it is.
- **One export instead of two.** The separate "quests with no audio" export is
  gone. Most such quests turn out to have been removed from the game, and that
  payload left out gossip and book text -- the two kinds that exist in no
  shipped file and on no scrapeable site, so capture is the only way they are
  ever obtained. `/ssharvest export` now always carries quests, greetings and
  books together, and `/qrmissing` runs the same thing.
- **Settings now open in their own window.** `/ss`, the minimap button and the
  AddOns list all lead to a movable panel that closes with Escape, with status
  cards down the left -- voice packs installed, text captured, whether capture
  is running -- and the options beside them. The state that matters most, "no
  voice pack is installed at all", now reads at a glance in red instead of
  sitting in a paragraph below the options.
- **The settings panel is grouped and explained.** Playback, Interface and
  Contribute, with a tooltip on every option, and a status block showing which
  voice packs are installed and what capture has collected -- previously there
  was no way to tell "this quest has no audio" apart from "no voice pack is
  installed at all".

### Added

- **A reminder to send in captured text.** Once a few hundred entries have
  built up, SpeakStone says so at login and the Captured card turns green with
  a prompt to export -- at most once every three days, and never before there
  is a real amount waiting. Capture only helps once it reaches the website, and
  nothing ever said so unprompted.
- A **Read Quest button** toggle, for players whose quest UI already occupies
  that spot.
- `/sstoggle`, matching the `ss` short form every other command already had.

### Added

- **Autoplay is now three switches, not one.** Quests, NPC greetings, and
  books/letters/plaques each have their own checkbox under "Read
  automatically", so you can have tomes read aloud without narration starting
  at every NPC you pass. The master switch still governs all of them, and the
  three are on by default -- existing installs behave exactly as before.

### Performance

- **Login is cheaper.** The settings window and the audio library window are
  now built the first time you open them, not on every login -- together they
  were around a hundred frames assembled for windows many players never open.
  Filling the settings dashboard also meant walking every clip in every
  installed voice pack, which happened at login whether or not the panel was
  ever shown; that count is now worked out on demand and cached until a pack
  registers.
- **Searching the audio library no longer stutters.** Typing re-filtered the
  whole library on every keystroke, and filtering by name means resolving a
  title for every voiced quest -- tens of thousands of them with a full pack
  set. Titles are now remembered once looked up, and a burst of typing costs
  one pass instead of one per character.
- The addon stopped listening for other addons loading once it has nothing
  left to wait for, rather than waking for every on-demand addon all session.
- **The audio library only listens while it is open.** It waits on quest data
  coming back from the server to fill in names it does not know yet, and that
  answer arrives for every quest anything in your UI asks about. It was
  listening from login, all session, for a window most players open rarely and
  many never do.

### Fixed

- **Blizzard's dialogue could be left silent.** With "silence Blizzard's own
  voice lines" on and "stop narration when the window closes" off, the Dialog
  channel was muted when narration started and nothing ever unmuted it: there
  is no notification when a clip finishes, so the addon believed it was still
  playing for the rest of the session. Narration now knows how long its own
  clip runs and releases the channel when it ends. That volume is also saved
  to disk while muted, so a crash or disconnect mid-line no longer leaves you
  with silent dialogue and nothing to point at -- it is restored on the next
  login.
- Eleven functions and variables the addon kept in the shared global namespace
  -- among them names as generic as `IsPlaying`, `GetCurrentSound` and
  `lastTextType` -- are now private to it. Any other addon defining one of
  those would have silently broken playback, or been broken by it.
- **A stopped clip could still start speaking.** The delay before narration
  used a timer that could not be cancelled, so walking away during the pause
  left the queued line to play anyway. Same fault, same fix, for the short
  delay before a book's first page.
- **The Dialog channel could stay muted.** Turning "Silence Blizzard's own
  voice lines" off while a clip was playing meant the volume was never put
  back, and the game stayed silent for the rest of the session.
- **A line could be spoken twice, over itself.** Narration waits a moment
  before speaking so Blizzard's own voice line can finish, and a clip still
  waiting out that pause did not count as playing -- so clicking on to the
  next page of dialogue left the old timer running. It then spoke whichever
  line had replaced it, which spoke again on its own timer: the same voice
  twice, a fraction of a second apart, with no way to stop the first.
- **A clip with no recorded length left the Dialog channel muted.** Nothing
  tells an addon when a sound has finished, so narration works from the length
  its voice pack records. Where that was missing the clip was never considered
  finished, and with "Silence Blizzard's own voice lines" on the game's
  dialogue stayed silent for the rest of the session -- the same dead end the
  length was introduced to avoid, reached by another road.
- **Previewing a clip in the audio library talked over the quest being
  narrated**, and where narration had silenced Blizzard's voice lines the
  preview played into that silenced channel and could not be heard at all.
  Previewing now stops whatever is being narrated first.
- **The SpeakStone icon in the AddOns list.** Its texture path was missing the
  `Interface\AddOns` prefix, so nothing was drawn.
- **The Capture card went blank** rather than reporting its state when the
  counts were unavailable.
- **Exports could be unparseable.** The serialiser escaped quotes in values
  but not in table keys, and books and plaques are keyed by their in-game name
  when they carry no item ID. One name containing a quote broke the whole
  payload at the far end.
- **A fresh install could show every option switched off.** The settings panel
  and the addon's own setup both run on ADDON_LOADED with no order between
  them; arriving first, the panel read defaults that had not been applied yet.
- Clearing captured data no longer prints "cleared" twice.
- The audio library rebuilds its index when a voice pack registers after the
  window has been opened, instead of showing the pack only after a reload.
- Clicking **Read Quest** with no quest panel open threw a Lua error instead of
  doing nothing.
- Hiding the minimap button did not survive a relog.
- The export window ignored Escape unless its text box had focus, took keyboard
  focus when it opened (so a stray keypress could replace the export before it
  was copied), and described a full export as "Missing Quest Audio".

## 1.3

First public release.

### Added

- **Per-expansion sound packs.** Audio no longer ships inside the base addon.
  The base addon is code only; voice audio installs alongside it as separate
  pack addons (starting with *SpeakStone Narration - Midnight Voices*), so you
  download only the expansions you care about. Packs self-register with the
  base addon and merge into its lookup, in any load order.
- **Text capture is built in.** What used to be a separate companion addon
  (SpeakStone Harvester) is now part of the main addon and **on by default**.
  It records quest, gossip and book text as you encounter it, so the gaps in
  the voiced library can be filled. Turn it off any time with the
  *Capture quest text* setting, or `/ssharvest off`.
  `/ssharvest` shows what you've collected and exports it; `/qrmissing`
  exports just the quests that had no audio. Your character's name is
  scrubbed to `$n` before anything is stored.
  Anything captured by the old standalone addon is imported automatically.
- **Missing-quest capture.** When no installed pack has audio for a quest
  passage, the addon now records that quest's text, speaker and title locally.
  `/qrmissing` exports what it has collected, ready to paste at
  speakstone.beanw.co.uk so the quest can be voiced. Your character's name is
  substituted back out to `$n` before anything is stored.

### Changed

- `/qrmissing` now exports full quest text rather than listing sound filenames.
- Debug chat output is off by default; `/qrdebug` toggles it.

### Notes

- English (enUS) only for now.
- Gossip playback works, but very little gossip audio has been generated yet.
