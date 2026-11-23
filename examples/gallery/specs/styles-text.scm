; Converted from tests/styles-text.script by scripts/convert_cases.roc.
(test "styles-text"
  (steps
    (choose "Styles")
    (expect-dump """
      --- 560x424
      ui-vstack [1 views]
        ui-vstack [4 views]
          ui-hstack [2 views]
            ui-image square.grid.2x2.fill
            ui-vstack [2 views]
              ui-text "Gallery" {text-style=title2 weight=semibold}
              ui-text "Native AppKit controls driven by the roc-signals engine" {color=secondary-label text-style=caption1}
          ui-vstack [2 views]
            ui-hstack [3 views]
              ui-spacer
              ui-segmented Controls Text [Styles] Shortcuts
              ui-spacer
            ui-vstack [2 views]
              ui-vstack [2 views]
                ui-text "TEXT STYLES" {color=secondary-label text-style=subheadline weight=semibold}
                ui-box {border=line:1:separator}
                  ui-vstack [6 views]
                    ui-text "Large Title" {text-style=large-title}
                    ui-text "Title 1" {text-style=title1}
                    ui-text "Headline" {text-style=headline}
                    ui-text "Body, the default"
                    ui-text "Caption, in the secondary label colour" {color=secondary-label text-style=caption1}
                    ui-text "Monospaced 0123456789" {design=monospaced}
              ui-vstack [2 views]
                ui-text "COLOURS" {color=secondary-label text-style=subheadline weight=semibold}
                ui-box {border=line:1:separator}
                  ui-vstack [2 views]
                    ui-hstack [10 views]
                      ui-hover
                        ui-box {fill=red}
                          ui-spacer
                      ui-hover
                        ui-box {fill=orange}
                          ui-spacer
                      ui-hover
                        ui-box {fill=yellow}
                          ui-spacer
                      ui-hover
                        ui-box {fill=green}
                          ui-spacer
                      ui-hover
                        ui-box {fill=teal}
                          ui-spacer
                      ui-hover
                        ui-box {fill=blue}
                          ui-spacer
                      ui-hover
                        ui-box {fill=indigo}
                          ui-spacer
                      ui-hover
                        ui-box {fill=purple}
                          ui-spacer
                      ui-hover
                        ui-box {fill=pink}
                          ui-spacer
                      ui-hover
                        ui-box {fill=adaptive:24404b:9fc3cf}
                          ui-spacer
                    ui-text "Point at a colour to name it" {color=secondary-label text-style=caption1}
          ui-shortcut
          ui-shortcut
      """)
    (choose "Text")
    (fill (text-area) "Hello\nworld")
    (expect-dump """
      --- 560x336
      ui-vstack [1 views]
        ui-vstack [4 views]
          ui-hstack [2 views]
            ui-image square.grid.2x2.fill
            ui-vstack [2 views]
              ui-text "Gallery" {text-style=title2 weight=semibold}
              ui-text "Native AppKit controls driven by the roc-signals engine" {color=secondary-label text-style=caption1}
          ui-vstack [2 views]
            ui-hstack [3 views]
              ui-spacer
              ui-segmented Controls [Text] Styles Shortcuts
              ui-spacer
            ui-vstack [2 views]
              ui-text "NOTES" {color=secondary-label text-style=subheadline weight=semibold}
              ui-box {border=line:1:separator}
                ui-vstack [2 views]
                  ui-text-area "Hello\nworld"
                  ui-text "2 lines, 11 bytes" {color=secondary-label text-style=caption1}
          ui-shortcut
          ui-shortcut
      """)))
