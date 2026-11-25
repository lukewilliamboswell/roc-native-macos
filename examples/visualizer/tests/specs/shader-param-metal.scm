; The Metal composite uses synthetic.level as red intensity. Four steps
; reach half red, three more reach seven eighths, and the next wraps to zero.
; The host updates the parameter without an engine turn.
(test "shader-param-metal"
  (steps
    (require-metal)
    (renderer metal)
    (window-size 600 300)
    (choose "Shaders")
    (choose "Param")
    (frame 100)
    (expect-visible (text "Shaders: running"))
    (expect-probe (surface "Visualizer") 200 100 :r 0 :g 0 :b 0 :a 100)
    (step-source "synthetic.level" 4)
    (frame 100)
    (expect-probe (surface "Visualizer") 200 100 :r 50 :g 0 :b 0 :a 100)
    (step-source "synthetic.level" 3)
    (frame 100)
    (expect-probe (surface "Visualizer") 200 100 :r 87 :g 0 :b 0 :a 100)
    (mark-metrics)
    (step-source "synthetic.level")
    (frame 100)
    (frame 100)
    (expect-allocations-at-most 0)
    (expect-probe (surface "Visualizer") 200 100 :r 0 :g 0 :b 0 :a 100)))
