# honeypot-lockdown

A decoy `~/passwords.txt` for macOS. No legitimate process has a reason to open it. When one tries, the access is denied, the network is blocked and an alert is shown. Aimed at credential stealers and agents that read through the home directory.

## How it works

1. [Santa](https://northpole.security/santa), a signed Endpoint Security system extension, watches the decoy through a file-access rule. It denies `open`, `clone`, `copyfile`, `exchangedata`, `link`, `rename`, `truncate` and `unlink` by any process outside the rule's allowed list, and writes one line to `/var/db/santa/santa.log`.
2. A root LaunchDaemon (`honeypot watch`) follows that log.
3. In `armed` mode, a logged violation loads a pf ruleset (`block drop quick all`, loopback skipped), flushes existing connections and shows an alert naming the process. The block stays, across reboots, until `unlock`.

Santa runs in Monitor mode with no binary rules: it does not stop any program from running.

Measured on this machine: Santa's daemon uses about 0.2% of one core, the watcher none. The network block follows the denied access by 2 to 3 s (Santa writes its log in batches).

## Requirements

- macOS 13 or later, an admin account, Homebrew.
- No MDM is needed. The Santa configuration is a profile installed by hand.

## Install

1. Install Santa. The cask is community-maintained; the package it installs is North Pole Security's.

```bash
brew install --cask santa
```

2. Approve Santa in System Settings:
   - General > Login Items & Extensions > Endpoint Security Extensions: turn on Santa.
   - Privacy & Security > Full Disk Access: turn on Santa.

3. Install the watcher, the policy and the decoy.

```bash
sudo ./santa/install.sh
```

4. Hand the configuration profile to System Settings, then approve it under General > Device Management > "Honeypot: Santa configuration" > Install.

```bash
open santa/honeypot.mobileconfig
```

5. Check. Within a minute `santa:` must show `Enabled | Yes` and `Rule Count | 1`, and `watcher:` must show `running`.

```bash
/usr/local/libexec/honeypot/honeypot status
```

Optional shell alias for the one command needed in a hurry:

```zsh
alias honeypot-unlock="sudo /usr/local/libexec/honeypot/honeypot unlock"
```

## Use

The command is `/usr/local/libexec/honeypot/honeypot`. Call it by full path: `/usr/local/bin` is writable by the user account on this machine, so a symlink there could be replaced by a process running as that user. Everything except `status` and `log` needs sudo.

| Command | Effect |
|---|---|
| `status` | Mode, lock state, watcher, Santa watch items |
| `observe` | Log violations only. Santa still denies the access |
| `arm` | Violations also block the network and show the alert |
| `unlock` | Restore the network: reload `/etc/pf.conf`, release the pf reference, clear the lock |
| `allow <signing-id> [team-id]` | Let a process touch the decoy. Without a team ID the entry applies to Apple platform binaries only. Santa applies it within 60 s |
| `nolock <exe-path>` | Santa still denies the process, and the hit is logged, but the network is not blocked. Matches on executable path only: use it for SIP-protected system paths |
| `log [n]` | Last n lines of `/var/log/honeypot.log` |

### First days: observe

The install starts in `observe` mode. Use the machine normally, then look for processes that were denied for ordinary reasons (indexers, backup tools, antivirus):

```bash
/usr/local/libexec/honeypot/honeypot log 200
```

Allow the ones that belong there. The signing ID of a binary is the `Identifier` line of `codesign -dv <path>`.

```bash
sudo /usr/local/libexec/honeypot/honeypot allow com.apple.example
```

### Arm

```bash
sudo /usr/local/libexec/honeypot/honeypot arm
```

### When it trips

- The process gets `Operation not permitted`. The decoy content is not disclosed.
- An alert appears: "Honeypot tripped: network blocked", with the executable path and pid.
- All network traffic except loopback is dropped.
- `/var/log/honeypot.log` holds the Santa event and the process ancestry. Read it before unlocking: the ancestry shows which application started the process.

Restore the network when the cause is understood:

```bash
sudo /usr/local/libexec/honeypot/honeypot unlock
```

### Test

```bash
cat ~/passwords.txt
```

Expected: `Operation not permitted` and, a few seconds later, a `hit OPEN decision=DENIED ... exe=/bin/cat` line in the log. In `armed` mode the alert appears and `curl -m 3 https://example.com` fails until `unlock`.

## Limits

- `stat`, `ls` and globbing do not trigger. Only access to the content or a second name for the file does.
- A process on the allowed list can be used as a proxy. Keep the list short; do not add shells or QuickLook.
- A file dialog that lists the home directory makes `com.apple.appkit.xpc.openAndSavePanelService` open the decoy for a preview. Add it with `nolock`. The service acts for whichever application opened the dialog, so a hit from it is still logged.
- Finder opens the decoy to draw a preview (icon preview, preview pane, Gallery view, search results) and retries the denied open about every 10 s while the file is on screen. Add `/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder` with `nolock`. Do not `allow` Finder: it accepts AppleScript commands from other processes and would then read the decoy for them.
- Third-party backup or sync tools that scan the home directory are denied and trip the lockdown. Exclude the file in the tool, or `allow` the tool. Time Machine is excluded by `install.sh`.
- Santa does not follow symlinks in watched paths and cannot guarantee coverage of hard links that existed before the rule. It denies creating new ones.
- pf does not stop AirDrop or Bluetooth. A VPN client that reloads pf rules replaces the block.
- Anything running as root can stop the watcher or unload the pf rules.

## Uninstall

```bash
sudo ./santa/uninstall.sh
```

This stops the watcher, lifts an active lockdown, and moves the installed files, the log and `~/passwords.txt` to `.trash/` here. Then remove the profile under System Settings > General > Device Management, and Santa if it is no longer wanted:

```bash
brew uninstall --cask santa
```

## Layout

| Path | Purpose |
|---|---|
| `santa/honeypot` | Watcher daemon and control command, installed to `/usr/local/libexec/honeypot/` |
| `santa/install.sh`, `santa/uninstall.sh` | Run with sudo |
| `santa/honeypot.mobileconfig` | Santa configuration profile |
| `santa/com.euklides.honeypot.plist` | LaunchDaemon for the watcher |
| `lockdown.pf.conf` | The pf ruleset loaded on lockdown |
| `passwords.decoy.txt` | Decoy content, all invented |

Installed state lives in `/usr/local/etc/honeypot/` (policy `faa.plist`, config), `/var/db/honeypot/` (mode, lock state) and `/var/log/honeypot.log`, all root-owned.
