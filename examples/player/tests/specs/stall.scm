; An analysis worker that falls behind: the ring fills and the oldest
; chunks are skipped, never queued, and the history catches up after.
(test "stall"
  (setup
    (audio-clock manual))
  (steps
    (toggle (checkbox "Measure levels"))
    (files "tests/fixtures/clicks.wav")
    (wait 300)
    (click (button "Play"))
    (render 200)
    (expect-history :count 5 :bound 128 :first "46.4" :last "139.3" :current true :ordered true :waiting 0 :slots 32 :skipped false)
    (stall-analysis true)
    (render 700)
    (expect-history :count 5 :bound 128 :first "46.4" :last "139.3" :current true :ordered true :waiting 32 :slots 32 :skipped true)
    (stall-analysis false)
    (wait 300)
    (expect-history :count 31 :bound 128 :first "46.4" :last "848.3" :current true :ordered true :waiting 0 :slots 32 :skipped true)))
