; Converted from tests/switch.script by scripts/convert_cases.roc.
(test "switch"
  (steps
    (expect-dump """
      --- 360x325
      ui-vstack [1 views]
        ui-vstack [5 views]
          ui-asset-image icon.png [1024x1024, 128pt wide, 128pt high] {label=The chosen image}
          ui-text "About" {text-style=title1 weight=semibold}
          ui-text "Version 1.0" {color=secondary-label text-style=callout}
          ui-segmented [Bitmap] Vector
          ui-hstack [2 views]
            ui-asset-image mark.pdf [160x160, 14pt wide, 14pt high]
            ui-text "Images from assets/, beside main.roc" {color=tertiary-label text-style=caption1}
      """)
    (choose "Vector")
    (expect-dump """
      --- 360x325
      ui-vstack [1 views]
        ui-vstack [5 views]
          ui-asset-image mark.pdf [160x160, 128pt wide, 128pt high] {label=The chosen image}
          ui-text "About" {text-style=title1 weight=semibold}
          ui-text "Version 1.0" {color=secondary-label text-style=callout}
          ui-segmented Bitmap [Vector]
          ui-hstack [2 views]
            ui-asset-image mark.pdf [160x160, 14pt wide, 14pt high]
            ui-text "Images from assets/, beside main.roc" {color=tertiary-label text-style=caption1}
      """)))
