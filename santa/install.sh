#!/bin/zsh
# Installs the honeypot watcher and the Santa file-access policy. Run with
# sudo from the account to protect. Santa itself and the configuration
# profile are installed separately; see README.md.
# Safe to run again: it keeps the mode, the lock state, an edited policy and
# an existing ~/passwords.txt.

set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin

(( EUID == 0 )) || { print -u2 "run with sudo"; exit 1 }
user=${SUDO_USER:?run with sudo from your own account, not as root}
home=$(dscl . -read /Users/$user NFSHomeDirectory | awk '{ print $2 }')
src=${0:A:h}

LABEL=com.euklides.honeypot
# The watcher runs as root and Santa reads the policy as root. Everything
# is installed root-owned under root-owned directories, so the unprivileged
# user (and malware running as that user) cannot change it.
LIB=/usr/local/libexec/honeypot
ETC=/usr/local/etc/honeypot
VAR=/var/db/honeypot
plist=/Library/LaunchDaemons/$LABEL.plist
decoy=$home/passwords.txt

install -d -o root -g wheel -m 755 $LIB $ETC $VAR
install -o root -g wheel -m 755 $src/honeypot $LIB/honeypot
install -o root -g wheel -m 644 $src/../lockdown.pf.conf $ETC/lockdown.pf.conf
print -r -- "HONEYFILE=${(q)decoy}" > $ETC/honeypot.conf
[[ -e $VAR/mode ]] || print observe > $VAR/mode
[[ -e $VAR/state ]] || print unlocked > $VAR/state

# AllowReadAccess false: reads count as violations, not only writes.
# AuditOnly false: Santa denies the access instead of only logging it.
# EnableSilentMode: no Santa dialog; the watcher shows the alert.
# Processes: Spotlight, which would otherwise trip the rule when indexing.
if [[ ! -e $ETC/faa.plist ]]; then
  cat > $ETC/faa.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Version</key>
	<string>honeypot-1</string>
	<key>WatchItems</key>
	<dict>
		<key>Honeypot</key>
		<dict>
			<key>Paths</key>
			<array>
				<dict>
					<key>Path</key>
					<string>$decoy</string>
				</dict>
			</array>
			<key>Options</key>
			<dict>
				<key>RuleType</key>
				<string>PathsWithAllowedProcesses</string>
				<key>AllowReadAccess</key>
				<false/>
				<key>AuditOnly</key>
				<false/>
				<key>EnableSilentMode</key>
				<true/>
			</dict>
			<key>Processes</key>
			<array>
				<dict>
					<key>SigningID</key>
					<string>com.apple.mds</string>
					<key>PlatformBinary</key>
					<true/>
				</dict>
				<dict>
					<key>SigningID</key>
					<string>com.apple.mdworker_shared</string>
					<key>PlatformBinary</key>
					<true/>
				</dict>
			</array>
		</dict>
	</dict>
</dict>
</plist>
EOF
  chown root:wheel $ETC/faa.plist
  chmod 644 $ETC/faa.plist
fi
plutil -lint $ETC/faa.plist

if [[ ! -e $decoy ]]; then
  install -o $user -g staff -m 644 $src/../passwords.decoy.txt $decoy
  # A file created seconds ago looks planted.
  touch -t 202403121745 $decoy
fi
# Time Machine would otherwise be denied, and trip the rule, on every backup.
tmutil addexclusion $decoy

install -o root -g wheel -m 644 $src/$LABEL.plist $plist
if launchctl print system/$LABEL &>/dev/null; then
  launchctl bootout system/$LABEL
  # bootout returns before the job is gone. A bootstrap during teardown
  # fails with "5: Input/output error".
  while launchctl print system/$LABEL &>/dev/null; do sleep 0.2; done
fi
launchctl bootstrap system $plist

print "Installed. Mode: $(<$VAR/mode)."
[[ -d /Applications/Santa.app ]] || print "Santa is not installed yet: brew install --cask santa"
print "Next: open $src/honeypot.mobileconfig and install it in System Settings."
print "Then check: $LIB/honeypot status"
