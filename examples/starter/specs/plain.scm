; A song dropped with a lyric file of another name stays unpaired; Add
; lyrics… attaches plain text to the current song, read through the
; bounded file API, and the overlay shows its verses whole.
(test "plain"
  (steps
    (drop "specs/fixtures/clicks.wav" "specs/fixtures/verses.txt")
    (expect-visible (text "Added 1 song; 1 file left out."))
    (click (button "Next"))
    (toggle (checkbox "Lyrics"))
    (files "specs/fixtures/verses.txt")
    (await-work)
    (expect-visible (text "Read the words of verses.txt."))
    (choose "Queue")
    (expect-dump (window :width 760 :height 679
                   (vstack :views 1
                     (vstack :views 9
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
                             (surface "Visualizer" :width 506 :height 280 :pacing display :ticking #t
                               (space :fit 1000.0 1000.0 :scale 0.280 :offset 113.0 0.0))
                             (vstack :views 1
                               (box :fill adaptive:141210:141210
                                 (vstack :views 1
                                   (scroll :views 1 :height 140
                                     (text "A click, and then the quiet,\na click, and then the room.\n\nCount them in the silence:\none, and two, and boom." :color adaptive:f4f1ea:f4f1ea :font-size 15)))))))
                         (vstack :views 5
                           (text "Presets" :text-style headline)
                           (hstack :views 2
                             (text "●" :color accent)
                             (button "Scope"))
                           (hstack :views 2
                             (text "" :color accent)
                             (button "Spectrum Bars"))
                           (hstack :views 2
                             (text "" :color accent)
                             (button "Echo Rings"))
                           (hstack :views 3
                             (button "New")
                             (button "Duplicate")
                             (button "Edit"))))
                       (box :border line:1:separator
                         (hstack :views 8
                           (text "0:00 / 0:22" :design monospaced-digits)
                           (slider :value 0.0)
                           (button "Previous")
                           (button "Play")
                           (button "Stop")
                           (button "Next")
                           (image speaker.wave.2.fill)
                           (slider :value 100.0)))
                       (segmented :items ("Hide Panels" "Queue" "EQ" "Editor") :selected "Queue")
                       (vstack :views 2
                         (hstack :views 3
                           (text "Queue · 2 songs of 60" :text-style headline)
                           (spacer)
                           (button "Clear Queue"))
                         (scroll :views 2 :height 160
                           (hstack :views 6
                             (text "1." :color secondary-label :design monospaced-digits)
                             (text "Polymorphic Defunctionalization Through Lambda Set Specialization")
                             (spacer)
                             (text "timed lyrics" :color secondary-label :text-style caption1)
                             (button "Play Polymorphic Defunctionalization Through Lambda Set Specialization")
                             (button "Remove Polymorphic Defunctionalization Through Lambda Set Specialization"))
                           (hstack :views 6
                             (text "▶" :color secondary-label :design monospaced-digits)
                             (text "clicks")
                             (spacer)
                             (text "lyrics as text" :color secondary-label :text-style caption1)
                             (button "Play clicks")
                             (button "Remove clicks"))))
                       (text "Read the words of verses.txt." :color secondary-label :text-style callout)
                       (shortcut)
                       (shortcut)
                       (shortcut)))))))
