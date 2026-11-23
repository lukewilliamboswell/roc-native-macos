; Converted from tests/quit.script by scripts/convert_cases.roc.
(test "quit"
  (setup
    (worker-pool 2))
  (steps
    (choose "Fast")
    (click (button "Zoom In"))
    (wait 300)
    (click (button "Zoom In"))
    (wait 300)
    (choose "Extreme")
    (click (button "Draw"))
    (wait 250)
    (expect-workers :limit 2 :live 2 :running 2 :queued 6 :started 2 :answered 16 :lost 0 :stopped 0 :timed-out 0 :dropped 0)))
