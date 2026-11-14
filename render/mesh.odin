package render

import "core:mem"
import "vendor:sdl3"

Mesh :: struct {
	vertex_buffer: ^sdl3.GPUBuffer,
	vertex_count:  u32,
	index_buffer:  ^sdl3.GPUBuffer,
	index_count:   u32,
}

Vertex :: struct #packed {
	position: [3]f32,
	normal:   [3]f32,
	uv0:      [2]f32,
}
Index :: u32

initMesh :: proc(gpu: ^sdl3.GPUDevice, vertices: []Vertex, indices: []Index) -> Mesh {
	return {
		vertex_buffer = initBuffer(gpu, {.VERTEX}, mem.slice_to_bytes(vertices)),
		vertex_count = u32(len(vertices)),
		index_buffer = initBuffer(gpu, {.INDEX}, mem.slice_to_bytes(indices)),
		index_count = u32(len(indices)),
	}
}

deinitMesh :: proc(gpu: ^sdl3.GPUDevice, mesh: Mesh) {
	sdl3.ReleaseGPUBuffer(gpu, mesh.vertex_buffer)
	sdl3.ReleaseGPUBuffer(gpu, mesh.index_buffer)
}

drawMesh :: proc(render_pass: ^sdl3.GPURenderPass, mesh: Mesh) {
	vertex_binding := sdl3.GPUBufferBinding {
		buffer = mesh.vertex_buffer,
	}

	sdl3.BindGPUVertexBuffers(render_pass, 0, &vertex_binding, 1)
	sdl3.BindGPUIndexBuffer(render_pass, {buffer = mesh.vertex_buffer}, ._32BIT)
	sdl3.DrawGPUIndexedPrimitives(render_pass, mesh.index_count, 1, 0, 0, 0)
}

initBuffer :: proc(
	gpu: ^sdl3.GPUDevice,
	usage: sdl3.GPUBufferUsageFlags,
	data: []u8,
) -> ^sdl3.GPUBuffer {
	data_size := u32(len(data))

	buffer_create_info := sdl3.GPUBufferCreateInfo {
		usage = usage,
		size  = data_size,
	}

	buffer := sdl3.CreateGPUBuffer(gpu, buffer_create_info)

	transfer_create_info := sdl3.GPUTransferBufferCreateInfo {
		usage = .UPLOAD,
		size  = data_size,
	}
	transfer := sdl3.CreateGPUTransferBuffer(gpu, transfer_create_info)
	defer sdl3.ReleaseGPUTransferBuffer(gpu, transfer)

	transfer_ptr := sdl3.MapGPUTransferBuffer(gpu, transfer, false)
	mem.copy(transfer_ptr, raw_data(data), len(data))

	sdl3.UnmapGPUTransferBuffer(gpu, transfer)

	cmd := sdl3.AcquireGPUCommandBuffer(gpu)
	copy_pass := sdl3.BeginGPUCopyPass(cmd)

	sdl3.UploadToGPUBuffer(
		copy_pass,
		{transfer_buffer = transfer},
		{buffer = buffer, size = data_size},
		false,
	)

	sdl3.EndGPUCopyPass(copy_pass)
	_ = sdl3.SubmitGPUCommandBuffer(cmd)

	return buffer
}
