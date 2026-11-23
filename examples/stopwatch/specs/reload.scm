; Converted from tests/reload.script by scripts/convert_cases.roc.
(test "reload"
  (steps
    (click (button "Start"))
    (wait 200)
    (click (button "Lap"))
    (reload)
    (wait 300)
    (expect-dump """
      --- 420x236
      ui-vstack [1 views]
        ui-vstack [4 views]
          ui-text "0:00.00" {design=monospaced-digits font-size=56 weight=light}
          ui-hstack [3 views]
            ui-button "Reset"
            ui-button "Lap" (disabled)
            ui-button "Start"
          ui-hstack [3 views]
            ui-text "Laps" {text-style=headline}
            ui-spacer
            ui-text "" {color=secondary-label text-style=caption1}
          ui-box {border=line:1:separator}
            ui-vstack [1 views]
              ui-text "Press Lap while the watch runs." {color=tertiary-label}
      """)
    (click (button "Start"))
    (wait 200)
    (click (button "Stop"))
    (click (button "Reset"))
    (expect-dump """
      --- 420x236
      ui-vstack [1 views]
        ui-vstack [4 views]
          ui-text "0:00.00" {design=monospaced-digits font-size=56 weight=light}
          ui-hstack [3 views]
            ui-button "Reset"
            ui-button "Lap" (disabled)
            ui-button "Start"
          ui-hstack [3 views]
            ui-text "Laps" {text-style=headline}
            ui-spacer
            ui-text "" {color=secondary-label text-style=caption1}
          ui-box {border=line:1:separator}
            ui-vstack [1 views]
              ui-text "Press Lap while the watch runs." {color=tertiary-label}
      """)))
