; A job that crashes is lost alone: its worker is discarded, and the next
; jobs run on a fresh one.
(test "crash"
  (setup
    (worker-pool 1))
  (steps
    (choose "Lab")
    (click (button "Crash a job"))
    (await-work)
    (expect-workers :lost 1 :answered 0)
    (click (button "Run 24 jobs"))
    (await-work)
    (expect-workers :limit 1 :running 0 :queued 0 :answered 24 :lost 1 :stopped 0 :timed-out 0 :dropped 0)
    (expect-dump """
      --- 600x283
      ui-vstack [1 views]
        ui-vstack [2 views]
          ui-hstack [3 views]
            ui-text "Workers" {text-style=title2 weight=semibold}
            ui-spacer
            ui-text "Roc jobs off the main thread" {color=secondary-label text-style=caption1}
          ui-vstack [2 views]
            ui-hstack [3 views]
              ui-spacer
              ui-segmented Mandelbrot [Lab]
              ui-spacer
            ui-vstack [6 views]
              ui-hstack [2 views]
                ui-button "Crash a job"
                ui-text "No answer: lost (AppCrash)" {text-style=callout}
              ui-hstack [2 views]
                ui-button "Run 24 jobs"
                ui-text "24 of 24 answered, total 13549840112" {text-style=callout}
              ui-hstack [3 views]
                ui-button "Slow job"
                ui-button "Cancel" (disabled)
                ui-text "" {text-style=callout}
              ui-hstack [2 views]
                ui-button "Timed job"
                ui-text "" {text-style=callout}
              ui-divider
              ui-drop-zone
                ui-hstack [4 views]
                  ui-image doc.text.magnifyingglass
                  ui-text "Drop a file to inspect it in a worker." {text-style=callout}
                  ui-spacer
                  ui-file-button "Choose…"
      """)))
