; A 60 by 60 grid (grid-20.scm and grid-60.scm differ only in the size): a
; hover writes one cell's state and starts its cooling timer, and a timer
; cools one cell, whatever the grid's size. The bounds are the same at both
; sizes, so a turn that grows with the cells fails.
(test "grid-60"
  (setup
    (local-storage "grid-n" "60"))
  (steps
    (mark-metrics)
    (hover (hover-target 1))
    (hover (hover-target 2))
    (hover (hover-target 3))
    (expect-pending-effects 3)
    (expect-metric-delta create_element 0)
    (expect-metric-delta-at-most derived_calls_into_roc 48)
    (expect-metric-delta-at-most patches_emitted 3)
    (expect-allocations-at-most 50)
    (mark-metrics)
    (fire-timer 500)
    (fire-timer 500)
    (fire-timer 500)
    (expect-pending-effects 0)
    (expect-metric-delta-at-most derived_calls_into_roc 30)
    (expect-metric-delta-at-most patches_emitted 3)))
