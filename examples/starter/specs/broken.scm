; A shader broken in the editor, with the Metal renderer: Orb Garden's
; warp edited to read a name it does not have. The editor and the notice
; name the stage, the line and the compiler's message, and the picture
; keeps drawing with the last good warp. Mending it runs it again.
(test "broken"
  (steps
    (require-metal)
    (renderer metal)
    (choose "Editor")
    (click (button "Hide File"))
    (click (button "Hide Composite"))
    (frame 100)
    (fill (text-area) "float4 warp(Frame f, Params p) {\n    return sample(f, f.uv) * brightness;\n}")
    (frame 100)
    (expect-visible (text "warp, line 2: use of undeclared identifier 'brightness'"))
    (expect-visible (text "The warp, line 2: use of undeclared identifier 'brightness'. The last good shader goes on drawing."))
    (expect-probe (surface "Visualizer") 253 140 :r 24 :g 22 :b 45 :a 100)
    (fill (text-area) "float4 warp(Frame f, Params p) {\n    return sample(f, f.uv) * p.decay;\n}")
    (frame 100)
    (expect-absent (text "warp, line 2: use of undeclared identifier 'brightness'"))
    (expect-dump (window :width 760 :height 1850
                   (vstack :views 1
                     (vstack :views 9
                       (hstack :views 6
                         (asset-image icon.png :pixels 512x512 :width 30 :height 30)
                         (text "Music" :text-style title2 :weight bold)
                         (text "Polymorphic Defunctionalization Through Lambda Set Specialization" :color secondary-label :text-style title3)
                         (spacer)
                         (hstack :views 2
                           (text "" :color red :text-style caption1)
                           (file-button "Add lyrics…"))
                         (checkbox "Lyrics" :checked #f))
                       (hstack :views 2
                         (drop-zone
                           (overlay
                             (surface "Visualizer" :width 506 :height 332 :pacing display :ticking #t :trail held :shader running
                               (space :fit 1000.0 1000.0 :scale 0.332 :offset 87.0 0.0)
                               (save)
                               (transform 1.000 0.000 0.000 1.000 500.000 500.000)
                               (transform 1.000 0.000 0.000 1.000 0.000 0.000)
                               (transform 0.467 0.000 0.000 0.467 0.000 0.000)
                               (opacity 1.000)
                               (opacity 1.000)
                               (stroke adaptive:ff3fc8:ff3fc8 24.0 0.0,-150.0 150.0,0.0 0.0,150.0 -150.0,0.0 0.0,-150.0 close)
                               (restore)
                               (save)
                               (transform 1.000 0.000 0.000 1.000 500.000 500.000)
                               (transform 1.000 0.000 0.000 1.000 0.000 0.000)
                               (transform 0.462 0.000 0.000 0.462 0.000 0.000)
                               (opacity 1.000)
                               (opacity 1.000)
                               (stroke adaptive:22e0d0:22e0d0 24.0 0.0,-130.0 130.0,0.0 0.0,130.0 -130.0,0.0 0.0,-130.0 close)
                               (restore)
                               (save)
                               (transform 1.000 0.000 0.000 1.000 500.000 500.000)
                               (transform 1.000 0.000 0.000 1.000 0.000 0.000)
                               (transform 0.417 0.000 0.000 0.417 0.000 0.000)
                               (opacity 1.000)
                               (opacity 1.000)
                               (stroke adaptive:ff9a2a:ff9a2a 24.0 0.0,-120.0 120.0,0.0 0.0,120.0 -120.0,0.0 0.0,-120.0 close)
                               (restore))
                             (vstack :views 0)))
                         (vstack :views 4
                           (hstack :views 2
                             (text "Presets" :text-style headline)
                             (spacer))
                           (text "Using Orb Garden" :color secondary-label :text-style caption1)
                           (box :border line:1:separator :fill text-background
                             (scroll :views 15 :height 190
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Scope"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Spectrum Bars"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Echo Rings"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Liquid Drift"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Blur Corridor"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Superscope Bloom"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Flux Streaks"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Phase Scope"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Peak Meter"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Plasma Weave"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Hyperspace"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Mirror Shard"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Spectrum Fire"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Ripple Pool"))
                               (hstack :views 2
                                 (text "●" :color accent)
                                 (button "Orb Garden"))))
                           (hstack :views 3
                             (button "New")
                             (button "Duplicate")
                             (button "Edit"))))
                       (box :border line:1:separator
                         (hstack :views 8
                           (text "0:00 / 2:59" :design monospaced-digits :weight medium)
                           (slider :value 0.0)
                           (button "Previous")
                           (button "Play")
                           (button "Stop")
                           (button "Next")
                           (image speaker.wave.2.fill)
                           (slider :value 100.0)))
                       (segmented :items ("Hide Panels" "Queue" "EQ" "Editor") :selected "Editor")
                       (vstack :views 8
                         (hstack :views 4
                           (text "Preset" :text-style headline)
                           (text-field "Orb Garden")
                           (button "Save As")
                           (button "Delete…" :enabled #f))
                         (vstack :views 1
                           (vstack :views 2
                             (hstack :views 3
                               (text "Layer 1" :text-style subheadline :weight semibold)
                               (spacer)
                               (button "Hide Layer 1"))
                             (vstack :views 5
                               (hstack :views 4
                                 (dropdown "Ring" :items ("Waveform" "Circular waveform" "Spectrum bars" "Ring" "Lissajous"))
                                 (dropdown "Custom" :items ("Phosphor" "Amber" "Ice" "Orchid" "Paper" "Custom"))
                                 (spacer)
                                 (button "Remove Layer 1"))
                               (hstack :views 3
                                 (text "Size" :color secondary-label :text-style caption1)
                                 (slider :value 90.0)
                                 (text "90" :design monospaced-digits :text-style caption1))
                               (hstack :views 3
                                 (text "Thickness" :color secondary-label :text-style caption1)
                                 (slider :value 60.0)
                                 (text "60" :design monospaced-digits :text-style caption1))
                               (hstack :views 3
                                 (text "Opacity" :color secondary-label :text-style caption1)
                                 (slider :value 100.0)
                                 (text "100" :design monospaced-digits :text-style caption1))
                               (vstack :views 2
                                 (vstack :views 3
                                   (hstack :views 3
                                     (text "Band 3 → Size, 70 to 150" :text-style caption1)
                                     (spacer)
                                     (button "Remove Mapping 1.1"))
                                   (hstack :views 3
                                     (text "From" :color secondary-label :text-style caption1)
                                     (slider :value 70.0)
                                     (text "70" :design monospaced-digits :text-style caption1))
                                   (hstack :views 3
                                     (text "To" :color secondary-label :text-style caption1)
                                     (slider :value 150.0)
                                     (text "150" :design monospaced-digits :text-style caption1)))
                                 (dropdown "Add Mapping" :items ("Add Mapping" "Level → Size" "Level → Thickness" "Level → Opacity" "Level → Brightness" "Level → Rotation" "Bass → Size" "Bass → Thickness" "Bass → Opacity" "Bass → Brightness" "Bass → Rotation" "Mids → Size" "Mids → Thickness" "Mids → Opacity" "Mids → Brightness" "Mids → Rotation" "Treble → Size" "Treble → Thickness" "Treble → Opacity" "Treble → Brightness" "Treble → Rotation"))))))
                         (vstack :views 1
                           (vstack :views 2
                             (hstack :views 3
                               (text "Layer 2" :text-style subheadline :weight semibold)
                               (spacer)
                               (button "Hide Layer 2"))
                             (vstack :views 5
                               (hstack :views 4
                                 (dropdown "Ring" :items ("Waveform" "Circular waveform" "Spectrum bars" "Ring" "Lissajous"))
                                 (dropdown "Custom" :items ("Phosphor" "Amber" "Ice" "Orchid" "Paper" "Custom"))
                                 (spacer)
                                 (button "Remove Layer 2"))
                               (hstack :views 3
                                 (text "Size" :color secondary-label :text-style caption1)
                                 (slider :value 75.0)
                                 (text "75" :design monospaced-digits :text-style caption1))
                               (hstack :views 3
                                 (text "Thickness" :color secondary-label :text-style caption1)
                                 (slider :value 60.0)
                                 (text "60" :design monospaced-digits :text-style caption1))
                               (hstack :views 3
                                 (text "Opacity" :color secondary-label :text-style caption1)
                                 (slider :value 100.0)
                                 (text "100" :design monospaced-digits :text-style caption1))
                               (vstack :views 2
                                 (vstack :views 3
                                   (hstack :views 3
                                     (text "Band 10 → Size, 60 to 130" :text-style caption1)
                                     (spacer)
                                     (button "Remove Mapping 2.1"))
                                   (hstack :views 3
                                     (text "From" :color secondary-label :text-style caption1)
                                     (slider :value 60.0)
                                     (text "60" :design monospaced-digits :text-style caption1))
                                   (hstack :views 3
                                     (text "To" :color secondary-label :text-style caption1)
                                     (slider :value 130.0)
                                     (text "130" :design monospaced-digits :text-style caption1)))
                                 (dropdown "Add Mapping" :items ("Add Mapping" "Level → Size" "Level → Thickness" "Level → Opacity" "Level → Brightness" "Level → Rotation" "Bass → Size" "Bass → Thickness" "Bass → Opacity" "Bass → Brightness" "Bass → Rotation" "Mids → Size" "Mids → Thickness" "Mids → Opacity" "Mids → Brightness" "Mids → Rotation" "Treble → Size" "Treble → Thickness" "Treble → Opacity" "Treble → Brightness" "Treble → Rotation"))))))
                         (vstack :views 1
                           (vstack :views 2
                             (hstack :views 3
                               (text "Layer 3" :text-style subheadline :weight semibold)
                               (spacer)
                               (button "Hide Layer 3"))
                             (vstack :views 5
                               (hstack :views 4
                                 (dropdown "Ring" :items ("Waveform" "Circular waveform" "Spectrum bars" "Ring" "Lissajous"))
                                 (dropdown "Custom" :items ("Phosphor" "Amber" "Ice" "Orchid" "Paper" "Custom"))
                                 (spacer)
                                 (button "Remove Layer 3"))
                               (hstack :views 3
                                 (text "Size" :color secondary-label :text-style caption1)
                                 (slider :value 65.0)
                                 (text "65" :design monospaced-digits :text-style caption1))
                               (hstack :views 3
                                 (text "Thickness" :color secondary-label :text-style caption1)
                                 (slider :value 60.0)
                                 (text "60" :design monospaced-digits :text-style caption1))
                               (hstack :views 3
                                 (text "Opacity" :color secondary-label :text-style caption1)
                                 (slider :value 100.0)
                                 (text "100" :design monospaced-digits :text-style caption1))
                               (vstack :views 2
                                 (vstack :views 3
                                   (hstack :views 3
                                     (text "Band 17 → Size, 50 to 120" :text-style caption1)
                                     (spacer)
                                     (button "Remove Mapping 3.1"))
                                   (hstack :views 3
                                     (text "From" :color secondary-label :text-style caption1)
                                     (slider :value 50.0)
                                     (text "50" :design monospaced-digits :text-style caption1))
                                   (hstack :views 3
                                     (text "To" :color secondary-label :text-style caption1)
                                     (slider :value 120.0)
                                     (text "120" :design monospaced-digits :text-style caption1)))
                                 (dropdown "Add Mapping" :items ("Add Mapping" "Level → Size" "Level → Thickness" "Level → Opacity" "Level → Brightness" "Level → Rotation" "Bass → Size" "Bass → Thickness" "Bass → Opacity" "Bass → Brightness" "Bass → Rotation" "Mids → Size" "Mids → Thickness" "Mids → Opacity" "Mids → Brightness" "Mids → Rotation" "Treble → Size" "Treble → Thickness" "Treble → Opacity" "Treble → Brightness" "Treble → Rotation"))))))
                         (hstack :views 4
                           (dropdown "Add Layer" :items ("Add Layer" "Waveform" "Circular waveform" "Spectrum bars" "Ring" "Lissajous"))
                           (spacer)
                           (file-button "Import…")
                           (button "Export…"))
                         (vstack :views 2
                           (checkbox "Feedback" :checked #t)
                           (vstack :views 2
                             (hstack :views 3
                               (text "Zoom ‰" :color secondary-label :text-style caption1)
                               (slider :value 1050.0)
                               (text "1050" :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "Half-life" :color secondary-label :text-style caption1)
                               (slider :value 450.0)
                               (text "450 ms" :design monospaced-digits :text-style caption1))))
                         (vstack :views 6
                           (text "Shader params" :text-style subheadline :weight semibold)
                           (vstack :views 2
                             (hstack :views 4
                               (text "decay" :design monospaced :text-style caption1 :weight semibold)
                               (text "how long the orbs' liquid trails last" :color secondary-label :text-style caption1)
                               (spacer)
                               (dropdown "Fixed" :items ("Fixed" "Level" "Bass" "Mids" "Treble" "Band 1" "Band 2" "Band 3" "Band 4" "Band 5" "Band 6" "Band 7" "Band 8" "Band 9" "Band 10" "Band 11" "Band 12" "Band 13" "Band 14" "Band 15" "Band 16" "Band 17" "Band 18" "Band 19" "Band 20" "Band 21" "Band 22" "Band 23" "Band 24")))
                             (hstack :views 2
                               (slider :value 692.0)
                               (text "0.94" :design monospaced-digits :text-style caption1)))
                           (vstack :views 2
                             (hstack :views 4
                               (text "size" :design monospaced :text-style caption1 :weight semibold)
                               (text "an orb's size at rest, in half-heights" :color secondary-label :text-style caption1)
                               (spacer)
                               (dropdown "Fixed" :items ("Fixed" "Level" "Bass" "Mids" "Treble" "Band 1" "Band 2" "Band 3" "Band 4" "Band 5" "Band 6" "Band 7" "Band 8" "Band 9" "Band 10" "Band 11" "Band 12" "Band 13" "Band 14" "Band 15" "Band 16" "Band 17" "Band 18" "Band 19" "Band 20" "Band 21" "Band 22" "Band 23" "Band 24")))
                             (hstack :views 2
                               (slider :value 400.0)
                               (text "0.11" :design monospaced-digits :text-style caption1)))
                           (vstack :views 2
                             (hstack :views 4
                               (text "swell" :design monospaced :text-style caption1 :weight semibold)
                               (text "how far the orbs swell with their bands" :color secondary-label :text-style caption1)
                               (spacer)
                               (dropdown "Level" :items ("Fixed" "Level" "Bass" "Mids" "Treble" "Band 1" "Band 2" "Band 3" "Band 4" "Band 5" "Band 6" "Band 7" "Band 8" "Band 9" "Band 10" "Band 11" "Band 12" "Band 13" "Band 14" "Band 15" "Band 16" "Band 17" "Band 18" "Band 19" "Band 20" "Band 21" "Band 22" "Band 23" "Band 24")))
                             (hstack :views 2
                               (slider :value 0.0)
                               (text "0.2–0.8" :design monospaced-digits :text-style caption1)))
                           (vstack :views 1
                             (vstack :views 2
                               (hstack :views 3
                                 (text "Warp" :text-style subheadline :weight semibold)
                                 (spacer)
                                 (button "Hide Warp"))
                               (text-area "float4 warp(Frame f, Params p) {\n    return sample(f, f.uv) * p.decay;\n}")))
                           (vstack :views 1
                             (vstack :views 1
                               (hstack :views 3
                                 (text "Composite" :text-style subheadline :weight semibold)
                                 (spacer)
                                 (button "Show Composite")))))
                         (vstack :views 1
                           (hstack :views 3
                             (text "File" :text-style subheadline :weight semibold)
                             (spacer)
                             (button "Show File"))))
                       (text "The warp, line 2: use of undeclared identifier 'brightness'. The last good shader goes on drawing." :color secondary-label :text-style callout)
                       (shortcut)
                       (shortcut)
                       (shortcut)))))))
