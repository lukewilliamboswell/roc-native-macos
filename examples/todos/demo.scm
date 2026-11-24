; The README's demo of the todos example: scripts/record_demos.roc records
; its window while these steps run, as docs/images/todos.gif. It is a spec
; in the same grammar as specs/, but with real effects and time, so it is
; not part of the check.
(test "todos demo"
  (setup
    (live-effects))
  (steps
    (window)
    (wait 900)
    (fill (text-field) "B") (fill (text-field) "Bu") (fill (text-field) "Buy") (fill (text-field) "Buy ") (fill (text-field) "Buy m") (fill (text-field) "Buy mi") (fill (text-field) "Buy mil") (fill (text-field) "Buy milk") (wait 300)
    (submit (text-field)) (wait 600)
    (fill (text-field) "W") (fill (text-field) "Wa") (fill (text-field) "Wal") (fill (text-field) "Walk") (fill (text-field) "Walk ") (fill (text-field) "Walk t") (fill (text-field) "Walk th") (fill (text-field) "Walk the") (fill (text-field) "Walk the ") (fill (text-field) "Walk the d") (fill (text-field) "Walk the do") (fill (text-field) "Walk the dog") (wait 300)
    (submit (text-field)) (wait 600)
    (fill (text-field) "R") (fill (text-field) "Re") (fill (text-field) "Rea") (fill (text-field) "Read") (fill (text-field) "Read ") (fill (text-field) "Read a") (fill (text-field) "Read a ") (fill (text-field) "Read a b") (fill (text-field) "Read a bo") (fill (text-field) "Read a boo") (fill (text-field) "Read a book") (wait 300)
    (submit (text-field)) (wait 800)
    (toggle (checkbox "Buy milk")) (wait 700)
    (toggle (checkbox "Read a book")) (wait 900)
    (choose "Done") (wait 1200)
    (choose "Open") (wait 1200)
    (choose "All") (wait 1500)))
