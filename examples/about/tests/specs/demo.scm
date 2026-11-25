; Record the switch between the bitmap and vector assets.
; Used by scripts/record_demos.roc.
(demo "about demo"
  (setup
    (live-effects))
  (steps
    (window)
    (wait 1200)
    (choose "Vector") (wait 1600)
    (choose "Bitmap") (wait 1600)
    (choose "Vector") (wait 1600)))
