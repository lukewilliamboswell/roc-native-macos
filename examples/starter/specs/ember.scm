; The design's third check: Ember Tunnel made from a blank preset as its
; file, saved, exported by a worker, drawn on the surface as a ring the
; bass scales with a trail, then chosen again after Scope, and kept
; through a reload, with the Lyrics choice.
(test "ember"
  (setup
    (worker-pool 1))
  (steps
    (click (button "New"))
    (fill (text-area) "{\"version\": 1, \"id\": \"user.untitled\", \"name\": \"Untitled\", \"background\": \"#0B0705\", \"layers\": [{\"type\": \"circular-waveform\", \"colors\": [\"#FF8C1A\", \"#FFD27A\"], \"size\": 200, \"thickness\": 25, \"opacity\": 100, \"mappings\": [{\"feature\": \"bass\", \"property\": \"size\", \"from\": 200, \"to\": 380}, {\"feature\": \"treble\", \"property\": \"brightness\", \"from\": 40, \"to\": 100}]}], \"feedback\": {\"enabled\": true, \"zoom\": 1030, \"rotation\": 0, \"half_life_ms\": 300}}")
    (fill (text-field "Name") "Ember Tunnel")
    (click (button "Save As"))
    (expect-visible (text "Saved Ember Tunnel."))
    (click (button "Export…"))
    (await-work)
    (expect-workers :answered 1 :lost 0)
    (expect-visible (text "Exported ember-tunnel.json."))
    (choose "Hide Panels")
    (click (button "Scope"))
    (frame)
    (click (button "Ember Tunnel"))
    (toggle (checkbox "Lyrics"))
    (reload)
    (frame)
    (expect-checked (checkbox "Lyrics") true)
    (expect-dump (window :width 760 :height 539
                   (vstack :views 1
                     (vstack :views 8
                       (hstack :views 7
                         (asset-image icon.png :pixels 512x512 :width 30 :height 30)
                         (text "Music" :text-style title2 :weight bold)
                         (text "Polymorphic Defunctionalization Through Lambda Set Specialization" :color secondary-label :text-style title3)
                         (spacer)
                         (hstack :views 2
                           (text "" :color red :text-style caption1)
                           (file-button "Add lyrics…"))
                         (hstack :views 2
                           (button "Smaller Lyrics")
                           (button "Larger Lyrics"))
                         (checkbox "Lyrics" :checked #t))
                       (hstack :views 2
                         (drop-zone
                           (overlay
                             (surface "Visualizer" :width 506 :height 332 :pacing display :ticking #t :trail held
                               (space :fit 1000.0 1000.0 :scale 0.332 :offset 87.0 0.0)
                               (save)
                               (transform 1.000 0.000 0.000 1.000 500.000 500.000)
                               (transform 1.000 0.000 0.000 1.000 0.000 0.000)
                               (transform 0.526 0.000 0.000 0.526 0.000 0.000)
                               (opacity 1.000)
                               (opacity 0.400)
                               (restore))
                             (vstack :views 1
                               (hstack :views 2
                                 (spacer)
                                 (button "Read all")))))
                         (vstack :views 4
                           (hstack :views 2
                             (text "Presets" :text-style headline)
                             (spacer))
                           (text "Using Ember Tunnel" :color secondary-label :text-style caption1)
                           (box :border line:1:separator :fill text-background
                             (scroll :views 17 :height 190
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
                                 (text "" :color accent)
                                 (button "Orb Garden"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Sync Test"))
                               (hstack :views 2
                                 (text "●" :color accent)
                                 (button "Ember Tunnel"))))
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
                       (segmented :items ("Hide Panels" "Queue" "EQ" "Editor") :selected "Hide Panels")
                       (text "Press Play for the default song, or drop your own songs here with their .lrc or .txt lyrics." :color secondary-label :text-style callout)
                       (shortcut)
                       (shortcut)
                       (shortcut)))))))
