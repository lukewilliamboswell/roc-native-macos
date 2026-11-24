; The README's demo of the about example: scripts/record_demos.roc records
; its window while these steps run, as docs/images/about.gif. It is a spec
; in the same grammar as specs/, but with real effects and time, so it is
; not part of the check.
(test "about demo"
  (setup
    (live-effects))
  (steps
    (window)
    (wait 1200)
    (choose "Vector") (wait 1600)
    (choose "Bitmap") (wait 1600)
    (choose "Vector") (wait 1600)))
