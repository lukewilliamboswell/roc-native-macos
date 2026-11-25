; A crash loses one job. The worker starts a fresh Roc instance for
; later jobs.
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
    (expect-dump (window :width 600 :height 295
                   (vstack :views 1
                     (vstack :views 2
                       (hstack :views 3
                         (text "Workers" :text-style title2 :weight semibold)
                         (spacer)
                         (text "Roc jobs off the main thread" :color secondary-label :text-style caption1))
                       (vstack :views 2
                         (hstack :views 3
                           (spacer)
                           (segmented :items ("Mandelbrot" "Lab") :selected "Lab")
                           (spacer))
                         (vstack :views 6
                           (hstack :views 2
                             (button "Crash a job")
                             (text "No answer: lost (AppCrash)" :text-style callout))
                           (hstack :views 2
                             (button "Run 24 jobs")
                             (text "24 of 24 answered, total 13549840112" :text-style callout))
                           (hstack :views 3
                             (button "Slow job")
                             (button "Cancel" :enabled #f)
                             (text "" :text-style callout))
                           (hstack :views 2
                             (button "Timed job")
                             (text "" :text-style callout))
                           (divider)
                           (drop-zone
                             (hstack :views 4
                               (image doc.text.magnifyingglass)
                               (text "Drop a file to inspect it in a worker." :text-style callout)
                               (spacer)
                               (file-button "Choose…")))))))))))
