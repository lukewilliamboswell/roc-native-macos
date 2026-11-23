; Converted from tests/add-toggle-filter.script by scripts/convert_cases.roc.
(test "add-toggle-filter"
  (steps
    (fill (text-field) "Buy milk")
    (submit (text-field))
    (fill (text-field) "Walk the dog")
    (submit (text-field))
    (toggle (checkbox "Buy milk"))
    (choose "Done")
    (expect-dump """
      --- 480x392
      ui-vstack [1 views]
        ui-vstack [4 views]
          ui-hstack [3 views]
            ui-text "To-do" {text-style=large-title weight=bold}
            ui-spacer
            ui-text "1 item left" {color=secondary-label design=monospaced-digits text-style=subheadline}
          ui-form [1 views]
            ui-hstack [2 views]
              ui-text-field ""
              ui-button "Add"
          ui-vstack [2 views]
            ui-segmented All Open [Done]
            ui-box {border=line:1:separator}
              ui-scroll [1 views, 220pt high]
                ui-hstack [4 views]
                  ui-checkbox "Buy milk" [x]
                  ui-text "Buy milk" {color=secondary-label}
                  ui-spacer
                  ui-button "Remove"
          ui-shortcut
      """)
    (choose "Open")
    (expect-dump """
      --- 480x392
      ui-vstack [1 views]
        ui-vstack [4 views]
          ui-hstack [3 views]
            ui-text "To-do" {text-style=large-title weight=bold}
            ui-spacer
            ui-text "1 item left" {color=secondary-label design=monospaced-digits text-style=subheadline}
          ui-form [1 views]
            ui-hstack [2 views]
              ui-text-field ""
              ui-button "Add"
          ui-vstack [2 views]
            ui-segmented All [Open] Done
            ui-box {border=line:1:separator}
              ui-scroll [1 views, 220pt high]
                ui-hstack [4 views]
                  ui-checkbox "Walk the dog" [ ]
                  ui-text "Walk the dog"
                  ui-spacer
                  ui-button "Remove"
          ui-shortcut
      """)))
