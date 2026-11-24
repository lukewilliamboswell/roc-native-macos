; With the timeout on, two seconds with no answer time the request out; a
; second request cancelled before its answer is never answered.
(test "timeout-cancel"
  (steps
    (toggle (checkbox "Time out after 2 s"))
    (expect-checked (checkbox "Time out after 2 s") true)
    (fill (text-field) "https://example.com/slow")
    (click (button "Fetch"))
    (expect-request 1 :timeout 2000)
    (advance-time 1999)
    (expect-pending-effects 1)
    (advance-time 1)
    (expect-pending-effects 0)
    (expect-visible (text "TIMEOUT"))
    (click (button "Fetch"))
    (expect-pending-effects 1)
    (click (button "Cancel"))
    (expect-cancelled 2)
    (expect-pending-effects 0)
    (expect-visible (text "Cancelled #2"))))
