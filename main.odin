package main

import "platform"
import "render"

import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:mem"
import "vendor:sdl3"

Transform :: struct {
	position: linalg.Vector3f32,
	rotation: linalg.Quaternionf32,
	scale:    linalg.Vector3f32,
}

makeTransform :: proc(
	position: linalg.Vector3f32 = {0, 0, 0},
	rotation: linalg.Quaternionf32 = quaternion(imag = 0, jmag = 0, kmag = 0, real = 1),
	scale: linalg.Vector3f32 = {1, 1, 1},
) -> Transform {
	return {position = position, rotation = rotation, scale = scale}
}

calcModelMatrix :: proc(transform: Transform) -> linalg.Matrix4f32 {
	translation := linalg.matrix4_translate(transform.position)
	rotation := linalg.matrix4_from_quaternion(transform.rotation)
	scale := linalg.matrix4_scale(transform.scale)
	return linalg.matrix_mul(translation, linalg.matrix_mul(rotation, scale))}

calcViewMatrix :: proc(transform: Transform) -> linalg.Matrix4f32 {
	forward := linalg.quaternion_mul_vector3(transform.rotation, linalg.VECTOR3F32_Z_AXIS)
	up := linalg.quaternion_mul_vector3(transform.rotation, linalg.VECTOR3F32_Y_AXIS)
	return linalg.matrix4_look_at(transform.position, transform.position + forward, up)
}

matrix4_perspective_infinite_reverse_z_f32 :: proc(
	fovy: f32,
	aspect_ratio: f32,
	near: f32,
	flip_y_axis := false,
) -> linalg.Matrix4f32 {
	t := linalg.tan(fovy * 0.5)
	m: linalg.Matrix4f32
	m[0, 0] = 1 / (aspect_ratio * t)
	m[1, 1] = 1 / t
	m[2, 2] = 0
	m[2, 3] = near
	m[3, 2] = -1

	if flip_y_axis {
		m[1, 1] = -m[1, 1]
	}

	return m
}

fovYFromFovX :: proc(aspect_ratio: f32, fovx: f32) -> f32 {
	return linalg.atan(linalg.tan(fovx / 2) / aspect_ratio) * 2
}

main :: proc() {
	context.logger = log.create_console_logger()

	platform.init()
	defer platform.deinit()

	gpu := sdl3.CreateGPUDevice({.SPIRV}, true, nil)
	defer sdl3.DestroyGPUDevice(gpu)

	window := sdl3.CreateWindow("Jupiter Engine", 1920, 1080, {.RESIZABLE})
	defer sdl3.DestroyWindow(window)

	assert(sdl3.ClaimWindowForGPUDevice(gpu, window), "Failed to claim window")
	defer sdl3.ReleaseWindowFromGPUDevice(gpu, window)

	triangle_pipeline := createPipeline(gpu, window)
	defer sdl3.ReleaseGPUGraphicsPipeline(gpu, triangle_pipeline)

	cube_mesh, ok := render.importGltfMesh(gpu, "./assets/models/cube.glb")
	defer render.deinitMesh(gpu, cube_mesh)

	running := true

	input_state: platform.InputState = {}

	model_transform: Transform = makeTransform()
	camera_transform: Transform = makeTransform(position = {0, 0, -3})

	last_counter := sdl3.GetPerformanceCounter()
	freq := f64(sdl3.GetPerformanceFrequency())
	for running {
		now := sdl3.GetPerformanceCounter()
		delta_time := f32(f64(now - last_counter) / freq) // seconds
		last_counter = now

		platform.newFrameInput(&input_state)
		event: sdl3.Event
		for sdl3.PollEvent(&event) {
			platform.processEventInput(&input_state, &event)
			#partial switch event.type {
			case .QUIT, .WINDOW_CLOSE_REQUESTED:
				running = false
			case .KEY_DOWN:
				if event.key.scancode == .ESCAPE {
					running = false
				}
			}
		}

		input: f32
		switch input_state.last_device {
		case .MouseKeyboard:
			if input_state.mouse.buttons[.LEFT].current &&
			   !input_state.mouse.buttons[.RIGHT].current {
				input = -1
			} else if !input_state.mouse.buttons[.LEFT].current &&
			   input_state.mouse.buttons[.RIGHT].current {
				input = 1
			}
		case .Gamepad:
			last_gamepad, ok := &input_state.gamepads[input_state.last_gamepad]
			if ok {
				input = last_gamepad.axis[.RIGHTX]
			}
		}

		if abs(input) > 0.1 {
			roll_quat := linalg.quaternion_from_euler_angle_z_f32(linalg.PI * input * delta_time)
			model_transform.rotation = linalg.quaternion_normalize(
				linalg.quaternion_mul_quaternion(model_transform.rotation, roll_quat),
			)
		}

		cmdBuf := sdl3.AcquireGPUCommandBuffer(gpu)
		window_texture: ^sdl3.GPUTexture
		window_size: [2]u32
		got_win_tex := sdl3.WaitAndAcquireGPUSwapchainTexture(
			cmdBuf,
			window,
			&window_texture,
			&window_size[0],
			&window_size[1],
		)
		window_aspect_ratio := f32(window_size[0]) / f32(window_size[1])

		colorTarget := sdl3.GPUColorTargetInfo {
			texture     = window_texture,
			clear_color = sdl3.FColor{0.1, 0.1, 0.1, 1.0},
			load_op     = .CLEAR,
			store_op    = .STORE,
		}
		renderPass := sdl3.BeginGPURenderPass(cmdBuf, &colorTarget, 1, nil)

		sdl3.BindGPUGraphicsPipeline(renderPass, triangle_pipeline)

		model_matrix := calcModelMatrix(model_transform)
		view_matrix := calcViewMatrix(camera_transform)
		projection_matrix := matrix4_perspective_infinite_reverse_z_f32(
			45,
			window_aspect_ratio,
			0.1,
		)
		mvp_matrix := linalg.matrix_mul(
			projection_matrix,
			linalg.matrix_mul(view_matrix, model_matrix),
		)
		sdl3.PushGPUVertexUniformData(cmdBuf, 0, &mvp_matrix, size_of(mvp_matrix))
		sdl3.DrawGPUPrimitives(renderPass, 3, 1, 0, 0)

		sdl3.EndGPURenderPass(renderPass)
		submit_ok := sdl3.SubmitGPUCommandBuffer(cmdBuf)
	}
}

createPipeline :: proc(gpu: ^sdl3.GPUDevice, window: ^sdl3.Window) -> ^sdl3.GPUGraphicsPipeline {
	spirvCode := #load("cache/shaders/slang/triangle.spv")

	vertexShaderCreateInfo := sdl3.GPUShaderCreateInfo {
		code                 = raw_data(spirvCode),
		code_size            = len(spirvCode),
		entrypoint           = "vertex",
		format               = {.SPIRV},
		stage                = .VERTEX,
		num_samplers         = 0,
		num_uniform_buffers  = 1,
		num_storage_buffers  = 0,
		num_storage_textures = 0,
	}
	vertex_shader := sdl3.CreateGPUShader(gpu, vertexShaderCreateInfo)
	defer sdl3.ReleaseGPUShader(gpu, vertex_shader)

	fragmentShaderCreateInfo := sdl3.GPUShaderCreateInfo {
		code                 = raw_data(spirvCode),
		code_size            = len(spirvCode),
		entrypoint           = "fragment",
		format               = {.SPIRV},
		stage                = .FRAGMENT,
		num_samplers         = 0,
		num_uniform_buffers  = 0,
		num_storage_buffers  = 0,
		num_storage_textures = 0,
	}
	fragment_shader := sdl3.CreateGPUShader(gpu, fragmentShaderCreateInfo)
	defer sdl3.ReleaseGPUShader(gpu, fragment_shader)

	colorTargetDesc := [1]sdl3.GPUColorTargetDescription {
		{format = sdl3.GetGPUSwapchainTextureFormat(gpu, window)},
	}

	pipelineCreateInfo := sdl3.GPUGraphicsPipelineCreateInfo {
		target_info = sdl3.GPUGraphicsPipelineTargetInfo {
			num_color_targets = u32(len(colorTargetDesc)),
			color_target_descriptions = raw_data(&colorTargetDesc),
		},
		primitive_type = .TRIANGLELIST,
		vertex_shader = vertex_shader,
		fragment_shader = fragment_shader,
		rasterizer_state = {fill_mode = .FILL, cull_mode = .NONE},
	}

	return sdl3.CreateGPUGraphicsPipeline(gpu, pipelineCreateInfo)
}
