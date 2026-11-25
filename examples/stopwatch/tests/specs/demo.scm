; Record laps as the live interval advances the stopwatch.
; Used by scripts/record_demos.roc.
(demo "stopwatch demo"
  (setup
    (live-effects))
  (steps
    (window)
    (wait 900)
    (click (button "Start")) (wait 1300)
    (click (button "Lap")) (wait 1100)
    (click (button "Lap")) (wait 1500)
    (click (button "Lap")) (wait 700)
    (click (button "Stop")) (wait 1500)
    (click (button "Reset")) (wait 1200)))
