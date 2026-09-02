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

- A **Read Quest button** toggle, for players whose quest UI already occupies
  that spot.
- `/sstoggle`, matching the `ss` short form every other command already had.

### Fixed

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
