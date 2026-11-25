; This recording script uses the spec grammar with live effects and waits.
; `roc macos.roc test --check` checks its syntax.
; https://lukewilliamboswell.github.io/roc-native-macos/apps.html#test-an-app
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
