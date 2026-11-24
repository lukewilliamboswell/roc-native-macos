; A recording of the counter: a (demo …) is a spec with real effects and
; time, so `roc macos.roc test` parses it but never runs it. The platform's
; repository records this one as its README's demo, docs/images/counter.gif
; (scripts/record_demos.roc).
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
