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
    (expect-dump (window :width 600 :height 504
                   (vstack :views 1
                     (vstack :views 2
                       (hstack :views 3
                         (text "Workers" :text-style title2 :weight semibold)
                         (spacer)
                         (text "Roc jobs off the main thread" :color secondary-label :text-style caption1))
                       (vstack :views 2
                         (hstack :views 3
                           (spacer)
                           (segmented :items ("Mandelbrot" "Lab") :selected "Mandelbrot")
                           (spacer))
                         (vstack :views 3
                           (hstack :views 6
                             (button "Draw")
                             (button "Cancel" :enabled #f)
                             (button "Zoom In")
                             (button "Reset")
                             (spacer)
                             (segmented :items ("Fast" "Fine" "Extreme") :selected "Extreme"))
                           (hstack :views 3
                             (progress :value 0 :max 8)
                             (text "Cancelled." :text-style callout)
                             (spacer))
                           (box :border line:1:separator
                             (text "                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        \n                                                                        " :design monospaced :font-size 10))))))))))
