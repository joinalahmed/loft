# Research notes: what Notchy does (Nov 2026)

Gathered from notchy.dev, its help centre and changelog, as the brief for this build.

- One developer (Vishva Variya), closed source, SwiftUI, macOS 13+, universal. $24.99
  one-time with a 7-day trial since v2.0.0 (Oct 26 2026); ~222 releases in six months via
  Sparkle; 134 languages; claims ~0.9 % of one core under load.
- Collapsed pill: Now Playing with artwork + spectrum, system HUDs, call/message islands,
  battery, timers, download progress, agent (Claude Code / Codex) approvals, caps lock,
  keystroke HUD, multiple live activities, Lottie idle animations.
- Panel: Home cards, Now Playing with synced lyrics (LRCLIB), clipboard with smart actions,
  file shelf with AirDrop, Pomodoro, calendar/reminders, notes, stocks, weather, system
  stats, terminal (VT100), command palette ⌃⌥K / ⌘1-9, launcher wheel ⌃⌥L.
- Platform tricks: per-app volume via CoreAudio process taps (14.4+), DDC for external
  monitors via IOAVService, Face Unlock with Apple Vision + Keychain-stored password typed
  through Accessibility, window snapping, menu bar icon hiding, lock-screen widgets,
  notification mirroring (Full Disk Access), knock detection via accelerometer.
- Developer surface: local API on 127.0.0.1:9999, newline JSON with a per-install token;
  `notchy://show?title=&message=` URL scheme; zsh preexec hook; Claude Code hooks.
- Defaults: hover opens the panel; ⌥Space hides; ⌃⌥N opens; accessibility is the only
  mandatory permission; everything else prompts when the feature is enabled.

Loft implements the core of that list. Not implemented (by choice, for an overnight build):
lyrics, per-app volume, DDC, Face Unlock, window snapping, notification mirroring,
terminal, stocks, Sparkle updates, localisation.

