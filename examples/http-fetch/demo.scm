; The README's demo of the http-fetch example: scripts/record_demos.roc records
; its window while these steps run, as docs/images/http-fetch.gif. It is a spec
; in the same grammar as specs/, but with real effects and time, so it is
; not part of the check.
(test "http-fetch demo"
  (setup
    (live-effects))
  (steps
    (window)
    (wait 900)
    (fill (text-field) "http://127.0.0.1:9/") (wait 500)
    (click (button "Fetch")) (wait 1600)
    (fill (text-field) "http://127.0.0.1:8737/examples/counter/main.roc") (wait 600)
    (click (button "Fetch")) (wait 2500)))
