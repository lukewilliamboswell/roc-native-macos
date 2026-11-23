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
    (expect-dump """
      --- 600x404
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
            ui-vstack [7 views]
              ui-hstack [2 views]
                ui-button "Crash a job"
                ui-text "" {text-style=callout}
              ui-hstack [2 views]
                ui-button "Run 24 jobs"
                ui-text "" {text-style=callout}
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
                  ui-text "Inspected in a worker." {text-style=callout}
                  ui-spacer
                  ui-file-button "Choose…"
              ui-box {border=line:1:separator}
                ui-vstack [4 views]
                  ui-hstack [3 views]
                    ui-text "hello.txt report.txt" {text-style=headline}
                    ui-spacer
                    ui-button "Save Report…"
                  ui-text "21 bytes, 1 lines, FNV-1a 06ec95d042c623c7; the report is 76 bytes" {color=secondary-label text-style=callout}
                  ui-text "SHA-256 7dd577451abc68bfde0c735f9a184b3ac76bf52f3b4043b371bc54cce6961403" {design=monospaced text-style=caption1}
                  ui-hstack [2 views]
                    ui-text-field "fixture"
                    ui-text "1 line contains “fixture”" {text-style=callout}
      """)))
