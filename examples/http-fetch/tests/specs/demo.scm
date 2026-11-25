; Record a live request to the recorder's local HTTP server.
; Used by scripts/record_demos.roc.
(demo "http-fetch demo"
  (setup
    (live-effects))
  (steps
    (window)
    (wait 900)
    (fill (text-field) "http://127.0.0.1:9/") (wait 500)
    (click (button "Fetch")) (wait 1600)
    (fill (text-field) "http://127.0.0.1:8737/examples/counter/src/main.roc") (wait 600)
    (click (button "Fetch")) (wait 2500)))
