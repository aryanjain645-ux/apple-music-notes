# SongNotes

Press **⌃⌥N** (or click the ♫ icon in the menu bar) while a song plays in Apple Music, type or speak what you think ("perfect sunset tune, slow build"), and press Enter.

- The note is saved to Supabase immediately. If you're offline it waits in `~/.config/songnotes/queue.json` and syncs later.
- Gemini (free tier; or Claude if you prefer) turns it into tags: vibes (`sunset`), energy (1–5), set role (`opener`…`closer`) and free tags (`slow-build`).
- The tags also go into the song's **Comments** in Music as `[sn] #sunset #e2 #slow-build [/sn]`, so Smart Playlists like *Comments contains #sunset* work there and sync to your iPhone.
- **Menu → Make playlist → sunset** creates a real Apple Music playlist from every song with that tag.
- Or ask Claude Code in this folder, e.g. "build a 90-minute sunset set that ends at energy 4" (see `CLAUDE.md`).

Voice: click the mic in the note box (on-device transcription). Wispr Flow also works, since it types into the focused box.

## Setup
1. Create a Supabase project and run `supabase/migrations/001_init.sql` in its SQL Editor (or `scripts/db.sh -f supabase/migrations/001_init.sql`).
2. `scripts/build-app.sh`, then `open ~/Applications/SongNotes.app`
3. In the Settings window, paste the project URL, the **secret** key (Project Settings → API Keys) and a Gemini API key (aistudio.google.com), or an Anthropic key instead.
4. Approve the macOS prompts: control Music, microphone, speech recognition.

Optional: System Settings → General → Login Items → add SongNotes.

Note: each rebuild changes the ad-hoc signature, so macOS may ask for permissions again.

If Google's free model is busy (HTTP 503), notes stay "pending" and get tagged automatically on the next sync, every 5 minutes or when you click **Sync now**.
