; Reset puts the count back to 0, whatever it was.
(test "reset"
  (steps
    (click (button "+"))
    (click (button "+"))
    (expect-visible (text "2"))
    (click (button "Reset"))
    (expect-visible (text "0"))
    (expect-dump """
      --- 360x237
      ui-vstack [1 views]
        ui-vstack [4 views]
          ui-text "Counter" {color=secondary-label text-style=headline}
          ui-text "0" {design=monospaced-digits font-size=64 weight=light}
          ui-hstack [3 views]
            ui-button "−"
            ui-button "Reset"
            ui-button "+"
          ui-text "Each click is one engine turn." {color=tertiary-label text-style=caption1}
      """)))
