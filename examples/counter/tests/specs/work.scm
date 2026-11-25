; A click updates the text in one turn without creating views. This spec
; also bounds allocation and checks that an increment and decrement leave
; no additional allocations live.
; https://lukewilliamboswell.github.io/roc-native-macos/apps.html#work-metrics
(test "work"
  (steps
    (mark-metrics)
    (click (button "+"))
    (expect-metric-delta turns 1)
    (expect-metric-delta set_text 1)
    (expect-metric-delta create_element 0)
    (expect-metric-delta scopes_created 0)
    (expect-metric-delta-at-most derived_calls_into_roc 2)
    ; TODO(slow-lambda-sets): 7 once the tool builds with --opt=speed again.
    (expect-allocations-at-most 22)
    ; TODO(slow-lambda-sets): 3450 once the tool builds with --opt=speed again.
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
