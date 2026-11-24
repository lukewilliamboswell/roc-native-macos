; The README's demo of the counter example: scripts/record_demos.roc records
; its window while these steps run, as docs/images/counter.gif. A (demo …)
; is a spec with real effects and time, so `test` and the check parse it but
; never run it.
(demo "counter demo"
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
