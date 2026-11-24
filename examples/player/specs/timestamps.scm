; Measurements stamped with the source position: a seek starts the history
; again, the sources are empty until the next measurement and none once
; measuring stops, and a pause keeps what was measured.
(test "timestamps"
  (setup
    (audio-clock manual))
  (steps
    (toggle (checkbox "Measure levels"))
    (files "specs/fixtures/clicks.wav")
    (wait 300)
    (click (button "Play"))
    (render 300)
    (expect-history :count 9 :bound 128 :first "46.4" :last "232.2" :current true :ordered true :waiting 0 :slots 32 :skipped false)
    (slide (slider 1) 700)
    (expect-history :count 0 :bound 128 :first "-" :last "-" :current true :ordered true :waiting 0 :slots 32 :skipped false)
    (render 250)
    (expect-history :count 7 :bound 128 :first "746.4" :last "885.8" :current true :ordered true :waiting 0 :slots 32 :skipped false)
    (expect-sources :waveform "1024 0.00 0.00" :bands "24 0.00 0.00" :level "0.00" :bass "0.00" :mids "0.00" :treble "0.00")
    (slide (slider 1) 300)
    (expect-sources :waveform "none" :bands "none" :level "none" :bass "none" :mids "none" :treble "none")
    (render 250)
    (expect-history :count 7 :bound 128 :first "346.5" :last "485.8" :current true :ordered true :waiting 0 :slots 32 :skipped false)
    (click (button "Pause"))
    (render 200)
    (expect-history :count 7 :bound 128 :first "346.5" :last "485.8" :current true :ordered true :waiting 0 :slots 32 :skipped false)
    (expect-audio-status :state "Paused" :position 550 :duration 1000 :track 1 :ended 0 :analysis true)
    (toggle (checkbox "Measure levels"))
    (wait 200)
    (expect-audio-status :state "Paused" :position 550 :duration 1000 :track 1 :ended 0 :analysis false)))
