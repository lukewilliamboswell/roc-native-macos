; An analysis worker that falls behind: the ring fills and the oldest
; chunks are skipped, never queued, and the history catches up after.
(test "stall"
  (setup
    (audio-clock manual))
  (steps
    (toggle (checkbox "Measure levels"))
    (files "specs/fixtures/clicks.wav")
    (wait 300)
    (click (button "Play"))
    (render 200)
    (expect-history :count 5 :bound 32 :first "46.4" :last "139.3" :current true :ordered true :waiting 0 :slots 4 :skipped false)
    (stall-analysis true)
    (render 700)
    (expect-history :count 5 :bound 32 :first "46.4" :last "139.3" :current true :ordered true :waiting 4 :slots 4 :skipped true)
    (stall-analysis false)
    (wait 300)
    (expect-history :count 19 :bound 32 :first "46.4" :last "848.3" :current true :ordered true :waiting 0 :slots 4 :skipped true)))
