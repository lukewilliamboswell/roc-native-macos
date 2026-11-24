import pf.Engine exposing [Elem, Signal]
import pf.Ui
import logic.Scene

## The visualization: the one module that knows how a scene reaches the
## screen. Everything else hands it a `Scene.Drawing` (from
## `logic/Scene.roc`, which turns a preset into one) and the lyrics to show
## over it.
##
## The picture and the words are two layers of one `Ui.overlay`. The
## picture is a drawing surface (`Ui.surface`) that draws `Scene.marks` at
## every refresh of the display, reading the sound's measurements
## (`audio.waveform`, `audio.bands`, `audio.level`, ...) natively, so Roc
## runs only when the preset changes. Its trail (`Scene.trail`) keeps the
## last frames under the new one; the player's session generation resets
## it after a load, seek or stop. A preset's shaders go to the surface
## (`shader`), which runs them with the Metal renderer and reports what
## they are doing (`on_shader`): running, a stage that does not compile
## (it keeps drawing that stage's last good source), or the Core Graphics
## fallback, where the marks and the trail are the whole picture. The words are native text in the
## overlay's foreground, over the finished picture, so they stay sharp,
## read to VoiceOver, and never enter the trail.
Visual := [].{

	## How tall the visualization is when the window opens.
	height : U32
	height = 280

	## The picture with the words over it, filling the width. `reset` is the
	## session's generation: a new one clears the trail.
	view : Signal(ctx, Scene.Drawing), Signal(ctx, U64), Engine.HandlerOf(ctx, Ui.ShaderStatus), Elem(ctx) -> Elem(ctx)
	view = |drawing, reset, on_shader, words|
		Ui.overlay(
			{ vertical: Bottom, padding: All(14), height: AtLeast(Visual.height) },
			Visual.picture(drawing, reset, on_shader),
			words,
		)

	## The drawing surface.
	picture : Signal(ctx, Scene.Drawing), Signal(ctx, U64), Engine.HandlerOf(ctx, Ui.ShaderStatus) -> Elem(ctx)
	picture = |drawing, reset, on_shader|
		Ui.surface(
			drawing.map(|d| Scene.marks(d).map(Visual.mark)),
			{
				label: "Visualizer",
				space: Engine.const(Fit(Scene.space)),
				background: drawing.map(|d| Visual.color(Scene.background(d))),
				pacing: Engine.const(Display),
				trail: drawing.map(|d| Visual.trail(Scene.trail(d))),
				reset,
				shader: drawing.map(|d| Visual.shader(d.shader)),
				on_shader: Handled(on_shader),
				height: AtLeast(Visual.height),
			},
		)

	## A scene's mark as the surface takes it: the same tags and fields,
	## with each `0xRRGGBB` as a colour.
	mark : Scene.Mark -> Ui.Mark
	mark = |m|
		match m {
			Fill(figure, rgb) => Fill(Visual.shape(figure), Visual.color(rgb))
			Stroke(figure, pen) => Stroke(Visual.shape(figure), { color: Visual.color(pen.color), width: Visual.number(pen.width) })
			Save => Save
			Restore => Restore
			Translate(x, y) => Translate(Visual.number(x), Visual.number(y))
			Rotate(a) => Rotate(Visual.number(a))
			Scale(x, y) => Scale(Visual.number(x), Visual.number(y))
			Opacity(o) => Opacity(Visual.number(o))
		}

	shape : Scene.SurfaceShape -> Ui.Shape
	shape = |s|
		match s {
			Oval(area) => Oval(area)
			Wave(w) => Wave(w)
			Ring(r) => Ring(r)
			Bars(b) => Bars(b)
			Lissajous(l) => Lissajous(l)
		}

	number : Scene.Number -> Ui.Number
	number = |n|
		match n {
			Value(v) => Value(v)
			Source(s) => Source(s)
			Element(e) => Element(e)
		}

	## A preset's shaders as the surface takes them.
	shader : Scene.Shader -> Ui.Shader
	shader = |s|
		match s {
			NoShader => NoShader
			Shaders(stages) => Shaders({ warp: stages.warp, composite: stages.composite, params: stages.params.map(|(name, n)| (name, Visual.number(n))) })
		}

	trail : Scene.Trail -> Ui.Trail
	trail = |t|
		match t {
			NoTrail => NoTrail
			Trail(rates) => Trail(rates)
		}

	## A `0xRRGGBB` the same in light and dark mode, since the picture is
	## drawn on its own background.
	color : Scene.Rgb -> Ui.Color
	color = |rgb| Adaptive({ light: rgb, dark: rgb })

	## Light text, for words over the picture.
	light : Ui.Color
	light = Adaptive({ light: 0xF4F1EA, dark: 0xF4F1EA })

	## Dimmer light text, for what is secondary.
	dim : Ui.Color
	dim = Adaptive({ light: 0xA9A39A, dark: 0xA9A39A })

	## The opaque dark backing behind words, kept to the words themselves.
	backing : Ui.Color
	backing = Adaptive({ light: 0x141210, dark: 0x141210 })
}

expect Visual.mark(Opacity(Element({ source: "audio.bands", index: 2, scale: 1, offset: 0 }))) == Opacity(Element({ source: "audio.bands", index: 2, scale: 1, offset: 0 }))
