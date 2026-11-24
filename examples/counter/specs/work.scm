; A click is one turn that rewrites the count's text and builds nothing,
; and allocates a bounded amount: a stray copy of the state would show
; here first. `roc macos.roc test --update` lowers the allocation bounds
; when the app allocates less, and never raises them.
(test "work"
  (steps
    (mark-metrics)
    (click (button "+"))
    (expect-metric-delta turns 1)
    (expect-metric-delta set_text 1)
    (expect-metric-delta create_element 0)
    (expect-metric-delta scopes_created 0)
    (expect-metric-delta-at-most derived_calls_into_roc 2)
    ; TODO(slow-lambda-sets): 7 with --opt=speed; restore it when the default build returns (cli/App.roc build_opt).
    (expect-allocations-at-most 22)
    ; TODO(slow-lambda-sets): 3450 with --opt=speed; restore it when the default build returns (cli/App.roc build_opt).
    (expect-allocated-bytes-at-most 5552)
    (mark-metrics)
    (click (button "+"))
    (click (button "−"))
    (expect-no-new-live-allocations)
    (mark-metrics)
    (click (button "Reset"))
    (click (button "Reset"))
    (expect-metric-delta turns 2)
    (expect-metric-delta set_text 1)))
