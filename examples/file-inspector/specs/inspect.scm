; Converted from tests/inspect.script by scripts/convert_cases.roc.
(test "inspect"
  (steps
    (files "specs/fixtures/hello.txt")
    (click (button "Inspect"))
    (wait 500)
    (expect-dump """
      --- <size>
      ui-vstack [1 views]
        ui-vstack [5 views]
          ui-hstack [4 views]
            ui-text "File inspector" {text-style=title2 weight=semibold}
            ui-spacer
            ui-file-button "Choose Files…"
            ui-button "Clear"
          ui-drop-zone
            ui-vstack [3 views]
              ui-image arrow.down.doc
              ui-text "Drop files here" {color=secondary-label text-style=headline}
              ui-text "The app holds each file as a handle, never its bytes." {color=tertiary-label text-style=caption1}
          ui-text "1 file" {color=secondary-label text-style=caption1}
          ui-box {border=line:1:separator}
            ui-vstack [1 views]
              ui-hstack [4 views]
                ui-image doc
                ui-vstack [2 views]
                  ui-text "hello.txt"
                  ui-text "21 bytes · text/plain" {color=secondary-label text-style=caption1}
                ui-spacer
                ui-button "Inspect"
          ui-box {border=line:1:separator}
            ui-vstack [5 views]
              ui-hstack [4 views]
                ui-image doc.text.magnifyingglass
                ui-text "hello.txt" {text-style=headline}
                ui-spacer
                ui-button "Save Copy…"
              ui-divider
              ui-hstack [2 views]
                ui-text "SHA-256" {color=secondary-label text-style=caption1}
                ui-text "86501f780e3b0baedf53a16cae80a0defcffb5ce1bb167c09ebf9c4f2e669c87" {design=monospaced text-style=callout}
              ui-hstack [2 views]
                ui-text "Starts" {color=secondary-label text-style=caption1}
                ui-text "hello from a fixture" {design=monospaced text-style=callout}
              ui-hstack [2 views]
                ui-text "URL" {color=secondary-label text-style=caption1}
                ui-text "file://<app>/specs/fixtures/hello.txt" {design=monospaced text-style=callout}
      """)))
