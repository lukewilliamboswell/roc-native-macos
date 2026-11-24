; The README's demo of the about example: scripts/record_demos.roc records
; its window while these steps run, as docs/images/about.gif. A (demo …) is
; a spec with real effects and time, so `test` and the check parse it but
; never run it.
(demo "about demo"
  (setup
    (live-effects))
  (steps
    (window)
    (wait 1200)
    (choose "Vector") (wait 1600)
    (choose "Bitmap") (wait 1600)
    (choose "Vector") (wait 1600)))
