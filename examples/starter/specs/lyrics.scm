; The design's lyrics check: cues at 5 s and 12 s and an empty cue at 20 s.
; Lyrics on at 7 s show the first line; a preset switch mid-line keeps it;
; hiding and showing the words keeps the song in place; pausing, then
; seeking to 13 s while paused, shows the second line and stays paused;
; resuming through 20 s clears the overlay.
(test "lyrics"
  (setup
    (audio-clock manual))
  (steps
    (drop "specs/fixtures/clicks.wav" "specs/fixtures/clicks.lrc")
    (await-work)
    (click (button "Next"))
    (wait 400)
    (expect-audio-status :state "Stopped" :position 0 :duration 22000 :track 2)
    (click (button "Play"))
    (render 7000)
    (expect-absent (text "The first line, at five seconds"))
    (press "cmd+l" :heard true)
    (expect-visible (text "The first line, at five seconds"))
    (expect-visible (text "The second line, at twelve"))
    (click (button "Echo Rings"))
    (expect-visible (text "The first line, at five seconds"))
    (press "cmd+l" :heard true)
    (expect-absent (text "The first line, at five seconds"))
    (press "cmd+l" :heard true)
    (expect-visible (text "The first line, at five seconds"))
    (expect-audio-status :state "Playing" :position 7000 :track 2)
    (click (button "Pause"))
    (render 500)
    (expect-audio-status :state "Paused" :position 7000)
    (slide (slider 1) 591)
    (render 100)
    (expect-audio-status :state "Paused" :position 13002)
    (expect-visible (text "The second line, at twelve"))
    (expect-absent (text "The first line, at five seconds"))
    (click (button "Play"))
    (render 7100)
    (expect-audio-status :state "Playing" :position 20102)
    (expect-absent (text "The second line, at twelve"))
    (frame)
    (expect-dump (window :width 760 :height 535
                   (vstack :views 1
                     (vstack :views 8
                       (hstack :views 7
                         (asset-image icon.png :pixels 512x512 :width 30 :height 30)
                         (text "Music" :text-style title2 :weight bold)
                         (text "clicks" :color secondary-label :text-style title3)
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
                               (transform 0.333 0.000 0.000 0.333 0.000 0.000)
                               (opacity 1.000)
                               (stroke adaptive:b266ff:b266ff 12.0 0.0,-450.0 450.0,0.0 0.0,450.0 -450.0,0.0 0.0,-450.0 close)
                               (opacity 1.000)
                               (stroke adaptive:ff66d9:ff66d9 12.0 0.0,-450.0 450.0,0.0 0.0,450.0 -450.0,0.0 0.0,-450.0 close)
                               (restore))
                             (vstack :views 1
                               (hstack :views 2
                                 (spacer)
                                 (button "Read all")))))
                         (vstack :views 17
                           (hstack :views 2
                             (text "Presets" :text-style headline)
                             (spacer))
                           (hstack :views 2
                             (text "" :color accent)
                             (button "Scope"))
                           (hstack :views 2
                             (text "" :color accent)
                             (button "Spectrum Bars"))
                           (hstack :views 2
                             (text "●" :color accent)
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
                           (hstack :views 3
                             (button "New")
                             (button "Duplicate")
                             (button "Edit"))))
                       (box :border line:1:separator
                         (hstack :views 8
                           (text "0:20 / 0:22" :design monospaced-digits)
                           (slider :value 913.0)
                           (button "Previous")
                           (button "Pause")
                           (button "Stop")
                           (button "Next")
                           (image speaker.wave.2.fill)
                           (slider :value 100.0)))
                       (segmented :items ("Hide Panels" "Queue" "EQ" "Editor") :selected "Hide Panels")
                       (text "Read the words of clicks.lrc." :color secondary-label :text-style callout)
                       (shortcut)
                       (shortcut)
                       (shortcut)))))))
