; The design's first check: one song and one scope. The scope draws the
; waveform the session measures while it plays; pause holds the playhead,
; a seek while paused stays paused, resume plays on from there; and a
; track switch near the end loads the other song, whose position the old
; song's end never moves.
(test "transport"
  (setup
    (audio-clock manual))
  (steps
    (drop "specs/fixtures/clicks.wav")
    (click (button "Next"))
    (wait 400)
    (expect-audio-status :state "Stopped" :position 0 :duration 22000 :track 2 :ended 0)
    (mark-metrics)
    (click (button "Play"))
    (expect-allocations-at-most 2559)
    (render 1000)
    (wait 200)
    (expect-audio-status :state "Playing" :position 1000 :track 2 :analysis true)
    (frame)
    (expect-surfaces :shown 1 :ticking 1)
    (expect-snapshot :present true :rate 4000 :finite true)
    (expect-history :current true :ordered true :skipped false)
    (expect-text (text "0:01 / 0:22") "0:01 / 0:22")
    (click (button "Pause"))
    (render 400)
    (expect-audio-status :state "Paused" :position 1000)
    (press "ArrowRight" :heard true)
    (render 100)
    (expect-audio-status :state "Paused" :position 6000)
    (expect-text (text "0:06 / 0:22") "0:06 / 0:22")
    (click (button "Play"))
    (render 200)
    (expect-audio-status :state "Playing" :position 6200)
    (slide (slider 1) 977)
    (render 300)
    (expect-audio-status :state "Playing" :position 21794 :track 2 :ended 0)
    (click (button "Previous"))
    (wait 400)
    (render 600)
    (expect-audio-status :state "Playing" :position 600 :track 3 :ended 0)
    (expect-visible (text "Polymorphic Defunctionalization Through Lambda Set Specialization"))
    (expect-text (text "0:00 / 2:59") "0:00 / 2:59")))
