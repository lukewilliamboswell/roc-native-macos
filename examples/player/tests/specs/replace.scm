; A second file replacing the playing one: stopped at its start as the
; second track, then played.
(test "replace"
  (setup
    (audio-clock manual))
  (steps
    (files "tests/fixtures/clicks.wav")
    (wait 300)
    (click (button "Play"))
    (render 950)
    (expect-audio-status :state "Playing" :position 950 :duration 1000 :track 1 :ended 0 :analysis false)
    (files "tests/fixtures/tones-44100.wav")
    (wait 300)
    (expect-audio-status :state "Stopped" :position 0 :duration 500 :track 2 :ended 0 :analysis false)
    (click (button "Play"))
    (render 200)
    (wait 200)
    (expect-audio-status :state "Playing" :position 200 :duration 500 :track 2 :ended 0 :analysis false)
    (expect-dump (window :width 640 :height 595
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
                           (text "tones-44100.wav · Playing · 0:00.20 / 0:00.50" :design monospaced-digits :text-style headline)
                           (slider :value 200.0)
                           (hstack :views 7
                             (button "Play")
                             (button "Pause")
                             (button "Resume")
                             (button "Stop")
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
                       (text "Loaded: 0:00.50, 44100 Hz, 1 channel" :color secondary-label :text-style caption1)))))))
