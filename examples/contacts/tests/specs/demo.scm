; The README's demo of the contacts example: scripts/record_demos.roc
; records its window while these steps run, as docs/images/contacts.gif. A
; (demo …) is a spec with real effects and time, so `test` and the check
; parse it but never run it.
(demo "contacts demo"
  (setup
    (live-effects))
  (steps
    (window)
    (wait 1000)
    (fill (text-field) "a") (wait 150) (fill (text-field) "ad") (wait 150) (fill (text-field) "ada") (wait 700)
    (select (list-row "Ada A. Lovelace")) (wait 900)
    (select (list-row "Ada A. Turing")) (wait 900)
    (select (list-row "Ada A. Liskov")) (wait 1000)
    (fill (text-field) "ada l") (wait 150) (fill (text-field) "ada li") (wait 150) (fill (text-field) "ada lis") (wait 1200)
    (fill (text-field) "") (wait 1200)))
