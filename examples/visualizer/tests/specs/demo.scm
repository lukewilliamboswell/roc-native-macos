; The demo of the visualizer example: scripts/record_demos.roc records its
; window while these steps run: the scope at the display's refresh, then the
; trail, the caption over it, and the trail cleared. A (demo …) is a spec
; with real effects and time, so `test` and the check parse it but never run
; it.
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
