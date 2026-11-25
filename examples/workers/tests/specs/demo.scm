; Record the heartbeat and the workers drawing the Mandelbrot set.
; Used by scripts/record_demos.roc.
(demo "workers demo"
  (setup
    (live-effects))
  (steps
    (window)
    (wait 800)
    (choose "Fast") (click (button "Draw")) (wait 900)
    (choose "Fine") (click (button "Zoom In")) (wait 1500)
    (click (button "Zoom In")) (wait 1500)
    (choose "Extreme") (click (button "Draw")) (wait 1800)
    (click (button "Cancel")) (wait 800)
    (choose "Fine") (click (button "Reset")) (wait 2000)))
