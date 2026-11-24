; The README's demo of the workers example: scripts/record_demos.roc records
; its window while these steps run, as docs/images/workers.gif. It is a spec
; in the same grammar as specs/, but with real effects and time, so it is
; not part of the check.
(test "workers demo"
  (setup
    (live-effects))
  (steps
    (window)
    (wait 800)
    (choose "Fast") (click (button "Draw")) (wait 900)
    (choose "Fine") (click (button "Zoom In")) (wait 1500)
    (click (button "Zoom In")) (wait 1500)
    (choose "Extreme") (click (button "Draw")) (wait 1800)
    (click (button "Cancel")) (wait 800)
    (choose "Fine") (click (button "Reset")) (wait 2000)))
