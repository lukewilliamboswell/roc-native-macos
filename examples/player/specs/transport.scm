; Play, Pause, a seek while paused, and Resume from there; the allocations
; a resumed second of playback makes stay bounded.
(test "transport"
  (setup
    (audio-clock manual))
  (steps
    (files "specs/fixtures/clicks.wav")
    (wait 300)
    (click (button "Play"))
    (render 300)
    (expect-audio-status :state "Playing" :position 300 :duration 1000 :track 1 :ended 0 :analysis false)
    (click (button "Pause"))
    (render 200)
    (expect-audio-status :state "Paused" :position 300 :duration 1000 :track 1 :ended 0 :analysis false)
    (slide (slider 1) 800)
    (wait 200)
    (expect-audio-status :state "Paused" :position 800 :duration 1000 :track 1 :ended 0 :analysis false)
    (mark-metrics)
    (click (button "Resume"))
    (render 100)
    (wait 200)
    (expect-audio-status :state "Playing" :position 900 :duration 1000 :track 1 :ended 0 :analysis false)
    ; TODO(slow-lambda-sets): 212 with --opt=speed; restore it when the default build returns (cli/App.roc build_opt).
    ; The conditional backlight adds six allocations with measurement off.

    (expect-allocations-at-most 884)
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
                           (text "clicks.wav · Playing · 0:00.90 / 0:01.00" :design monospaced-digits :text-style headline)
                           (slider :value 900.0)
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
                       (text "Loaded: 0:01.00, 22050 Hz, 1 channel" :color secondary-label :text-style caption1)))))))
