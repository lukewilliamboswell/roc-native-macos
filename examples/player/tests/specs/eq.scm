; The EQ cutting the 250 Hz band by 12 dB, bypassed, and back, measured at
; the output: the 4 kHz tone never moves.
(test "eq"
  (setup
    (audio-clock manual))
  (steps
    (files "tests/fixtures/tones-44100.wav")
    (wait 300)
    (click (button "Play"))
    (render 100)
    (expect-tone 250 -20)
    (expect-tone 4000 -20)
    (slide (slider 6) -12)
    (render 100)
    (expect-audio-status :state "Playing" :position 200 :duration 500 :track 1 :ended 0 :analysis false)
    (expect-eq :bypass false :preamp 0 :bands "0 0 0 -12 0 0 0 0 0 0" :volume 100)
    (expect-tone 250 -32)
    (expect-tone 4000 -20)
    (toggle (checkbox "Bypass"))
    (render 100)
    (expect-eq :bypass true :preamp 0 :bands "0 0 0 -12 0 0 0 0 0 0" :volume 100)
    (expect-tone 250 -20)
    (expect-tone 4000 -20)
    (toggle (checkbox "Bypass"))
    (render 100)
    (expect-tone 250 -32)
    (expect-tone 4000 -20)
    (expect-audio-status :state "Playing" :position 400 :duration 500 :track 1 :ended 0 :analysis false)))
