; The README's demo of the counter example: scripts/record_demos.roc records
; its window while these steps run, as docs/images/counter.gif. It is a spec
; in the same grammar as specs/, but with real effects and time, so it is
; not part of the check.
(test "counter demo"
  (setup
    (live-effects))
  (steps
    (window)
    (wait 900)
    (click (button "+")) (wait 450)
    (click (button "+")) (wait 450)
    (click (button "+")) (wait 450)
    (click (button "+")) (wait 450)
    (click (button "+")) (wait 800)
    (click (button "−")) (wait 450)
    (click (button "−")) (wait 900)
    (click (button "Reset")) (wait 1500)))
