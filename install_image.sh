#!/usr/bin/bash
. /kayak/install_help.sh
ConsoleLog /tmp/kayak.log
ForceDHCP
RunInstall || bomb "RunInstall failed."
[[ -n "$NO_REBOOT" ]] || Reboot
