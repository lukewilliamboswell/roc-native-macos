; The README's demo of the stopwatch example: scripts/record_demos.roc records
; its window while these steps run, as docs/images/stopwatch.gif. It is a spec
; in the same grammar as specs/, but with real effects and time, so it is
; not part of the check.
(test "stopwatch demo"
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
