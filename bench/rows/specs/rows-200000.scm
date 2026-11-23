; 200000 rows (rows-2000.scm and rows-200000.scm differ only in the rows): the
; windowed list draws one window of them, a tick writing three rows costs
; those rows alone, and selecting a row rewrites only what shows it. The
; bounds are the same at both sizes, so work that grows with the table fails.
(test "rows-200000"
  (setup
    (local-storage "rows-n" "200000"))
  (steps
    (expect-metric-delta-at-most rows_created 150)
    (toggle (checkbox "Tick"))
    (expect-interval 100 1)
    (mark-metrics)
    (tick-interval 100)
    (tick-interval 100)
    (tick-interval 100)
    (tick-interval 100)
    (tick-interval 100)
    (expect-metric-delta turns 5)
    (expect-metric-delta rows_created 0)
    (expect-metric-delta-at-most rows_updated 15)
    (expect-metric-delta-at-most derived_calls_into_roc 80)
    (expect-metric-delta-at-most patches_emitted 15)
    (toggle (checkbox "Tick"))
    (expect-interval 100 0)
    (mark-metrics)
    (select (list-row 3))
    (expect-metric-delta turns 1)
    (expect-metric-delta-at-most derived_calls_into_roc 2)
    (expect-metric-delta-at-most patches_emitted 1)))
