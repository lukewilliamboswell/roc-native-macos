; The demo of the player example: scripts/record_demos.roc records its
; window while these steps run. The session renders on its manual clock, so
; the demo plays nothing aloud. A (demo …) is a spec with real effects and
; time, so `test` and the check parse it but never run it.
(demo "player demo"
  (setup
    (live-effects)
    (audio-clock manual))
  (steps
    (window)
    (frame-clock display)
    (toggle (checkbox "Measure levels")) (wait 400)
    (files "tests/fixtures/tones-44100.wav") (wait 900)
    (click (button "Play")) (render 150) (wait 1200)
    (slide (slider 6) -12) (render 100) (wait 1200)
    (toggle (checkbox "Bypass")) (render 100) (wait 1200)))
