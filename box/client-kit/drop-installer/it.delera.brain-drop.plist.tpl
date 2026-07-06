<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>it.delera.brain-drop</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>__WATCHER__</string>
  </array>
  <!-- trigger A EVENTO: scatta all'istante del drop in una cartella reparto -->
  <key>WatchPaths</key>
  <array>
__WATCHPATHS__
  </array>
  <!-- rete di sicurezza: tick ogni 60s (coda offline, retry rete giù/5xx) -->
  <key>StartInterval</key><integer>60</integer>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>/tmp/brain-drop.err.log</string>
</dict>
</plist>
