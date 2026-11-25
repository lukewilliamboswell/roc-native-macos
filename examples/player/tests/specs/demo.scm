; Record playback controls on the manual audio clock without speaker output.
; Used by scripts/record_demos.roc.
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
