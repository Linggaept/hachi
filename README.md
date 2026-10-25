# Hachi

**English** · [Bahasa Indonesia](README.id.md)

A to-do app that lives in your macOS menu bar. Press <kbd>⌥ Space</kbd> from any app, type or say what you need to do in everyday language, and Hachi turns it into a task with the right date, time, and reminder.

No AI, no account, no server. Everything stays on your Mac.

Named after Hachiko, the dog who waited at the station at the same time every day.

> [!NOTE]
> **Indonesian first.** Hachi currently understands sentences in Indonesian, and the app itself is in Indonesian. An English interface and an English sentence parser are being worked on.

## Why Hachi

- **Fast to capture.** One shortcut opens a small Spotlight-style box. Type, press <kbd>↩</kbd>, done. Hold the shortcut to dictate instead.
- **Understands plain sentences.** `besok jam 3 sore call client ingetin 30 menit sebelumnya` ("tomorrow at 3 pm call client, remind me 30 minutes before") becomes *Call client · tomorrow 15.00 · reminder 14.30*. A live preview shows what was understood before you save.
- **Reminders that arrive on time,** even when the panel is closed or the Mac just woke up. Act on them right from the notification: Done, Snooze 10 min, Snooze 1 hour, Tomorrow.
- **Repeating tasks** like "every Monday" or "every 1st of the month" reschedule themselves when you complete them.
- **Morning summary** once a day, and a gentle check on undated tasks you haven't touched for 14 days.
- **Native and dependency-free.** Swift and SwiftUI, with macOS's built-in SQLite and speech recognition.

## Install

Requires macOS 26 or later on Apple silicon.

1. Download `Hachi-<version>.zip` from the [Releases page](https://github.com/Linggaept/hachi/releases/latest), unzip it, and move **Hachi** to your Applications folder.
2. Open Hachi. Because it isn't notarized by Apple, macOS blocks it the first time. Click **Done**, go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the message about Hachi.

   Or in Terminal: `xattr -dr com.apple.quarantine /Applications/Hachi.app`

3. Allow notifications when asked. The first time you use voice, allow the microphone; the Indonesian speech model downloads once, then works offline.

Hachi starts automatically at login. You can turn this off in Settings. Hachi has to be in the Applications folder for this to work.

## Using Hachi

| Action | How |
|---|---|
| Add a task | <kbd>⌥ Space</kbd>, type, <kbd>↩</kbd> |
| Dictate | Hold <kbd>⌥ Space</kbd>, speak, release, check, <kbd>↩</kbd> |
| Set details by hand | <kbd>⌘ ↩</kbd> in the capture box opens a form for date, time, reminder, and repeat |
| Cancel | <kbd>esc</kbd> |
| See your list | Click the Shiba icon in the menu bar. The number next to it is how many tasks are overdue. |

The shortcut can be changed in Settings.

### Example sentences

| You write | Hachi understands |
|---|---|
| `besok jam 3 sore call client ingetin 30 menit sebelumnya` | Tomorrow 15.00, reminder at 14.30 |
| `nanti malam telpon ibu` | Today 20.00 |
| `30 menit lagi angkat jemuran` | 30 minutes from now |
| `lusa jam sembilan pagi bayar internet` | The day after tomorrow, 09.00 |
| `jam setengah lima jemput adik` | 16.30 |
| `jumat depan deadline proposal` | Friday next week, all day |
| `tgl 25 bayar listrik` | The 25th, all day |
| `tiap senin jam 9 cek backup` | Every Monday 09.00 |
| `tiap hari kerja jam 8 pagi absen` | Monday to Friday 08.00 |
| `beli kopi` | No date |

How ambiguous times are read:

- `jam 1`–`jam 6` without a part of day means afternoon (`jam 3` = 15.00). `jam 7`–`jam 11` means morning, unless that time has already passed today, then it means evening.
- `pagi` 08.00, `siang` 12.00, `sore` 16.00, `malam` 20.00. These can be changed in Settings.
- `jumat depan` is Friday of next week (weeks start on Monday). `jumat` alone is the nearest Friday.
- All-day tasks don't ring on their own; they show up in the morning summary. Add `ingetin` ("remind me") if you want a reminder anyway.

## Privacy

Hachi has no server, no account, and no analytics. Tasks and settings are stored only on your Mac, in `~/Library/Application Support/Hachi/`. Speech is recognized on-device. If on-device recognition fails, Hachi falls back to Apple's server-based speech recognition, which sends that recording to Apple.

## Build from source

No Xcode needed, only the Command Line Tools.

```sh
swift test               # run the parser tests
./scripts/install.sh     # build, install to /Applications, and relaunch
./scripts/build-app.sh   # only assemble build/Hachi.app
./scripts/release.sh     # build and zip build/Hachi-<version>.zip
```

The app is signed ad hoc, so macOS may ask for notification and microphone permission again after a rebuild.

## Contributing

Issues and pull requests are welcome. The sentence parser lives in the `TodoParser` target and can be tested without running the app. Every new sentence pattern should come with tests in `Tests/TodoParserTests`.

## License

[MIT](LICENSE)
