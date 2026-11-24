; The player on a screen with room for only 760 by 560 points: the window
; keeps within it, and the editor, the tallest panel, scrolls in its own
; area rather than push the window past the screen. What still does not
; fit scrolls with the whole window (the dump's :content-height), so the
; transport, the panel switcher and the editor's last controls are all
; there to reach.
(test "small-screen"
  (steps
    (screen-size 760 560)
    (choose "Editor")
    (frame)
    (expect-visible (button "Next"))
    (expect-visible (button "Export…"))
    (expect-dump (window :width 760 :height 560 :content-height 711
                   (vstack :views 1
                     (vstack :views 9
                       (hstack :views 6
                         (asset-image icon.png :pixels 512x512 :width 30 :height 30)
                         (text "Music" :text-style title2 :weight bold)
                         (text "Polymorphic Defunctionalization Through Lambda Set Specialization" :color secondary-label :text-style title3)
                         (spacer)
                         (hstack :views 2
                           (text "" :color red :text-style caption1)
                           (file-button "Add lyrics…"))
                         (checkbox "Lyrics" :checked #f))
                       (hstack :views 2
                         (drop-zone
                           (overlay
                             (surface "Visualizer" :width 506 :height 332 :pacing display :ticking #t :trail held :shader fallback
                               (space :fit 1000.0 1000.0 :scale 0.332 :offset 87.0 0.0)
                               (save)
                               (transform 1.000 0.000 0.000 1.000 500.000 500.000)
                               (transform 1.000 0.000 0.000 1.000 0.000 0.000)
                               (transform 0.467 0.000 0.000 0.467 0.000 0.000)
                               (opacity 1.000)
                               (opacity 1.000)
                               (stroke adaptive:ff3fc8:ff3fc8 24.0 0.0,-150.0 150.0,0.0 0.0,150.0 -150.0,0.0 0.0,-150.0 close)
                               (restore)
                               (save)
                               (transform 1.000 0.000 0.000 1.000 500.000 500.000)
                               (transform 1.000 0.000 0.000 1.000 0.000 0.000)
                               (transform 0.462 0.000 0.000 0.462 0.000 0.000)
                               (opacity 1.000)
                               (opacity 1.000)
                               (stroke adaptive:22e0d0:22e0d0 24.0 0.0,-130.0 130.0,0.0 0.0,130.0 -130.0,0.0 0.0,-130.0 close)
                               (restore)
                               (save)
                               (transform 1.000 0.000 0.000 1.000 500.000 500.000)
                               (transform 1.000 0.000 0.000 1.000 0.000 0.000)
                               (transform 0.417 0.000 0.000 0.417 0.000 0.000)
                               (opacity 1.000)
                               (opacity 1.000)
                               (stroke adaptive:ff9a2a:ff9a2a 24.0 0.0,-120.0 120.0,0.0 0.0,120.0 -120.0,0.0 0.0,-120.0 close)
                               (restore))
                             (vstack :views 0)))
                         (vstack :views 4
                           (hstack :views 3
                             (text "Presets" :text-style headline)
                             (spacer)
                             (text "Simple visuals" :color secondary-label :text-style caption1))
                           (text "Using Orb Garden" :color secondary-label :text-style caption1)
                           (box :border line:1:separator :fill text-background
                             (scroll :views 16 :height 190
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Scope"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Spectrum Bars"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Echo Rings"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Liquid Drift"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Blur Corridor"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Superscope Bloom"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Flux Streaks"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Phase Scope"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Peak Meter"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Plasma Weave"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Hyperspace"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Mirror Shard"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Spectrum Fire"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Ripple Pool"))
                               (hstack :views 2
                                 (text "●" :color accent)
                                 (button "Orb Garden"))
                               (hstack :views 2
                                 (text "" :color accent)
                                 (button "Sync Test"))))
                           (hstack :views 3
                             (button "New")
                             (button "Duplicate")
                             (button "Edit"))))
                       (box :border line:1:separator
                         (hstack :views 8
                           (text "0:00 / 2:59" :design monospaced-digits :weight medium)
                           (slider :value 0.0)
                           (button "Previous")
                           (button "Play")
                           (button "Stop")
                           (button "Next")
                           (image speaker.wave.2.fill)
                           (slider :value 100.0)))
                       (segmented :items ("Hide Panels" "Queue" "EQ" "Editor") :selected "Editor")
                       (scroll :views 1 :height 160
                         (vstack :views 1
                           (vstack :views 8
                             (hstack :views 4
                               (text "Preset" :text-style headline)
                               (text-field "Orb Garden")
                               (button "Save As")
                               (button "Delete…" :enabled #f))
                             (vstack :views 1
                               (vstack :views 2
                                 (hstack :views 3
                                   (text "Layer 1" :text-style subheadline :weight semibold)
                                   (spacer)
                                   (button "Hide Layer 1"))
                                 (vstack :views 5
                                   (hstack :views 4
                                     (dropdown "Ring" :items ("Waveform" "Circular waveform" "Spectrum bars" "Ring" "Lissajous"))
                                     (dropdown "Custom" :items ("Phosphor" "Amber" "Ice" "Orchid" "Paper" "Custom"))
                                     (spacer)
                                     (button "Remove Layer 1"))
                                   (hstack :views 3
                                     (text "Size" :color secondary-label :text-style caption1)
                                     (slider :value 90.0)
                                     (text "90" :design monospaced-digits :text-style caption1))
                                   (hstack :views 3
                                     (text "Thickness" :color secondary-label :text-style caption1)
                                     (slider :value 60.0)
                                     (text "60" :design monospaced-digits :text-style caption1))
                                   (hstack :views 3
                                     (text "Opacity" :color secondary-label :text-style caption1)
                                     (slider :value 100.0)
                                     (text "100" :design monospaced-digits :text-style caption1))
                                   (vstack :views 2
                                     (vstack :views 3
                                       (hstack :views 3
                                         (text "Band 3 → Size, 70 to 150" :text-style caption1)
                                         (spacer)
                                         (button "Remove Mapping 1.1"))
                                       (hstack :views 3
                                         (text "From" :color secondary-label :text-style caption1)
                                         (slider :value 70.0)
                                         (text "70" :design monospaced-digits :text-style caption1))
                                       (hstack :views 3
                                         (text "To" :color secondary-label :text-style caption1)
                                         (slider :value 150.0)
                                         (text "150" :design monospaced-digits :text-style caption1)))
                                     (dropdown "Add Mapping" :items ("Add Mapping" "Level → Size" "Level → Thickness" "Level → Opacity" "Level → Brightness" "Level → Rotation" "Bass → Size" "Bass → Thickness" "Bass → Opacity" "Bass → Brightness" "Bass → Rotation" "Mids → Size" "Mids → Thickness" "Mids → Opacity" "Mids → Brightness" "Mids → Rotation" "Treble → Size" "Treble → Thickness" "Treble → Opacity" "Treble → Brightness" "Treble → Rotation"))))))
                             (vstack :views 1
                               (vstack :views 2
                                 (hstack :views 3
                                   (text "Layer 2" :text-style subheadline :weight semibold)
                                   (spacer)
                                   (button "Hide Layer 2"))
                                 (vstack :views 5
                                   (hstack :views 4
                                     (dropdown "Ring" :items ("Waveform" "Circular waveform" "Spectrum bars" "Ring" "Lissajous"))
                                     (dropdown "Custom" :items ("Phosphor" "Amber" "Ice" "Orchid" "Paper" "Custom"))
                                     (spacer)
                                     (button "Remove Layer 2"))
                                   (hstack :views 3
                                     (text "Size" :color secondary-label :text-style caption1)
                                     (slider :value 75.0)
                                     (text "75" :design monospaced-digits :text-style caption1))
                                   (hstack :views 3
                                     (text "Thickness" :color secondary-label :text-style caption1)
                                     (slider :value 60.0)
                                     (text "60" :design monospaced-digits :text-style caption1))
                                   (hstack :views 3
                                     (text "Opacity" :color secondary-label :text-style caption1)
                                     (slider :value 100.0)
                                     (text "100" :design monospaced-digits :text-style caption1))
                                   (vstack :views 2
                                     (vstack :views 3
                                       (hstack :views 3
                                         (text "Band 10 → Size, 60 to 130" :text-style caption1)
                                         (spacer)
                                         (button "Remove Mapping 2.1"))
                                       (hstack :views 3
                                         (text "From" :color secondary-label :text-style caption1)
                                         (slider :value 60.0)
                                         (text "60" :design monospaced-digits :text-style caption1))
                                       (hstack :views 3
                                         (text "To" :color secondary-label :text-style caption1)
                                         (slider :value 130.0)
                                         (text "130" :design monospaced-digits :text-style caption1)))
                                     (dropdown "Add Mapping" :items ("Add Mapping" "Level → Size" "Level → Thickness" "Level → Opacity" "Level → Brightness" "Level → Rotation" "Bass → Size" "Bass → Thickness" "Bass → Opacity" "Bass → Brightness" "Bass → Rotation" "Mids → Size" "Mids → Thickness" "Mids → Opacity" "Mids → Brightness" "Mids → Rotation" "Treble → Size" "Treble → Thickness" "Treble → Opacity" "Treble → Brightness" "Treble → Rotation"))))))
                             (vstack :views 1
                               (vstack :views 2
                                 (hstack :views 3
                                   (text "Layer 3" :text-style subheadline :weight semibold)
                                   (spacer)
                                   (button "Hide Layer 3"))
                                 (vstack :views 5
                                   (hstack :views 4
                                     (dropdown "Ring" :items ("Waveform" "Circular waveform" "Spectrum bars" "Ring" "Lissajous"))
                                     (dropdown "Custom" :items ("Phosphor" "Amber" "Ice" "Orchid" "Paper" "Custom"))
                                     (spacer)
                                     (button "Remove Layer 3"))
                                   (hstack :views 3
                                     (text "Size" :color secondary-label :text-style caption1)
                                     (slider :value 65.0)
                                     (text "65" :design monospaced-digits :text-style caption1))
                                   (hstack :views 3
                                     (text "Thickness" :color secondary-label :text-style caption1)
                                     (slider :value 60.0)
                                     (text "60" :design monospaced-digits :text-style caption1))
                                   (hstack :views 3
                                     (text "Opacity" :color secondary-label :text-style caption1)
                                     (slider :value 100.0)
                                     (text "100" :design monospaced-digits :text-style caption1))
                                   (vstack :views 2
                                     (vstack :views 3
                                       (hstack :views 3
                                         (text "Band 17 → Size, 50 to 120" :text-style caption1)
                                         (spacer)
                                         (button "Remove Mapping 3.1"))
                                       (hstack :views 3
                                         (text "From" :color secondary-label :text-style caption1)
                                         (slider :value 50.0)
                                         (text "50" :design monospaced-digits :text-style caption1))
                                       (hstack :views 3
                                         (text "To" :color secondary-label :text-style caption1)
                                         (slider :value 120.0)
                                         (text "120" :design monospaced-digits :text-style caption1)))
                                     (dropdown "Add Mapping" :items ("Add Mapping" "Level → Size" "Level → Thickness" "Level → Opacity" "Level → Brightness" "Level → Rotation" "Bass → Size" "Bass → Thickness" "Bass → Opacity" "Bass → Brightness" "Bass → Rotation" "Mids → Size" "Mids → Thickness" "Mids → Opacity" "Mids → Brightness" "Mids → Rotation" "Treble → Size" "Treble → Thickness" "Treble → Opacity" "Treble → Brightness" "Treble → Rotation"))))))
                             (hstack :views 4
                               (dropdown "Add Layer" :items ("Add Layer" "Waveform" "Circular waveform" "Spectrum bars" "Ring" "Lissajous"))
                               (spacer)
                               (file-button "Import…")
                               (button "Export…"))
                             (vstack :views 2
                               (checkbox "Feedback" :checked #t)
                               (vstack :views 2
                                 (hstack :views 3
                                   (text "Zoom ‰" :color secondary-label :text-style caption1)
                                   (slider :value 1050.0)
                                   (text "1050" :design monospaced-digits :text-style caption1))
                                 (hstack :views 3
                                   (text "Half-life" :color secondary-label :text-style caption1)
                                   (slider :value 450.0)
                                   (text "450 ms" :design monospaced-digits :text-style caption1))))
                             (vstack :views 6
                               (text "Shader params" :text-style subheadline :weight semibold)
                               (vstack :views 2
                                 (hstack :views 4
                                   (text "decay" :design monospaced :text-style caption1 :weight semibold)
                                   (text "how long the orbs' liquid trails last" :color secondary-label :text-style caption1)
                                   (spacer)
                                   (dropdown "Fixed" :items ("Fixed" "Level" "Bass" "Mids" "Treble" "Band 1" "Band 2" "Band 3" "Band 4" "Band 5" "Band 6" "Band 7" "Band 8" "Band 9" "Band 10" "Band 11" "Band 12" "Band 13" "Band 14" "Band 15" "Band 16" "Band 17" "Band 18" "Band 19" "Band 20" "Band 21" "Band 22" "Band 23" "Band 24")))
                                 (hstack :views 2
                                   (slider :value 692.0)
                                   (text "0.94" :design monospaced-digits :text-style caption1)))
                               (vstack :views 2
                                 (hstack :views 4
                                   (text "size" :design monospaced :text-style caption1 :weight semibold)
                                   (text "an orb's size at rest, in half-heights" :color secondary-label :text-style caption1)
                                   (spacer)
                                   (dropdown "Fixed" :items ("Fixed" "Level" "Bass" "Mids" "Treble" "Band 1" "Band 2" "Band 3" "Band 4" "Band 5" "Band 6" "Band 7" "Band 8" "Band 9" "Band 10" "Band 11" "Band 12" "Band 13" "Band 14" "Band 15" "Band 16" "Band 17" "Band 18" "Band 19" "Band 20" "Band 21" "Band 22" "Band 23" "Band 24")))
                                 (hstack :views 2
                                   (slider :value 400.0)
                                   (text "0.11" :design monospaced-digits :text-style caption1)))
                               (vstack :views 2
                                 (hstack :views 4
                                   (text "swell" :design monospaced :text-style caption1 :weight semibold)
                                   (text "how far the orbs swell with their bands" :color secondary-label :text-style caption1)
                                   (spacer)
                                   (dropdown "Level" :items ("Fixed" "Level" "Bass" "Mids" "Treble" "Band 1" "Band 2" "Band 3" "Band 4" "Band 5" "Band 6" "Band 7" "Band 8" "Band 9" "Band 10" "Band 11" "Band 12" "Band 13" "Band 14" "Band 15" "Band 16" "Band 17" "Band 18" "Band 19" "Band 20" "Band 21" "Band 22" "Band 23" "Band 24")))
                                 (hstack :views 2
                                   (slider :value 0.0)
                                   (text "0.2–0.8" :design monospaced-digits :text-style caption1)))
                               (vstack :views 1
                                 (vstack :views 2
                                   (hstack :views 3
                                     (text "Warp" :text-style subheadline :weight semibold)
                                     (spacer)
                                     (button "Hide Warp"))
                                   (text-area "// Where orb `i` is at time `t`: each wanders on its own slow figure.\nfloat2 orb_at(int i, float t) {\n    float fi = float(i);\n    return float2(sin(t * 0.29 * (1.0 + fi * 0.21) + fi * 1.7) * 1.05,\n                  cos(t * 0.23 * (1.0 + fi * 0.17) + fi * 2.9) * 0.62);\n}\n\n// Orb Garden's warp: the old picture drifts on slow noise and fades,\n// leaving liquid trails, and six metaballs are drawn over it: their\n// fields add, so near each other they merge, and each is coloured by\n// how much of the field is its own.\nfloat4 warp(Frame f, Params p) {\n    float k = min(f.dt * 60.0, 4.0);\n    float2 c = centered(f);\n    float2 drift = float2(noise(c * 2.2 + f.time * 0.2), noise(c * 2.2 - f.time * 0.17 + 9.0)) - 0.5;\n    float3 old = sample(f, uv_of(f, c + drift * 0.008 * k)).rgb * pow(p.decay, k) - 1.0 / 255.0;\n    float3 colours[3] = { float3(1.0, 0.22, 0.78), float3(0.12, 0.9, 0.82), float3(1.0, 0.58, 0.15) };\n    float field = 0.0;\n    float3 tint = float3(0.0);\n    for (int i = 0; i < 6; i++) {\n        float r = p.size * (0.7 + p.swell * band_at(f, i * 4 + 1));\n        float2 off = c - orb_at(i, f.time);\n        float w = r * r / (dot(off, off) + 1e-4);\n        field += w;\n        tint += w * colours[i % 3];\n    }\n    tint /= max(field, 1e-4);\n    float body = smoothstep(0.8, 1.3, field);\n    float halo = saturate(field * 0.35) * (1.0 - body);\n    float3 col = max(old, tint * (body * 0.85 + halo * 0.5));\n    // A bright rim where the surface of the merged blob is.\n    col += tint * smoothstep(0.25, 0.0, abs(field - 1.0)) * 0.35;\n    return opaque(col);\n}")))
                               (vstack :views 1
                                 (vstack :views 2
                                   (hstack :views 3
                                     (text "Composite" :text-style subheadline :weight semibold)
                                     (spacer)
                                     (button "Hide Composite"))
                                   (text-area "// Where star `i` is: a slow drift across the whole surface.\nfloat2 star_at(int i, float t) {\n    float fi = float(i);\n    return float2(sin(t * 0.07 * (1.0 + fi * 0.3) + fi * 2.1) * 1.4, cos(t * 0.09 * (1.0 + fi * 0.2) + fi * 1.3) * 0.8);\n}\n\n// Orb Garden's screen: deep purple behind, the orbs with a bloom, and\n// five spiky stars whose points lengthen with the treble.\nfloat4 composite(Frame f, Params p) {\n    float2 c = centered(f);\n    float3 col = mix(float3(0.09, 0.02, 0.16), float3(0.03, 0.0, 0.07), length(c) * 0.6);\n    float3 orbs = sample(f, f.uv).rgb + blur(f, f.uv, 10.0).rgb * 0.6;\n    col += orbs;\n    for (int i = 0; i < 5; i++) {\n        float2 off = c - star_at(i, f.time);\n        // Far from a star its glow is nothing: skip the costly part.\n        if (dot(off, off) > 0.5) continue;\n        float2 ra = polar(off);\n        // cos^24 by squaring, much cheaper than pow.\n        float s = cos(ra.y * 3.0 + f.time * (0.3 + 0.1 * float(i)));\n        s *= s; s *= s; s *= s;\n        float points = s * s * s;\n        float reach = 0.012 + (0.05 + 0.12 * f.treble) * points;\n        float glow = exp(-ra.x / reach) * (0.6 + 0.4 * sin(f.time * 2.0 + float(i) * 1.9));\n        float3 tint = (i % 2 == 0) ? float3(1.0, 0.75, 0.4) : float3(0.5, 1.0, 0.95);\n        col += tint * glow * 0.9;\n    }\n    return opaque(1.0 - exp(-col * 1.5));\n}"))))
                             (vstack :views 2
                               (hstack :views 3
                                 (text "File" :text-style subheadline :weight semibold)
                                 (spacer)
                                 (button "Hide File"))
                               (text-area "{\n  \"format\": \"roc-music-preset\",\n  \"version\": 1,\n  \"id\": \"builtin.orb-garden\",\n  \"name\": \"Orb Garden\",\n  \"background\": \"#12051F\",\n  \"layers\": [\n    {\n      \"type\": \"ring\",\n      \"colors\": [\"#FF3FC8\"],\n      \"size\": 90,\n      \"thickness\": 60,\n      \"opacity\": 100,\n      \"brightness\": 100,\n      \"rotation\": 0,\n      \"mappings\": [\n        {\n          \"feature\": \"band-2\",\n          \"property\": \"size\",\n          \"from\": 70,\n          \"to\": 150\n        }\n      ]\n    },\n    {\n      \"type\": \"ring\",\n      \"colors\": [\"#22E0D0\"],\n      \"size\": 75,\n      \"thickness\": 60,\n      \"opacity\": 100,\n      \"brightness\": 100,\n      \"rotation\": 0,\n      \"mappings\": [\n        {\n          \"feature\": \"band-9\",\n          \"property\": \"size\",\n          \"from\": 60,\n          \"to\": 130\n        }\n      ]\n    },\n    {\n      \"type\": \"ring\",\n      \"colors\": [\"#FF9A2A\"],\n      \"size\": 65,\n      \"thickness\": 60,\n      \"opacity\": 100,\n      \"brightness\": 100,\n      \"rotation\": 0,\n      \"mappings\": [\n        {\n          \"feature\": \"band-16\",\n          \"property\": \"size\",\n          \"from\": 50,\n          \"to\": 120\n        }\n      ]\n    }\n  ],\n  \"feedback\": {\n    \"enabled\": true,\n    \"zoom\": 1050,\n    \"rotation\": 14,\n    \"half_life_ms\": 450\n  },\n  \"shaders\": {\n    \"warp\": \"// Where orb `i` is at time `t`: each wanders on its own slow figure.\\nfloat2 orb_at(int i, float t) {\\n    float fi = float(i);\\n    return float2(sin(t * 0.29 * (1.0 + fi * 0.21) + fi * 1.7) * 1.05,\\n                  cos(t * 0.23 * (1.0 + fi * 0.17) + fi * 2.9) * 0.62);\\n}\\n\\n// Orb Garden's warp: the old picture drifts on slow noise and fades,\\n// leaving liquid trails, and six metaballs are drawn over it: their\\n// fields add, so near each other they merge, and each is coloured by\\n// how much of the field is its own.\\nfloat4 warp(Frame f, Params p) {\\n    float k = min(f.dt * 60.0, 4.0);\\n    float2 c = centered(f);\\n    float2 drift = float2(noise(c * 2.2 + f.time * 0.2), noise(c * 2.2 - f.time * 0.17 + 9.0)) - 0.5;\\n    float3 old = sample(f, uv_of(f, c + drift * 0.008 * k)).rgb * pow(p.decay, k) - 1.0 / 255.0;\\n    float3 colours[3] = { float3(1.0, 0.22, 0.78), float3(0.12, 0.9, 0.82), float3(1.0, 0.58, 0.15) };\\n    float field = 0.0;\\n    float3 tint = float3(0.0);\\n    for (int i = 0; i < 6; i++) {\\n        float r = p.size * (0.7 + p.swell * band_at(f, i * 4 + 1));\\n        float2 off = c - orb_at(i, f.time);\\n        float w = r * r / (dot(off, off) + 1e-4);\\n        field += w;\\n        tint += w * colours[i % 3];\\n    }\\n    tint /= max(field, 1e-4);\\n    float body = smoothstep(0.8, 1.3, field);\\n    float halo = saturate(field * 0.35) * (1.0 - body);\\n    float3 col = max(old, tint * (body * 0.85 + halo * 0.5));\\n    // A bright rim where the surface of the merged blob is.\\n    col += tint * smoothstep(0.25, 0.0, abs(field - 1.0)) * 0.35;\\n    return opaque(col);\\n}\",\n    \"composite\": \"// Where star `i` is: a slow drift across the whole surface.\\nfloat2 star_at(int i, float t) {\\n    float fi = float(i);\\n    return float2(sin(t * 0.07 * (1.0 + fi * 0.3) + fi * 2.1) * 1.4, cos(t * 0.09 * (1.0 + fi * 0.2) + fi * 1.3) * 0.8);\\n}\\n\\n// Orb Garden's screen: deep purple behind, the orbs with a bloom, and\\n// five spiky stars whose points lengthen with the treble.\\nfloat4 composite(Frame f, Params p) {\\n    float2 c = centered(f);\\n    float3 col = mix(float3(0.09, 0.02, 0.16), float3(0.03, 0.0, 0.07), length(c) * 0.6);\\n    float3 orbs = sample(f, f.uv).rgb + blur(f, f.uv, 10.0).rgb * 0.6;\\n    col += orbs;\\n    for (int i = 0; i < 5; i++) {\\n        float2 off = c - star_at(i, f.time);\\n        // Far from a star its glow is nothing: skip the costly part.\\n        if (dot(off, off) > 0.5) continue;\\n        float2 ra = polar(off);\\n        // cos^24 by squaring, much cheaper than pow.\\n        float s = cos(ra.y * 3.0 + f.time * (0.3 + 0.1 * float(i)));\\n        s *= s; s *= s; s *= s;\\n        float points = s * s * s;\\n        float reach = 0.012 + (0.05 + 0.12 * f.treble) * points;\\n        float glow = exp(-ra.x / reach) * (0.6 + 0.4 * sin(f.time * 2.0 + float(i) * 1.9));\\n        float3 tint = (i % 2 == 0) ? float3(1.0, 0.75, 0.4) : float3(0.5, 1.0, 0.95);\\n        col += tint * glow * 0.9;\\n    }\\n    return opaque(1.0 - exp(-col * 1.5));\\n}\",\n    \"params\": [\n      {\n        \"name\": \"decay\",\n        \"value\": 0.94,\n        \"low\": 0.85,\n        \"high\": 0.98,\n        \"about\": \"how long the orbs' liquid trails last\"\n      },\n      {\n        \"name\": \"size\",\n        \"value\": 0.11,\n        \"low\": 0.05,\n        \"high\": 0.2,\n        \"about\": \"an orb's size at rest, in half-heights\"\n      },\n      {\n        \"name\": \"swell\",\n        \"value\": 0.2,\n        \"low\": 0.2,\n        \"high\": 0.8,\n        \"follows\": \"level\",\n        \"about\": \"how far the orbs swell with their bands\"\n      }\n    ]\n  }\n}")))))
                       (text "Press Play for the default song, or drop your own songs here with their .lrc or .txt lyrics." :color secondary-label :text-style callout)
                       (shortcut)
                       (shortcut)
                       (shortcut)))))))
