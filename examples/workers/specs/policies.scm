; A cancelled slow job runs to the end and its answer is dropped; a timed
; job past its timeout is stopped and answered Timeout.
(test "policies"
  (setup
    (worker-pool 2))
  (steps
    (choose "Lab")
    (click (button "Slow job"))
    (click (button "Cancel"))
    (expect-workers :running 1 :answered 0)
    (click (button "Timed job"))
    (await-work)
    (expect-workers :limit 2 :running 0 :queued 0 :started 2 :answered 0 :lost 0 :stopped 1 :timed-out 1 :dropped 1)
    (expect-dump (window :width 600 :height 283
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
                             (text "" :text-style callout))
                           (hstack :views 2
                             (button "Run 24 jobs")
                             (text "" :text-style callout))
                           (hstack :views 3
                             (button "Slow job")
                             (button "Cancel" :enabled #f)
                             (text "Cancelled; the job finishes and its answer is dropped." :text-style callout))
                           (hstack :views 2
                             (button "Timed job")
                             (text "No answer: timed out" :text-style callout))
                           (divider)
                           (drop-zone
                             (hstack :views 4
                               (image doc.text.magnifyingglass)
                               (text "Drop a file to inspect it in a worker." :text-style callout)
                               (spacer)
                               (file-button "Choose…")))))))))))
