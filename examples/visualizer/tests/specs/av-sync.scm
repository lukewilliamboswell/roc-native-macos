; Audio/visual sync on the real clock: the Sync Test preset flashes white on
; every click of a click track played to the Mac's own output, and the
; harness (host/AVTiming.swift) matches each click as it is heard to the
; flash as it is presented. It plays to a speaker and draws at the
; display's pace, so it runs only with ROC_AV_TIMING=1 (and a Metal device);
; elsewhere it passes at (require-av-timing). docs/apps.adoc, "Measure
; audio/visual sync".
(test "av-sync"
  (steps
    (require-av-timing)
    (require-metal)
    (renderer metal)
    (frame-clock display)
    (window-size 830 700)
    (choose "Gallery")
    (choose "Sync Test")
    (files "tests/fixtures/sync-clicks.wav")
    (wait 500)
    (mark-av-timing)
    (wait 6000)
    (expect-av-offset :mean-within 30 :p95-within 45 :lead-at-most 15 :matched-at-least 10)
    (expect-frame-pacing :dropped-at-most 6 :p99-at-most 25)))
