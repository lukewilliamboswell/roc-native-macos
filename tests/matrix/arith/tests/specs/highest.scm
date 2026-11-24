; Every count up to the highest the app allows, 12, each drawn without a
; crash, then every row at 12 with Next disabled: no count the button can
; reach overflows an operation that traps.
(test "highest"
  (steps
    (expect-visible (text "n 7"))
    (click (button "Next"))
    (expect-visible (text "n 8"))
    (click (button "Next"))
    (expect-visible (text "n 9"))
    (click (button "Next"))
    (expect-visible (text "n 10"))
    (click (button "Next"))
    (expect-visible (text "n 11"))
    (click (button "Next"))
    (expect-visible (text "n 12"))
    (expect-disabled (button "Next") true)
    (expect-dump (window :width 600 :height 584
                   (vstack :views 1
                     (vstack :views 2
                       (hstack :views 4
                         (text "Arithmetic" :text-style title2 :weight semibold)
                         (spacer)
                         (text "n 12" :design monospaced-digits :text-style headline)
                         (button "Next" :enabled #f))
                       (scroll :views 1 :height 490
                         (vstack :views 3
                           (box
                             (vstack :views 8
                               (text "Wide integers" :text-style headline)
                               (text "u128 221361592967301272227856052" :design monospaced :text-style callout)
                               (text "u128 / 15 = 14757439531153418148523736 rem 12" :design monospaced :text-style callout)
                               (text "i128 / 14 = -15811542354807233730561146 rem -8" :design monospaced :text-style callout)
                               (text "i128 parsed -221361592967301272227856052" :design monospaced :text-style callout)
                               (text "u128 << 28 59421300149063910099864675220979712" :design monospaced :text-style callout)
                               (text "u128 >> 14 13510839414508134291250" :design monospaced :text-style callout)
                               (text "i128 >> -13510839414508134291251 >>> 1267650600227404765301970042882" :design monospaced :text-style callout)))
                           (box
                             (vstack :views 9
                               (text "Decimal and floating point" :text-style headline)
                               (text "dec 4.0 5.0 4.0" :design monospaced :text-style callout)
                               (text "dec sqrt 3.464101615137754587 sin -0.536572918000434966" :design monospaced :text-style callout)
                               (text "dec pow 498.830632579836643072 rem 1.0" :design monospaced :text-style callout)
                               (text "f64 4 2 10.556063286183154" :design monospaced :text-style callout)
                               (text "f64 -0.7568024953079282 -0.6536436208636119 1.1578212823495777" :design monospaced :text-style callout)
                               (text "f64 1.3258176636680326 0.25268025514207865 0.5000000000000002" :design monospaced :text-style callout)
                               (text "f32 4 2 10.556065" :design monospaced :text-style callout)
                               (text "f32 -0.7568025 -0.65364367 1.012197 0.50000006" :design monospaced :text-style callout)))
                           (box
                             (vstack :views 9
                               (text "Conversions and collections" :text-style headline)
                               (text "to float 2.2136159296730127e26 -2.2136159296730127e26 2.213616e26" :design monospaced :text-style callout)
                               (text "from float 221361592967301272935858176 -1212500000000000053477376" :design monospaced :text-style callout)
                               (text "parsed 12125" :design monospaced :text-style callout)
                               (text "rounded 4 4 4 4 -4" :design monospaced :text-style callout)
                               (text "dec rounded 4.0 4.0 -4.0" :design monospaced :text-style callout)
                               (text "bits 64 40 2" :design monospaced :text-style callout)
                               (text "pow 1329227995784915872903807060280344576 overflow 0" :design monospaced :text-style callout)
                               (text "list 36 sum 1854 first 3,6,9,12,15" :design monospaced :text-style callout)))))))))))
