; Quitting while jobs run stops them through teardown: the spec ends with
; a drawing under way, and the app must still exit normally.
(test "quit"
  (setup
    (worker-pool 1))
  (steps
    (choose "Fast")
    (click (button "Zoom In"))
    (await-work)
    (click (button "Zoom In"))
    (await-work)
    (choose "Extreme")
    (click (button "Draw"))
    (expect-workers :limit 1 :live 1 :running 1 :queued 7 :answered 16)))
