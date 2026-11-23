; Each click is one engine turn: three up and one down leave 2.
(test "increment"
  (steps
    (expect-visible (text "0"))
    (click (button "+"))
    (click (button "+"))
    (click (button "+"))
    (click (button "−"))
    (expect-visible (text "2"))
    (expect-absent (text "0"))
    (expect-dump """
      --- 360x237
      ui-vstack [1 views]
        ui-vstack [4 views]
          ui-text "Counter" {color=secondary-label text-style=headline}
          ui-text "2" {design=monospaced-digits font-size=64 weight=light}
          ui-hstack [3 views]
            ui-button "−"
            ui-button "Reset"
            ui-button "+"
          ui-text "Each click is one engine turn." {color=tertiary-label text-style=caption1}
      """)))
