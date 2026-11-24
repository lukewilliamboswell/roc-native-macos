import pf.Engine exposing [Elem, Signal]
import pf.Ui
import logic.Library
import logic.Preset
import Store
import Widgets

## The preset editor panel: the preset's name and Save As, its layers and
## their mappings, its feedback, its file as text, and Import… and
## Export…. Editing is live: while the editor is open the picture shows the
## draft (`Store.shown`), and the song plays on.
##
## Every control edits the draft through one decision, `Store.edited`,
## and every slider keeps its value in range (`Preset.property_range`);
## the file's text goes through `Store.edited_text`, which checks it with
## `Preset.decode`: a text that is not a valid preset lists the fields that
## need attention, and the draft stays the last valid one. Both paths end
## in the same check, so a draft is always a preset that could be saved,
## exported or drawn.
##
## To add a layer kind or a mapping target, extend `logic/Preset.roc` (its
## opening comment says where); the editor offers what `Preset.kinds`,
## `Preset.features` and `Preset.properties` list.
Editor := [].{

	view : () -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	view = || {
		editor = Store.cells.editor.signal()
		mine = Store.cells.mine.signal()
		Ui.vstack(
			{ spacing: 10, align: Fill },
			[
				Ui.hstack(
					{ spacing: 8 },
					[
						Ui.text("Preset", { style: Headline }),
						Ui.text_field(editor.map(|e| e.name), { placeholder: "Name", on_input: Engine.handle_by(editor, Store.named_as), bezel: Rounded, width: Fill }),
						Ui.button("Save As", { on_press: Engine.handle_by({ mine, editor }.Signal.map(|x| x), |x, _| Store.saved(x.mine, x.editor)), role: Default }),
						Widgets.confirm_button("Delete…", "Delete", Engine.handle_by({ mine, chosen: Store.cells.chosen.signal() }.Signal.map(|x| x), |x, _| Store.deleted(x.mine, x.chosen)), Store.cells.chosen.signal().map(|id| !Library.is_builtin(id))),
					],
				),
				Engine.when(
					editor.map(|e| !e.problems.is_empty()),
					|| Ui.text(Store.cells.editor.signal().map(Editor.problems_text), { style: Callout, color: Red, overflow: Wrap, width: Fill }),
					|| Engine.text(""),
				),
				Engine.each(
					editor.map(|e| e.draft.layers.map_with_index(|l, i| { index: i, layer: l })),
					|row| row.index.to_str(),
					|row| Ui.vstack({ align: Fill }, [Editor.layer(row.item())]),
				),
				Ui.hstack(
					{ spacing: 8 },
					[
						Ui.dropdown(Engine.const("Add Layer"), { choices: ["Add Layer"].concat(Preset.kinds.map(Preset.kind_name)), on_change: Engine.handle_by(editor, Editor.layer_added) }),
						Ui.spacer(),
						Ui.file_button("Import…", { on_files: Engine.handle(|received| Store.import_chosen(received.files)), icon: Symbol("square.and.arrow.down"), size: Small }),
						Ui.button("Export…", { on_press: Engine.handle_by({ exporting: Store.cells.exporting.signal(), editor }.Signal.map(|x| x), |x, _| Store.export_asked(x.exporting, x.editor)), icon: Symbol("square.and.arrow.up"), size: Small }),
					],
				),
				Editor.feedback(),
				Widgets.section(
					Engine.const("File"),
					|| Ui.text_area(Store.cells.editor.signal().map(|e| e.text), { on_input: Engine.handle_by(Store.cells.editor.signal(), Store.edited_text), design: Monospaced, height: AtLeast(140) }),
				),
			],
		)
	}

	## The problems, a line each: `layers[0].size must be between 0 and 1000`.
	problems_text : Store.Editor -> Str
	problems_text = |e| Str.join_with(e.problems.map(|p| "${p.field} ${p.problem}"), "\n")

	## A kind chosen from Add Layer: a new layer of it on top.
	layer_added : Store.Editor, Str -> List(Engine.Write(_))
	layer_added = |e, name|
		match Preset.kinds.find_first(|k| Preset.kind_name(k) == name) {
			Ok(kind) if e.draft.layers.len() < Preset.most_layers => Store.edited(e, |d| { ..d, layers: d.layers.append(Preset.layer(kind)) })
			Ok(_) => [Store.cells.notice.set("A preset has at most ${Preset.most_layers.to_str()} layers.")]
			Err(_) => []
		}

	## The draft with layer `index` changed.
	with_layer : Preset.Doc, U64, (Preset.Layer -> Preset.Layer) -> Preset.Doc
	with_layer = |d, index, change| { ..d, layers: d.layers.update(index, change) ?? d.layers }

	## A slider's text as a number, kept within a property's range.
	ranged : Str, Preset.Property -> I64
	ranged = |typed, property| {
		range = Preset.property_range(property)
		(I64.from_str(typed) ?? range.min).max(range.min).min(range.max)
	}

	## What a layer's row knows: its place and the layer.
	LayerRow : { index : U64, layer : Preset.Layer }

	## A handler for a control of the layer in `row`: `change` makes the new
	## layer from the old one and what the control sent.
	on_layer : Signal(ctx, LayerRow), (Preset.Layer, Str -> Preset.Layer) -> Engine.Handler(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	on_layer = |row, change| Engine.handle_by({ r: row, e: Store.cells.editor.signal() }.Signal.map(|x| x), |x, sent| Store.edited(x.e, |d| Editor.with_layer(d, x.r.index, |l| change(l, sent))))

	## One layer: its kind, palette, size, thickness and opacity, and its
	## mappings, in a section of its own that can be folded away. A list
	## row is one element, so its row wraps the section in a stack.
	layer : Signal(ctx, LayerRow) -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	layer = |row|
		Widgets.section(
			row.map(|r| "Layer ${(r.index + 1).to_str()}"),
			|| {
				item = row.lift()
				held = item.map(|r| r.layer)
				Ui.vstack(
					{ spacing: 4, align: Fill },
					[
						Ui.hstack(
							{ spacing: 8 },
							[
								Ui.dropdown(held.map(|l| Preset.kind_name(l.kind)), { choices: Preset.kinds.map(Preset.kind_name), on_change: Editor.on_layer(item, |l, name| { ..l, kind: Preset.kinds.find_first(|k| Preset.kind_name(k) == name) ?? l.kind }) }),
								Ui.dropdown(held.map(|l| Library.palette_name(l.colors)), { choices: Library.palettes.map(|p| p.name).append("Custom"), on_change: Editor.on_layer(item, |l, name| { ..l, colors: (Library.palettes.find_first(|p| p.name == name) ?? { name, colors: l.colors }).colors }) }),
								Ui.spacer(),
								Ui.button(item.map(|r| "Remove Layer ${(r.index + 1).to_str()}"), { on_press: Engine.handle_by({ r: item, e: Store.cells.editor.signal() }.Signal.map(|x| x), |x, _| Store.edited(x.e, |d| { ..d, layers: d.layers.drop_at(x.r.index) })), icon: Symbol("trash"), title_display: Hidden, bezel: Borderless }),
							],
						),
						Editor.property_slider("Size", held.map(|l| l.size), Size, Editor.on_layer(item, |l, typed| { ..l, size: Editor.ranged(typed, Size) })),
						Widgets.labelled_slider("Thickness", held.map(|l| l.thickness), Preset.thickness_range, Editor.on_layer(item, |l, typed| { ..l, thickness: Editor.clamped(typed, Preset.thickness_range) }), held.map(|l| l.thickness.to_str())),
						Editor.property_slider("Opacity", held.map(|l| l.opacity), Opacity, Editor.on_layer(item, |l, typed| { ..l, opacity: Editor.ranged(typed, Opacity) })),
						Editor.mappings(item),
					],
				)
			},
		)

	property_slider : Str, Signal(ctx, I64), Preset.Property, Engine.Handler(ctx) -> Elem(ctx)
	property_slider = |label, value, property, on_input| Widgets.labelled_slider(label, value, Preset.property_range(property), on_input, value.map(|n| n.to_str()))

	## What a mapping's row knows: its layer's place, its own, and the mapping.
	MappingRow : { layer : U64, at : U64, mapping : Preset.Mapping }

	## A handler for a control of the mapping in `row`.
	on_mapping : Signal(ctx, MappingRow), (Preset.Mapping, Str -> Preset.Mapping) -> Engine.Handler(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	on_mapping = |row, change| Engine.handle_by({ r: row, e: Store.cells.editor.signal() }.Signal.map(|x| x), |x, sent| Store.edited(x.e, |d| Editor.with_layer(d, x.r.layer, |l| { ..l, mappings: l.mappings.update(x.r.at, |m| change(m, sent)) ?? l.mappings })))

	## A layer's mappings, each with its range, and a way to add one.
	mappings : Signal(ctx, LayerRow) -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	mappings = |item|
		Ui.vstack(
			{ spacing: 4, align: Fill },
			[
				Engine.each(
					item.map(|r| r.layer.mappings.map_with_index(|m, i| { layer: r.index, at: i, mapping: m })),
					|r| r.at.to_str(),
					|r| Editor.mapping(r.item()),
				),
				Ui.dropdown(
					Engine.const("Add Mapping"),
					{
						choices: ["Add Mapping"].concat(Editor.mapping_choices),
						on_change: Editor.on_layer(item, Editor.mapping_added),
					},
				),
			],
		)

	## One mapping: what it maps, its range as two sliders, and Remove.
	mapping : Signal(ctx, MappingRow) -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	mapping = |m|
		Ui.vstack(
			{ spacing: 2, align: Fill },
			[
				Ui.hstack(
					{},
					[
						Ui.text(m.map(|r| "${Preset.feature_name(r.mapping.feature)} → ${Preset.property_name(r.mapping.property)}, ${r.mapping.from.to_str()} to ${r.mapping.to.to_str()}"), { style: Caption1 }),
						Ui.spacer(),
						Ui.button(
							m.map(|r| "Remove Mapping ${(r.layer + 1).to_str()}.${(r.at + 1).to_str()}"),
							{ on_press: Engine.handle_by({ r: m, e: Store.cells.editor.signal() }.Signal.map(|x| x), |x, _| Store.edited(x.e, |d| Editor.with_layer(d, x.r.layer, |l| { ..l, mappings: l.mappings.drop_at(x.r.at) }))), icon: Symbol("minus.circle"), title_display: Hidden, bezel: Borderless },
						),
					],
				),
				Widgets.labelled_slider("From", m.map(|r| r.mapping.from), Editor.mapping_range, Editor.on_mapping(m, |mp, typed| { ..mp, from: Editor.ranged(typed, mp.property) }), m.map(|r| r.mapping.from.to_str())),
				Widgets.labelled_slider("To", m.map(|r| r.mapping.to), Editor.mapping_range, Editor.on_mapping(m, |mp, typed| { ..mp, to: Editor.ranged(typed, mp.property) }), m.map(|r| r.mapping.to.to_str())),
			],
		)

	## The range a mapping's sliders cover: every property's, end to end. A
	## value is kept within its own property's range when it is set.
	mapping_range : { min : I64, max : I64 }
	mapping_range = { min: -180, max: 1000 }

	## The mappings Add Mapping offers: each of the level, bass, mids and
	## treble onto each property.
	mapping_choices : List(Str)
	mapping_choices = Editor.pairs.map(|(f, p)| Editor.pair_name(f, p))

	pairs : List((Preset.Feature, Preset.Property))
	pairs = [Level, Bass, Mids, Treble].join_map(|f| Preset.properties.map(|p| (f, p)))

	pair_name : Preset.Feature, Preset.Property -> Str
	pair_name = |f, p| "${Preset.feature_name(f)} → ${Preset.property_name(p)}"

	## A mapping chosen from Add Mapping, over the whole of its property's
	## range; a property mapped already is mapped afresh.
	mapping_added : Preset.Layer, Str -> Preset.Layer
	mapping_added = |l, choice|
		match Editor.pairs.find_first(|(f, p)| Editor.pair_name(f, p) == choice) {
			Ok((feature, property)) if l.mappings.len() < Preset.most_mappings or l.mappings.any(|m| m.property == property) => {
				range = Preset.property_range(property)
				{ ..l, mappings: l.mappings.drop_if(|m| m.property == property).append({ feature, property, from: range.min, to: range.max }) }
			}
			_ => l
		}

	## A number a feedback slider sent, kept within its range.
	clamped : Str, { min : I64, max : I64 } -> I64
	clamped = |typed, range| (I64.from_str(typed) ?? range.min).max(range.min).min(range.max)

	## Feedback: on or off, its zoom and how long its trails last.
	feedback : () -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	feedback = || {
		editor = Store.cells.editor.signal()
		held = editor.map(|e| e.draft.feedback)
		change = |f| Engine.handle_by(Store.cells.editor.signal(), |e, typed| Store.edited(e, |d| { ..d, feedback: f(d.feedback, typed) }))
		Ui.vstack(
			{ spacing: 4, align: Fill },
			[
				Ui.checkbox("Feedback", { checked: held.map(|f| f.enabled), on_change: Engine.handle_by(editor, |e, on| Store.edited(e, |d| { ..d, feedback: { ..d.feedback, enabled: on } })) }),
				Engine.when(
					held.map(|f| f.enabled),
					|| Ui.vstack(
						{ spacing: 4, align: Fill },
						[
							Widgets.labelled_slider("Zoom ‰", Store.cells.editor.signal().map(|e| e.draft.feedback.zoom), Preset.zoom_range, change(|f, typed| { ..f, zoom: Editor.clamped(typed, Preset.zoom_range) }), Store.cells.editor.signal().map(|e| e.draft.feedback.zoom.to_str())),
							Widgets.labelled_slider("Half-life", Store.cells.editor.signal().map(|e| e.draft.feedback.half_life_ms), Preset.half_life_range, change(|f, typed| { ..f, half_life_ms: Editor.clamped(typed, Preset.half_life_range) }), Store.cells.editor.signal().map(|e| "${e.draft.feedback.half_life_ms.to_str()} ms")),
						],
					),
					|| Engine.text(""),
				),
			],
		)
	}

	## The site that reads a preset file chosen with Import…, as bounded
	## text on the page: a preset is small, so at most 64 KiB is read, and
	## the handle goes once the read is done.
	importing : () -> Elem(ctx)
		where [ctx.store : () -> Engine.Reach(ctx, _)]
	importing = ||
		Engine.watch_latest(
			Store.cells.importing.signal(),
			|state|
				match state {
					ImportReading(file) => [file.read_utf8({ max_bytes: 65_536 })]
					NotImporting => []
				},
			Engine.react_by(
				{ mine: Store.cells.mine.signal(), editor: Store.cells.editor.signal() }.Signal.map(|x| x),
				|x, state, answer|
					match state {
						ImportReading(file) => Store.imported(x.mine, x.editor, file.name(), answer)
						NotImporting => []
					},
			),
		)
}

expect Editor.mapping_added(Preset.layer(Ring), "Bass → Size").mappings == [{ feature: Bass, property: Size, from: 0, to: 1000 }]
expect Editor.mapping_added(Preset.layer(Ring), "Nonsense").mappings == []
expect Editor.ranged("5000", Opacity) == 100 and Editor.ranged("x", Rotation) == -180
