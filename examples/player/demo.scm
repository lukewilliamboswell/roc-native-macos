; The demo of the player example: scripts/record_demos.roc records its
; window while these steps run. The session renders on its manual clock,
; so the demo plays nothing aloud. It is a spec in the same grammar as
; specs/, but with real effects and time, so it is not part of the check.
(test "player demo"
  (setup
    (live-effects)
    (audio-clock manual))
  (steps
    (window)
    (toggle (checkbox "Measure levels")) (wait 400)
    (files "specs/fixtures/tones-44100.wav") (wait 900)
    (click (button "Play")) (render 150) (wait 1200)
    (slide (slider 6) -12) (render 100) (wait 1200)
    (toggle (checkbox "Bypass")) (render 100) (wait 1200)))
