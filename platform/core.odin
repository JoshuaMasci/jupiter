package platform

import "vendor:sdl3"

init :: proc() {
	sdl_ok := sdl3.Init({.VIDEO, .GAMEPAD})
	assert(sdl_ok)
}

deinit :: proc() {
	sdl3.Quit()
}
