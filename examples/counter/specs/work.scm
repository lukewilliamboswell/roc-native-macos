; A click is one turn that rewrites the count's text and builds nothing.
(test "work"
  (steps
    (mark-metrics)
    (click (button "+"))
    (expect-metric-delta turns 1)
    (expect-metric-delta set_text 1)
    (expect-metric-delta create_element 0)
    (expect-metric-delta scopes_created 0)
    (expect-metric-delta-at-most derived_calls_into_roc 2)
    (mark-metrics)
    (click (button "Reset"))
    (click (button "Reset"))
    (expect-metric-delta turns 2)
    (expect-metric-delta set_text 1)))
