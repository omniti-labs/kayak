#!/usr/bin/bash
. /kayak/install_help.sh
ForceDHCP
ConsoleLog /tmp/kayak.log
RunInstall || bomb "RunInstall failed."
[[ -n "$NO_REBOOT" ]] || Reboot
