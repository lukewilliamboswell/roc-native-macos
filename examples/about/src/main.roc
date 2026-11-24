app [main] { pf: platform "../../../platform/main.roc" }

import pf.Engine exposing [Elem, In, Root, State]
import pf.Ui

## An About window drawn from the app's assets: `assets/icon.png`, which is
## also the app's icon in `about.app`, and `assets/mark.pdf`, a vector
## drawing. The picker switches the image the window shows.
main : Engine.Program
main = Engine.program(|| Engine.state("icon.png", view))

view : State(In(Root, Str), Str) -> Elem(In(Root, Str))
view = |shown|
	Ui.vstack(
		{ spacing: 14, align: Center, padding: Axes({ horizontal: 32, vertical: 12 }), width: AtLeast(320) },
		[
			Ui.box(
				{ fill: Adaptive({ light: 0xE8EDF6, dark: 0x263246 }), radius: 18, padding: All(20) },
				Ui.asset_image(shown.signal(), { width: Fixed(144), height: Fixed(116), scaling: Fit, label: "The chosen image" }),
			),
			Ui.text("About", { style: Title1, weight: Semibold }),
			Ui.text("Version 1.0", { style: Callout, color: SecondaryLabel }),
			Ui.segmented(
				shown.signal().map(|file| if (file == "mark.pdf") "Vector" else "Bitmap"),
				{ choices: ["Bitmap", "Vector"], on_change: shown.set_value(|_, choice| if (choice == "Vector") "mark.pdf" else "icon.png") },
			),
			Ui.hstack(
				{ spacing: 6 },
				[
					Ui.asset_image("mark.pdf", { height: Fixed(14) }),
					Ui.text("Images from assets/, beside src/", { style: Caption1, color: TertiaryLabel }),
				],
			),
		],
	)
