; Converted from tests/cancel.script by scripts/convert_cases.roc.
(test "cancel"
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
    (expect-workers :limit 2 :live 2 :running 2 :queued 6 :started 2 :answered 16 :lost 0 :stopped 0 :timed-out 0 :dropped 0)
    (click (button "Cancel"))
    (wait 300)
    (expect-workers :limit 2 :live 0 :running 0 :queued 0 :started 2 :answered 16 :lost 0 :stopped 2 :timed-out 0 :dropped 0)
    (expect-dump """
      --- 600x504
      ui-vstack [1 views]
        ui-vstack [2 views]
          ui-hstack [3 views]
            ui-text "Workers" {text-style=title2 weight=semibold}
            ui-spacer
            ui-text "Roc jobs off the main thread" {color=secondary-label text-style=caption1}
          ui-vstack [2 views]
            ui-hstack [3 views]
              ui-spacer
              ui-segmented [Mandelbrot] Lab
              ui-spacer
            ui-vstack [3 views]
              ui-hstack [6 views]
                ui-button "Draw"
                ui-button "Cancel" (disabled)
                ui-button "Zoom In"
                ui-button "Reset"
                ui-spacer
                ui-segmented Fast Fine [Extreme]
              ui-hstack [3 views]
                ui-progress 0/8
                ui-text "Cancelled." {text-style=callout}
                ui-spacer
              ui-box {border=line:1:separator}
                ui-text "                                                                        
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              
                                                                              " {design=monospaced font-size=10}
      """)))
