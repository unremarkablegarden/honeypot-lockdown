#!/bin/zsh
# Stops the watcher, lifts a lockdown if one is active, and moves the
# installed files, the log and the decoy to .trash/ in the project root.
# Does not remove Santa or the configuration profile.

set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin

(( EUID == 0 )) || { print -u2 "run with sudo"; exit 1 }
user=${SUDO_USER:?run with sudo from your own account, not as root}
home=$(dscl . -read /Users/$user NFSHomeDirectory | awk '{ print $2 }')
src=${0:A:h}

LABEL=com.euklides.honeypot
LIB=/usr/local/libexec/honeypot
ETC=/usr/local/etc/honeypot
VAR=/var/db/honeypot
plist=/Library/LaunchDaemons/$LABEL.plist

launchctl bootout system/$LABEL 2>/dev/null || true
[[ -x $LIB/honeypot && $(cat $VAR/state 2>/dev/null) == locked ]] && $LIB/honeypot unlock

trash=$src/../.trash/uninstall-$(date +%Y%m%d-%H%M%S)
mkdir -p $trash
for item in $LIB $ETC $VAR $plist /var/log/honeypot.log $home/passwords.txt; do
  [[ -e $item ]] && mv $item $trash/${item:t}-${item:h:t}
done
chown -R $user $src/../.trash

print "Uninstalled. Everything is in ${trash:A}"
print "Still present: Santa, and the profile 'Honeypot: Santa configuration' in System Settings."
