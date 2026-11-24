; Sliders keep their value inside their range: one dragged past its low
; end stops there, and one with a wide range takes a value far up it.
(test "ranges"
  (steps
    (expect-dump (window :width 560 :height 539
                   (vstack :views 1
                     (vstack :views 4
                       (hstack :views 2
                         (image square.grid.2x2.fill)
                         (vstack :views 2
                           (text "Gallery" :text-style title2 :weight semibold)
                           (text "Controls, typography, colors, and shortcuts" :color secondary-label :text-style caption1)))
                       (vstack :views 2
                         (hstack :views 3
                           (spacer)
                           (segmented :items ("Controls" "Text" "Styles" "Shortcuts") :selected "Controls")
                           (spacer))
                         (vstack :views 4
                           (vstack :views 2
                             (text "CHOICE" :color secondary-label :text-style subheadline :weight semibold)
                             (box :border line:1:separator :fill text-background
                               (vstack :views 2
                                 (hstack :views 3
                                   (image leaf.fill)
                                   (text "Fruit")
                                   (dropdown "Apple" :items ("Apple" "Banana" "Cherry")))
                                 (text "You picked Apple" :color accent))))
                           (vstack :views 2
                             (text "LEVEL" :color secondary-label :text-style subheadline :weight semibold)
                             (box :border line:1:separator :fill text-background
                               (vstack :views 2
                                 (hstack :views 3
                                   (image speaker.wave.2.fill)
                                   (slider :value 40.0)
                                   (text "40" :design monospaced-digits))
                                 (progress :value 40 :max 100))))
                           (vstack :views 2
                             (text "RANGES" :color secondary-label :text-style subheadline :weight semibold)
                             (box :border line:1:separator :fill text-background
                               (vstack :views 2
                                 (hstack :views 3
                                   (text "Gain")
                                   (slider :value -6.0)
                                   (text "-6" :design monospaced-digits))
                                 (hstack :views 3
                                   (text "Zoom")
                                   (slider :value 200.0)
                                   (text "200" :design monospaced-digits)))))
                           (vstack :views 2
                             (text "ACTIVITY" :color secondary-label :text-style subheadline :weight semibold)
                             (box :border line:1:separator :fill text-background
                               (hstack :views 2
                                 (checkbox "Working" :checked #f)
                                 (progress idle))))))
                       (shortcut)
                       (shortcut)))))
    (slide (slider 2) -13)
    (slide (slider 3) 750)
    (expect-text (text "-12") "-12")
    (expect-dump (window :width 560 :height 539
                   (vstack :views 1
                     (vstack :views 4
                       (hstack :views 2
                         (image square.grid.2x2.fill)
                         (vstack :views 2
                           (text "Gallery" :text-style title2 :weight semibold)
                           (text "Controls, typography, colors, and shortcuts" :color secondary-label :text-style caption1)))
                       (vstack :views 2
                         (hstack :views 3
                           (spacer)
                           (segmented :items ("Controls" "Text" "Styles" "Shortcuts") :selected "Controls")
                           (spacer))
                         (vstack :views 4
                           (vstack :views 2
                             (text "CHOICE" :color secondary-label :text-style subheadline :weight semibold)
                             (box :border line:1:separator :fill text-background
                               (vstack :views 2
                                 (hstack :views 3
                                   (image leaf.fill)
                                   (text "Fruit")
                                   (dropdown "Apple" :items ("Apple" "Banana" "Cherry")))
                                 (text "You picked Apple" :color accent))))
                           (vstack :views 2
                             (text "LEVEL" :color secondary-label :text-style subheadline :weight semibold)
                             (box :border line:1:separator :fill text-background
                               (vstack :views 2
                                 (hstack :views 3
                                   (image speaker.wave.2.fill)
                                   (slider :value 40.0)
                                   (text "40" :design monospaced-digits))
                                 (progress :value 40 :max 100))))
                           (vstack :views 2
                             (text "RANGES" :color secondary-label :text-style subheadline :weight semibold)
                             (box :border line:1:separator :fill text-background
                               (vstack :views 2
                                 (hstack :views 3
                                   (text "Gain")
                                   (slider :value -12.0)
                                   (text "-12" :design monospaced-digits))
                                 (hstack :views 3
                                   (text "Zoom")
                                   (slider :value 750.0)
                                   (text "750" :design monospaced-digits)))))
                           (vstack :views 2
                             (text "ACTIVITY" :color secondary-label :text-style subheadline :weight semibold)
                             (box :border line:1:separator :fill text-background
                               (hstack :views 2
                                 (checkbox "Working" :checked #f)
                                 (progress idle))))))
                       (shortcut)
                       (shortcut)))))))
