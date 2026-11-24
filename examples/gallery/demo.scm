; The README's demo of the gallery example: scripts/record_demos.roc records
; its window while these steps run, as docs/images/gallery.gif. It is a spec
; in the same grammar as specs/, but with real effects and time, so it is
; not part of the check.
(test "gallery demo"
  (setup
    (live-effects))
  (steps
    (window)
    (wait 900)
    (choose "Banana") (wait 700)
    (choose "Cherry") (wait 700)
    (toggle (checkbox "Working")) (wait 1600)
    (toggle (checkbox "Working")) (wait 500)
    (choose "Text") (wait 500)
    (fill (text-area) "H") (fill (text-area) "He") (fill (text-area) "Hel") (fill (text-area) "Hell") (fill (text-area) "Hello") (fill (text-area) "Hello,") (fill (text-area) "Hello, n") (fill (text-area) "Hello, na") (fill (text-area) "Hello, nat") (fill (text-area) "Hello, nati") (fill (text-area) "Hello, nativ") (fill (text-area) "Hello, native") (fill (text-area) "Hello, native\nw") (fill (text-area) "Hello, native\nwo") (fill (text-area) "Hello, native\nwor") (fill (text-area) "Hello, native\nworl") (fill (text-area) "Hello, native\nworld") (wait 900)
    (choose "Styles") (wait 1800)
    (choose "Shortcuts") (wait 600)
    (press "cmd+n") (wait 300)
    (press "cmd+n") (wait 300)
    (press "cmd+n") (wait 700)
    (press "cmd+k") (wait 800)
    (choose "Controls") (wait 1000)))
