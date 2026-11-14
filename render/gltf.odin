package render

import "core:slice"
import "core:strings"
import "vendor:cgltf"
import "vendor:sdl3"

Import_Error :: enum {
	None,
	File_Not_Found,
	Invalid_Data,
}

importGltfMesh :: proc(
	gpu: ^sdl3.GPUDevice,
	path: string,
	mesh_index: int = 0,
	prim_index: int = 0,
) -> (
	ret_mesh: Mesh,
	import_err: Import_Error,
) {
	path_cstr := strings.clone_to_cstring(path)
	gltf_data, res := cgltf.parse_file({}, path_cstr)
	if res == .file_not_found {
		import_err = .File_Not_Found
		return
	} else if res != .success {
		import_err = .Invalid_Data
	}
	res = cgltf.load_buffers({}, gltf_data, path_cstr)
	if res == .file_not_found {
		import_err = .File_Not_Found
		return
	} else if res != .success {
		import_err = .Invalid_Data
	}

	attr_type_accessors: [cgltf.attribute_type]^cgltf.accessor
	indices_accessor: ^cgltf.accessor
	indices_type: cgltf.component_type

	mesh := &gltf_data.meshes[mesh_index]
	prim := &mesh.primitives[prim_index]

	if prim.type == .triangles {
		for &attr in prim.attributes {
			attr_type_accessors[attr.type] = attr.data
		}
		indices_accessor = prim.indices
	}


	pos_slice := slice.reinterpret(
		[][3]f32,
		slice.bytes_from_ptr(
			cgltf.buffer_view_data(attr_type_accessors[.position].buffer_view),
			cast(int)attr_type_accessors[.position].buffer_view.size,
		),
	)
	norm_slice := slice.reinterpret(
		[][3]f32,
		slice.bytes_from_ptr(
			cgltf.buffer_view_data(attr_type_accessors[.normal].buffer_view),
			cast(int)attr_type_accessors[.normal].buffer_view.size,
		),
	)
	uv_slice := slice.reinterpret(
		[][2]f32,
		slice.bytes_from_ptr(
			cgltf.buffer_view_data(attr_type_accessors[.texcoord].buffer_view),
			cast(int)attr_type_accessors[.texcoord].buffer_view.size,
		),
	)

	vertices := make([]Vertex, attr_type_accessors[.position].count)
	defer delete(vertices)

	for i in 0 ..< attr_type_accessors[.position].count {
		vertices[i] = Vertex {
			position = pos_slice[i],
			normal   = norm_slice[i],
			uv0      = uv_slice[i],
		}
	}

	indices_buffer_view := indices_accessor.buffer_view
	indices_slice := make([]u32, indices_accessor.count)
	defer delete(indices_slice)

	if indices_type == .r_32u {
		copy(
			indices_slice[:],
			slice.reinterpret(
				[]u32,
				slice.bytes_from_ptr(
					cgltf.buffer_view_data(indices_buffer_view),
					cast(int)indices_buffer_view.size,
				),
			),
		)
	} else {
		idxs_u16 := slice.reinterpret(
			[]u16,
			slice.bytes_from_ptr(
				cgltf.buffer_view_data(indices_buffer_view),
				cast(int)indices_buffer_view.size,
			),
		)
		for i in 0 ..< len(idxs_u16) {
			indices_slice[i] = cast(u32)idxs_u16[i]
		}
	}
	import_err = .None
	ret_mesh = initMesh(gpu, vertices, indices_slice)
	return
}
