; The README's demo of the file-inspector example: scripts/record_demos.roc
; records its window while these steps run, as
; docs/images/file-inspector.gif. A (demo …) is a spec with real effects and
; time, so `test` and the check parse it but never run it.
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
