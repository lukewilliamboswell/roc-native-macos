; While the watch runs, an interval ticks; the clock is virtual, so each
; tick adds exactly the time the spec moves it on.
(test "start-stop-reset"
  (setup
    (initial-time 1700000000000))
  (steps
    (click (button "Start"))
    (expect-interval 47 1)
    (tick-interval 47)
    (advance-time 1250)
    (tick-interval 47)
    (expect-visible (text "0:01.25"))
    (click (button "Lap"))
    (advance-time 500)
    (tick-interval 47)
    (click (button "Stop"))
    (expect-interval 47 0)
    (expect-visible (text "0:01.75"))
    (expect-dump """
      --- 420x236
      ui-vstack [1 views]
        ui-vstack [4 views]
          ui-text "0:01.75" {design=monospaced-digits font-size=56 weight=light}
          ui-hstack [3 views]
            ui-button "Reset"
            ui-button "Lap" (disabled)
            ui-button "Start"
          ui-hstack [3 views]
            ui-text "Laps" {text-style=headline}
            ui-spacer
            ui-text "1 recorded" {color=secondary-label text-style=caption1}
          ui-box {border=line:1:separator}
            ui-vstack [1 views]
              ui-hstack [4 views]
                ui-text "Lap 1" {color=secondary-label}
                ui-text "0:01.25" {design=monospaced-digits}
                ui-spacer
                ui-text "0:01.25" {color=secondary-label design=monospaced-digits}
      """)
    (click (button "Reset"))
    (expect-visible (text "0:00.00"))
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
