; Converted from tests/closed-port.script by scripts/convert_cases.roc.
(test "closed-port"
  (steps
    (fill (text-field) "http://127.0.0.1:9/")
    (click (button "Fetch"))
    (wait 1500)
    (expect-dump """
      --- 560x221
      ui-vstack [1 views]
        ui-vstack [6 views]
          ui-text "HTTP fetch" {text-style=title2 weight=semibold}
          ui-form [1 views]
            ui-hstack [4 views]
              ui-image globe
              ui-text-field "http://127.0.0.1:9/"
              ui-button "Fetch"
              ui-button "Cancel" (disabled)
          ui-checkbox "Time out after 2 s" [ ]
          ui-divider
          ui-hstack [2 views]
            ui-box {fill=orange}
              ui-text "NETWORK" {color=adaptive:ffffff:ffffff text-style=caption1 weight=bold}
            ui-text "#1: Could not connect to the server." {color=secondary-label}
          ui-box {border=line:1:separator fill=text-background}
            ui-text "The start of the body appears here." {color=tertiary-label design=monospaced text-style=callout}
      """)))
