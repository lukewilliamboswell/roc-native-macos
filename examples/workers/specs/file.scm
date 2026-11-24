; A dropped file is inspected in a worker, which reports on it, and a
; search runs over the report as each query is typed.
(test "file"
  (setup
    (worker-pool 1))
  (steps
    (choose "Lab")
    (drop "specs/fixtures/hello.txt")
    (await-work)
    (fill (text-field) "hello")
    (await-work)
    (fill (text-field) "fixture")
    (await-work)
    (expect-workers :limit 1 :live 1 :running 0 :queued 0 :started 1 :answered 3 :lost 0 :stopped 0 :timed-out 0 :dropped 0)
    (expect-dump (window :width 600 :height 404
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
                         (vstack :views 7
                           (hstack :views 2
                             (button "Crash a job")
                             (text "" :text-style callout))
                           (hstack :views 2
                             (button "Run 24 jobs")
                             (text "" :text-style callout))
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
                               (text "Inspected in a worker." :text-style callout)
                               (spacer)
                               (file-button "Choose…")))
                           (box :border line:1:separator
                             (vstack :views 4
                               (hstack :views 3
                                 (text "hello.txt report.txt" :text-style headline)
                                 (spacer)
                                 (button "Save Report…"))
                               (text "21 bytes, 1 lines, FNV-1a 06ec95d042c623c7; the report is 76 bytes" :color secondary-label :text-style callout)
                               (text "SHA-256 7dd577451abc68bfde0c735f9a184b3ac76bf52f3b4043b371bc54cce6961403" :design monospaced :text-style caption1)
                               (hstack :views 2
                                 (text-field "fixture")
                                 (text "1 line contains “fixture”" :text-style callout))))))))))))
