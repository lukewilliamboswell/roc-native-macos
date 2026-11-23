; Cancelling a drawing stops its jobs: the running one is stopped with its
; worker, the queued ones never start.
(test "cancel"
  (setup
    (worker-pool 1))
  (steps
    (choose "Fast")
    (click (button "Zoom In"))
    (await-work)
    (click (button "Zoom In"))
    (await-work)
    (expect-workers :answered 16 :running 0)
    (choose "Extreme")
    (click (button "Draw"))
    (expect-workers :limit 1 :live 1 :running 1 :queued 7 :answered 16)
    (click (button "Cancel"))
    (await-work)
    (expect-workers :limit 1 :live 0 :running 0 :queued 0 :answered 16 :stopped 1 :lost 0 :timed-out 0 :dropped 0)
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
