#!/bin/bash

/usr/local/bin/check-do-outbound-bandwidth.sh
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 2 ]; then
  echo "$(date): Exit code 2 — stopping and clearing all PM2 apps."
  echo "$(date): Exit code 2 — stopping and clearing all PM2 apps." >> /var/log/pm2-monitor.log

  # TODO: Customize your shutdown logic here
  
  pm2 delete all       # Stop & remove all apps
  pm2 save --force     # Save empty state so nothing restarts
else
  echo "$(date): Exit code $EXIT_CODE — no action taken."
  echo "$(date): Exit code $EXIT_CODE — no action taken." >> /var/log/pm2-monitor.log
fi
