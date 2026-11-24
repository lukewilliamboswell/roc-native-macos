; A param bound to a source, with the Metal renderer: the composite paints
; the surface as red as `synthetic.level`, which the host reads each frame
; without a turn of the engine. Four steps of the level (a half) make it
; half red; four more, full red less an eighth of the way back round.
; A Mac without a Metal device stops at (require-metal) and passes.
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
