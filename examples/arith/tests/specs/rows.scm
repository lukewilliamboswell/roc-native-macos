; Every row at n = 7, then at n = 8 after a click: the same text from every
; build of the app, whatever --opt and --specialize it was built with.
(test "rows"
  (steps
    (expect-visible (text "n 7"))
    (expect-dump (window :width 600 :height 584
                   (vstack :views 1
                     (vstack :views 2
                       (hstack :views 4
                         (text "Arithmetic" :text-style title2 :weight semibold)
                         (spacer)
                         (text "n 7" :design monospaced-digits :text-style headline)
                         (button "Next"))
                       (scroll :views 1 :height 490
                         (vstack :views 3
                           (box
                             (vstack :views 8
                               (text "Wide integers" :text-style headline)
                               (text "u128 129127595897592408799582697" :design monospaced :text-style callout)
                               (text "u128 / 10 = 12912759589759240879958269 rem 7" :design monospaced :text-style callout)
                               (text "i128 / 9 = -14347510655288045422175855 rem -2" :design monospaced :text-style callout)
                               (text "i128 parsed -129127595897592408799582697" :design monospaced :text-style callout)
                               (text "u128 << 91 339259825380873322007135609622714384384" :design monospaced :text-style callout)
                               (text "u128 >> 45 3670027010047" :design monospaced :text-style callout)
                               (text "i128 >> -3670027010048 >>> 137438953471" :design monospaced :text-style callout)))
                           (box
                             (vstack :views 9
                               (text "Decimal and floating point" :text-style headline)
                               (text "dec 2.333333333333333333 2.916666666666666666 2.0" :design monospaced :text-style callout)
                               (text "dec sqrt 2.64575131106459059 sin 0.656986598718789091" :design monospaced :text-style callout)
                               (text "dec pow 129.641814242164933888 rem 1.5" :design monospaced :text-style callout)
                               (text "f64 2.3333333333333335 1.5275252316519468 4.222411298698642" :design monospaced :text-style callout)
                               (text "f64 0.7230858817383246 -0.6907581397498764 -1.046800377915422" :design monospaced :text-style callout)
                               (text "f64 1.1659045405098132 0.4429110440736389 0.23333333333333361" :design monospaced :text-style callout)
                               (text "f32 2.3333333 1.5275252 4.222411" :design monospaced :text-style callout)
                               (text "f32 0.723086 -0.6907581 0.75092906 0.23333329" :design monospaced :text-style callout)))
                           (box
                             (vstack :views 9
                               (text "Conversions and collections" :text-style headline)
                               (text "to float 1.2912759589759241e26 -1.2912759589759241e26 1.291276e26" :design monospaced :text-style callout)
                               (text "from float 129127595897592409212583936 -712500000000000061865984" :design monospaced :text-style callout)
                               (text "parsed 7125" :design monospaced :text-style callout)
                               (text "rounded 2 3 2 2 -3" :design monospaced :text-style callout)
                               (text "dec rounded 2.0 3.0 -2.0" :design monospaced :text-style callout)
                               (text "bits 63 41 0" :design monospaced :text-style callout)
                               (text "pow 8193465725814765556554001028792218849 0" :design monospaced :text-style callout)
                               (text "list 21 sum 987 first 3,6,9,12,22" :design monospaced :text-style callout)))))))))
    (click (button "Next"))
    (expect-visible (text "n 8"))
    (expect-dump (window :width 600 :height 584
                   (vstack :views 1
                     (vstack :views 2
                       (hstack :views 4
                         (text "Arithmetic" :text-style title2 :weight semibold)
                         (spacer)
                         (text "n 8" :design monospaced-digits :text-style headline)
                         (button "Next"))
                       (scroll :views 1 :height 490
                         (vstack :views 3
                           (box
                             (vstack :views 8
                               (text "Wide integers" :text-style headline)
                               (text "u128 147574395311534181485237368" :design monospaced :text-style callout)
                               (text "u128 / 11 = 13415854119230380135021578 rem 10" :design monospaced :text-style callout)
                               (text "i128 / 10 = -14757439531153418148523736 rem -8" :design monospaced :text-style callout)
                               (text "i128 parsed -147574395311534181485237368" :design monospaced :text-style callout)
                               (text "u128 << 104 294862587891628229569440699213905133568" :design monospaced :text-style callout)
                               (text "u128 >> 52 32768098303" :design monospaced :text-style callout)
                               (text "i128 >> -32768098304 >>> 16777215" :design monospaced :text-style callout)))
                           (box
                             (vstack :views 9
                               (text "Decimal and floating point" :text-style headline)
                               (text "dec 2.666666666666666666 3.333333333333333332 3.0" :design monospaced :text-style callout)
                               (text "dec sqrt 2.828427124746190097 sin 0.989358246623381781" :design monospaced :text-style callout)
                               (text "dec pow 181.019335983756165376 rem 2.5" :design monospaced :text-style callout)
                               (text "f64 2.6666666666666665 1.632993161855452 5.298425654550918" :design monospaced :text-style callout)
                               (text "f64 0.457272626635812 -0.8893265682130413 -0.5141785289903434" :design monospaced :text-style callout)
                               (text "f64 1.2120256565243244 0.3843967744956391 0.5666666666666667" :design monospaced :text-style callout)
                               (text "f32 2.6666667 1.6329932 5.298426" :design monospaced :text-style callout)
                               (text "f32 0.45727256 -0.88932663 0.8176451 0.5666668" :design monospaced :text-style callout)))
                           (box
                             (vstack :views 9
                               (text "Conversions and collections" :text-style headline)
                               (text "to float 1.4757439531153418e26 -1.4757439531153418e26 1.47574395e26" :design monospaced :text-style callout)
                               (text "from float 147574395311534181957238784 -812499999999999952814080" :design monospaced :text-style callout)
                               (text "parsed 8125" :design monospaced :text-style callout)
                               (text "rounded 2 3 3 3 -3" :design monospaced :text-style callout)
                               (text "dec rounded 2.0 3.0 -2.0" :design monospaced :text-style callout)
                               (text "bits 62 41 3" :design monospaced :text-style callout)
                               (text "pow 45517159607903340355793714778287898624 0" :design monospaced :text-style callout)
                               (text "list 24 sum 1190 first 3,6,9,12,22" :design monospaced :text-style callout)))))))))))
