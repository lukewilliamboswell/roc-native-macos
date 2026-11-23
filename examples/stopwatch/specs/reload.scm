; A reload starts a fresh engine: the running watch and its lap are gone,
; and the fresh one runs as the first did.
(test "reload"
  (setup
    (initial-time 1700000000000))
  (steps
    (click (button "Start"))
    (tick-interval 47)
    (advance-time 300)
    (tick-interval 47)
    (click (button "Lap"))
    (reload)
    (expect-interval 47 0)
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
    (tick-interval 47)
    (advance-time 200)
    (tick-interval 47)
    (expect-visible (text "0:00.20"))
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
