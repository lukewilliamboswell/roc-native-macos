; Record the scope, the fading trail and the native caption above it.
; Used by scripts/record_demos.roc.
(demo "visualizer demo"
  (setup
    (live-effects))
  (steps
    (window)
    (frame-clock display)
    (wait 2500)
    (choose "Echo")
    (wait 3000)
    (toggle (checkbox "Caption"))
    (wait 3000)
    (click (button "Clear trail"))
    (wait 1500)))
