; A composite shader with the Metal renderer: each colour goes to the
; screen inverted, so the red mark shows cyan and the black background
; white. The composite never feeds back: the trail under it is Echo's,
; drifting right and fading, and the composite inverts the frame it makes.
; A Mac without a Metal device stops at (require-metal) and passes.
(test "shader-composite-metal"
  (steps
    (require-metal)
    (renderer metal)
    (window-size 600 300)
    (choose "Shaders")
    (choose "Invert")
    (frame 100)
    (expect-visible (text "Shaders: running"))
    (expect-probe (surface "Visualizer") 30 30 :r 0 :g 100 :b 100 :a 100)
    (expect-probe (surface "Visualizer") 70 30 :r 100 :g 100 :b 100 :a 100)
    (frame 100)
    (expect-probe (surface "Visualizer") 30 30 :r 0 :g 100 :b 100 :a 100)
    (expect-probe (surface "Visualizer") 45 30 :r 50 :g 100 :b 100 :a 100)
    (expect-probe (surface "Visualizer") 120 150 :r 100 :g 100 :b 100 :a 100)))
