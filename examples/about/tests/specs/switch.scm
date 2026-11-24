; The picture switches between its vector and bitmap assets.
(test "switch"
  (steps
    (expect-dump (window :width 360 :height 353
                   (vstack :views 1
                     (vstack :views 5
                       (box :fill adaptive:e8edf6:263246
                         (asset-image icon.png :pixels 1024x1024 :width 144 :height 116 :label "The chosen image"))
                       (text "About" :text-style title1 :weight semibold)
                       (text "Version 1.0" :color secondary-label :text-style callout)
                       (segmented :items ("Bitmap" "Vector") :selected "Bitmap")
                       (hstack :views 2
                         (asset-image mark.pdf :pixels 160x160 :width 14 :height 14)
                         (text "Images from assets/, beside src/" :color tertiary-label :text-style caption1))))))
    (choose "Vector")
    (expect-dump (window :width 360 :height 353
                   (vstack :views 1
                     (vstack :views 5
                       (box :fill adaptive:e8edf6:263246
                         (asset-image mark.pdf :pixels 160x160 :width 144 :height 116 :label "The chosen image"))
                       (text "About" :text-style title1 :weight semibold)
                       (text "Version 1.0" :color secondary-label :text-style callout)
                       (segmented :items ("Bitmap" "Vector") :selected "Vector")
                       (hstack :views 2
                         (asset-image mark.pdf :pixels 160x160 :width 14 :height 14)
                         (text "Images from assets/, beside src/" :color tertiary-label :text-style caption1))))))))
