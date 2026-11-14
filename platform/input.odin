package platform

import "core:log"
import "vendor:sdl3"

InputDeviceType :: enum {
	MouseKeyboard,
	Gamepad,
}

MouseButton :: enum {
	LEFT   = 1,
	MIDDLE = 2,
	RIGHT  = 3,
	X1     = 4,
	X2     = 5,
}

InputState :: struct {
	mouse:        MouseState,
	keyboard:     KeyboardState,
	gamepads:     map[sdl3.JoystickID]GamepadState,
	last_device:  InputDeviceType,
	last_gamepad: sdl3.JoystickID,
}

MouseState :: struct {
	motion:  [2]f32,
	buttons: [MouseButton]ButtonState,
	scroll:  [2]i32,
}

KeyboardState :: struct {}


GamepadState :: struct {
	gamepad: ^sdl3.Gamepad,
	buttons: [sdl3.GamepadButton]ButtonState,
	axis:    [sdl3.GamepadAxis]f32,
}

ButtonState :: struct {
	current:  bool,
	previous: bool,
}

newFrameInput :: proc(state: ^InputState) {
	state.mouse.motion = {0, 0}
	for &button in state.mouse.buttons {
		button.previous = button.current
	}

	for id in state.gamepads {
		gamepad := &state.gamepads[id]
		for &button in gamepad.buttons {
			button.previous = button.current
		}
	}
}

processEventInput :: proc(state: ^InputState, event: ^sdl3.Event) {
	#partial switch event.type {
	case .MOUSE_MOTION:
		state.last_device = .MouseKeyboard
		state.mouse.motion = {event.motion.xrel, event.motion.yrel}
	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		state.last_device = .MouseKeyboard
		button := cast(MouseButton)event.button.button
		state.mouse.buttons[button].current = event.button.down
	case .GAMEPAD_ADDED:
		state.gamepads[event.gdevice.which] = {
			gamepad = sdl3.OpenGamepad(event.gdevice.which),
		}
	case .GAMEPAD_REMOVED:
		sdl3.CloseGamepad(state.gamepads[event.gdevice.which].gamepad)
		delete_key(&state.gamepads, event.gdevice.which)
	case .GAMEPAD_BUTTON_DOWN, .GAMEPAD_BUTTON_UP:
		state.last_device = .Gamepad
		state.last_gamepad = event.gbutton.which
		button := cast(sdl3.GamepadButton)event.gbutton.button
		gamepad, ok := &state.gamepads[event.gbutton.which]
		if (ok) {
			gamepad.buttons[button].current = event.gbutton.down
		}
	case .GAMEPAD_AXIS_MOTION:
		state.last_device = .Gamepad
		state.last_gamepad = event.gaxis.which
		axis := cast(sdl3.GamepadAxis)event.gaxis.axis
		gamepad, ok := &state.gamepads[event.gaxis.which]
		if (ok) {
			gamepad.axis[axis] = axis_to_f32(event.gaxis.value)
		}
	}
}

axis_to_f32 :: proc(v: i16) -> f32 {
	return max(f32(v) / 32767.0, -1.0)
}
