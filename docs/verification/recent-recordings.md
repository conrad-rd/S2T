# Recent recordings

The settings sidebar opens a newest-first list of complete dictation transcripts. Each row has its recording date, the application name and installed app icon when known, and a Copy action. No transcript text appears in the menu. Recent recordings offers Previous recording and Two recordings ago, followed by Show all transcripts.

History stores only text, date, UUID and optional application name/bundle identifier in `~/Library/Application Support/S2T/recent-transcripts.json`. Atomic writes use owner-only file permissions. Retries update the same recording. Invalid archives are left intact and the page reports the load failure. Preview state has no history file. Existing failed-recording recovery and Meetings storage remain separate.

Run `bash scripts/test.sh`, `bash scripts/build-app.sh`, then the packaged executable with `--verify-recent-recordings`, `--verify-settings-sidebar`, `--verify-menu-highlights` and `--verify-build`. The recent-recordings probe uses temporary files, a named isolated pasteboard and hidden settings views. It covers restart persistence, complete Unicode text, empty input, retries, corrupt-file preservation, exact menu copy targets and page navigation. It never records audio or captures screen pixels. Real dictation and visual appearance are not established by these checks.
