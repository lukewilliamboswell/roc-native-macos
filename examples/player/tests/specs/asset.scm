; A file the app ships in assets/ loads by its path there (LoadAsset), with
; the events a picked file has, and plays; a path that leaves assets/ is
; refused as a load that cannot start, and the session goes idle.
(test "asset"
  (setup
    (audio-clock manual))
  (steps
    (click (button "Play Sample"))
    (wait 300)
    (expect-audio-status :state "Stopped" :position 0 :duration 1000 :track 1 :ended 0)
    (expect-visible (text "Loaded: 0:01.00, 22050 Hz, 1 channel"))
    (click (button "Play"))
    (render 250)
    (expect-audio-status :state "Playing" :position 250 :track 1)
    (click (button "Escape Assets"))
    (wait 300)
    (expect-audio-status :state "Idle" :position 0 :duration 0 :track 2)
    (expect-dump (window :width 777 :height 595
                   (vstack :views 1
                     (vstack :views 6
                       (hstack :views 6
                         (image music.note)
                         (text "Player" :text-style title2 :weight semibold)
                         (spacer)
                         (button "Play Sample")
                         (button "Escape Assets")
                         (file-button "Choose Audio…"))
                       (drop-zone
                         (text "Drop an audio file here" :color secondary-label :text-style headline))
                       (box
                         (vstack :views 3
                           (text "Nothing loaded" :design monospaced-digits :text-style headline)
                           (slider :value 0.0)
                           (hstack :views 7
                             (button "Play" :enabled #f)
                             (button "Pause" :enabled #f)
                             (button "Resume" :enabled #f)
                             (button "Stop" :enabled #f)
                             (spacer)
                             (text "Volume" :color secondary-label :text-style caption1)
                             (slider :value 100.0))))
                       (box
                         (vstack :views 2
                           (hstack :views 4
                             (text "Equalizer" :text-style headline)
                             (spacer)
                             (checkbox "Bypass" :checked #f)
                             (button "Flat"))
                           (vstack :views 11
                             (hstack :views 3
                               (text "32" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "64" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "125" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "250" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "500" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "1k" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "2k" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "4k" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "8k" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "16k" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1))
                             (hstack :views 3
                               (text "Preamp" :color secondary-label :text-style caption1)
                               (slider :value 0.0)
                               (text "0 dB" :color secondary-label :design monospaced-digits :text-style caption1)))))
                       (box
                         (vstack :views 2
                           (hstack :views 3
                             (checkbox "Measure levels" :checked #f)
                             (spacer)
                             (text "—" :design monospaced-digits))
                           (overlay :vertical center
                             (box :fill adaptive:e2ebe8:233330
                               (spacer))
                             (progress :value 0 :max 60))))
                       (text "Could not play it: unsupported (asset \"../tests/fixtures/clicks.wav\" is not a name inside the app's assets/ directory (such as logo.png or icons/star.pdf))" :color secondary-label :text-style caption1)))))))
