; Record dropping and inspecting files, then clearing the list.
; Used by scripts/record_demos.roc.
(demo "file-inspector demo"
  (setup
    (live-effects))
  (steps
    (window)
    (wait 900)
    (drop "/usr/share/dict/README") (wait 800)
    (drop "/usr/share/dict/web2") (wait 1000)
    (click (button "Inspect" 1)) (wait 2800)
    (click (button "Clear")) (wait 1200)))
