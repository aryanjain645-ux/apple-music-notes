# SongNotes

A macOS menu bar app (Swift, SwiftPM, no Xcode) for jotting notes on whatever is playing in Apple Music. Notes go to Supabase; Gemini (or Claude, if only an Anthropic key is set) turns each note into tags; the tags are mirrored into the song's Comments in Music.

- Build + install: `scripts/build-app.sh` (installs to `~/Applications/SongNotes.app`)
- Config (keys): `~/.config/songnotes/config.json`. Never commit keys; this repo is public.
- Secrets live in the macOS Keychain under account `songnotes`, e.g. `security find-generic-password -a songnotes -s "SongNotes Supabase DB password" -w`
- Database shell: `scripts/db.sh` (psql through the IPv4 pooler, using the password from the Keychain)
- Schema: `supabase/migrations/001_init.sql` (apply with `scripts/db.sh -f …`)

## Building a playlist when asked ("make me a sunset set…")

1. Query the database with `scripts/db.sh -c "…"`. Use the `track_profile` view, which has one row per song:
   `persistent_id, title, artist, album, duration_s, bpm, genre, in_library, vibes text[], tags text[], energy int (1–5), set_role, all_notes, note_count, last_noted_at`
   - Labels in use: `select * from tag_counts;`
   - Example: `select * from track_profile where 'sunset' = any(vibes) or 'sunset' = any(tags) order by energy;`
   - `all_notes` holds the raw notes. Read them for nuance that the tags miss.
2. Choose and order the songs. For DJ sets, shape the energy (warmup → build → peak → cooldown/closer), use `set_role` and `bpm` when available, and respect a target length using `duration_s`. Skip rows where `in_library` is false, or warn about them.
3. Create the playlist in that order:
   `scripts/make-playlist.sh "Sunset set · 2026-11-22" <persistent_id> <persistent_id> ...`
4. Report the tracklist (title — artist, energy) and anything that was skipped.

Don't modify or delete notes unless asked.
