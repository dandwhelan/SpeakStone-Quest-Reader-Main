# Changelog

## 1.3

First public release.

### Added

- **Per-expansion sound packs.** Audio no longer ships inside the base addon.
  The base addon is code only; voice audio installs alongside it as separate
  pack addons (starting with *SpeakStone Narration - Midnight Voices*), so you
  download only the expansions you care about. Packs self-register with the
  base addon and merge into its lookup, in any load order.
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
