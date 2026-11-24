; The demo of the visualizer example: scripts/record_demos.roc records its
; window while these steps run: the scope at the display's refresh, then the
; trail, the caption over it, and the trail cleared. It is a spec in the
; same grammar as specs/, but with real effects and time, so it is not part
; of the check.
(test "visualizer demo"
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
