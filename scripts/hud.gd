extends CanvasLayer

signal start_pressed
signal next_car
signal prev_car
signal restart_pressed

const FONT_PATH := "res://ui/kenney/Kenney Future.ttf"

@onready var select_root: Control = $Select
@onready var car_name_label: Label = $Select/Bar/HBox/CarName
@onready var times_panel: Control = $Select/TimesPanel
@onready var times_label: Label = $Select/TimesPanel/Times
@onready var race_root: Control = $Race
@onready var time_label: Label = $Race/Time
@onready var result_root: Control = $Result
@onready var result_time: Label = $Result/Panel/VBox/ResultTime

func _ready() -> void:
	_apply_theme()

func _apply_theme() -> void:
	var font: Font = load(FONT_PATH)
	var white := Color(1, 1, 1, 1)
	var frost := _glass(Color(1, 1, 1, 0.28), Color(1, 1, 1, 0.45), 10)
	var frost_hover := _glass(Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.7), 10)
	var frost_press := _glass(Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.4), 10)

	var theme := Theme.new()
	if font != null:
		theme.set_default_font(font)
	theme.set_default_font_size(22)
	theme.set_stylebox("panel", "PanelContainer", frost)
	theme.set_stylebox("normal", "Button", frost)
	theme.set_stylebox("hover", "Button", frost_hover)
	theme.set_stylebox("pressed", "Button", frost_press)
	theme.set_stylebox("focus", "Button", frost)
	theme.set_color("font_color", "Button", white)
	theme.set_color("font_hover_color", "Button", white)
	theme.set_color("font_pressed_color", "Button", white)
	theme.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.45))
	theme.set_constant("outline_size", "Button", 6)
	theme.set_color("font_color", "Label", white)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.45))
	theme.set_constant("outline_size", "Label", 6)
	select_root.theme = theme
	race_root.theme = theme
	result_root.theme = theme

	_style_label($Select/Title, font, 36)
	_style_label(times_label, font, 18)
	_style_label(car_name_label, font, 24)
	_style_label(time_label, font, 36)
	_style_label(result_time, font, 40)

	for button in [$Select/Bar/HBox/Prev, $Select/Bar/HBox/Next, $Select/Bar/HBox/Start, $Result/Panel/VBox/Restart]:
		_style_button(button, font)

	var prev: Button = $Select/Bar/HBox/Prev
	var next: Button = $Select/Bar/HBox/Next
	var left_tex: Texture2D = load("res://ui/kenney/arrow_w_white.png")
	var right_tex: Texture2D = load("res://ui/kenney/arrow_e_white.png")
	if left_tex != null:
		prev.icon = left_tex
		prev.text = ""
		prev.expand_icon = true
	if right_tex != null:
		next.icon = right_tex
		next.text = ""
		next.expand_icon = true

func _glass(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 18
	box.content_margin_top = 12
	box.content_margin_right = 18
	box.content_margin_bottom = 12
	return box

func _style_label(label: Label, font: Font, size: int) -> void:
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	label.add_theme_constant_override("outline_size", 8)

func _style_button(button: Button, font: Font) -> void:
	if font != null:
		button.add_theme_font_override("font", font)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	button.add_theme_constant_override("outline_size", 8)

func show_select(car_name: String, times: Array = []) -> void:
	select_root.visible = true
	race_root.visible = false
	result_root.visible = false
	set_car_name(car_name)
	set_recent_times(times)

func set_car_name(car_name: String) -> void:
	car_name_label.text = car_name.to_upper()

func set_recent_times(times: Array) -> void:
	if times.is_empty():
		times_panel.visible = false
		times_label.text = ""
		return
	var lines: PackedStringArray = PackedStringArray()
	for item in times:
		if not (item is Dictionary):
			continue
		var row: Dictionary = item
		lines.append("%s  %s" % [_format_time(float(row.get("time", 0.0))), String(row.get("car", "")).to_upper()])
	times_label.text = "\n".join(lines)
	times_panel.visible = not lines.is_empty()
	if times_panel.visible:
		times_panel.reset_size()

func show_race() -> void:
	select_root.visible = false
	race_root.visible = true
	result_root.visible = false
	set_time(0.0)

func set_time(seconds: float) -> void:
	time_label.text = _format_time(seconds)

func show_result(seconds: float) -> void:
	select_root.visible = false
	race_root.visible = true
	result_root.visible = true
	result_time.text = _format_time(seconds)
	time_label.text = _format_time(seconds)

func _format_time(seconds: float) -> String:
	var minutes := int(seconds) / 60
	var secs := fmod(seconds, 60.0)
	return "%d:%05.2f" % [minutes, secs]

func _on_start_pressed() -> void:
	start_pressed.emit()

func _on_prev_pressed() -> void:
	prev_car.emit()

func _on_next_pressed() -> void:
	next_car.emit()

func _on_restart_pressed() -> void:
	restart_pressed.emit()
