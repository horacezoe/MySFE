extends RefCounted
## Original procedural tactical-character geometry. No downloaded game assets.
## All pieces are merged by material and share the same four-weight skin layout.

var batches: Array[Dictionary] = []
var triangles := 0

func _init(material_count: int = 7):
	for i in material_count:
		batches.append({"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "b": PackedInt32Array(), "w": PackedFloat32Array(), "i": PackedInt32Array()})

func vertex(batch: Dictionary, p: Vector3, n: Vector3, uv: Vector2, bone: int, secondary: int = -1, mix_weight: float = 0.0) -> int:
	var result: int = batch.v.size()
	batch.v.append(p)
	batch.n.append(n.normalized())
	batch.uv.append(uv)
	batch.b.append_array(PackedInt32Array([bone, secondary if secondary >= 0 else bone, 0, 0]))
	batch.w.append_array(PackedFloat32Array([1.0 - mix_weight, mix_weight, 0.0, 0.0]))
	return result

func ellipsoid(mat: int, center: Vector3, radii: Vector3, bone: int, basis := Basis.IDENTITY, sides: int = 12, rings: int = 8, secondary: int = -1, mix_weight: float = 0.0):
	var batch := batches[mat]
	var first: int = batch.v.size()
	for row in rings + 1:
		var theta := PI * float(row) / rings
		for col in sides + 1:
			var phi := TAU * float(col) / sides
			var unit := Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi))
			vertex(batch, center + basis * (unit * radii), basis * (unit / radii), Vector2(float(col) / sides, float(row) / rings), bone, secondary, mix_weight)
	for row in rings:
		for col in sides:
			var a := first + row * (sides + 1) + col
			var c := a + sides + 1
			batch.i.append_array(PackedInt32Array([a, c, a + 1, a + 1, c, c + 1]))
			triangles += 2

func limb(mat: int, start: Vector3, end: Vector3, radii: Vector2, bone: int, secondary: int = -1):
	var axis := (start - end).normalized()
	var x_axis := Vector3.RIGHT
	if absf(axis.dot(x_axis)) > 0.9: x_axis = Vector3.FORWARD
	var z_axis := x_axis.cross(axis).normalized()
	x_axis = axis.cross(z_axis).normalized()
	var frame := Basis(x_axis, axis, z_axis)
	var batch := batches[mat]
	var first: int = batch.v.size()
	var profile := [0.77, 0.91, 1.0, 0.98, 0.91, 0.83, 0.75, 0.69, 0.66]
	var sides := 12
	var rings := profile.size() - 1
	var length := start.distance_to(end)
	for row in rings + 1:
		var t := float(row) / rings
		var center := start.lerp(end, t) + axis * lerpf(0.015, -0.015, t)
		for col in sides + 1:
			var phi := TAU * float(col) / sides
			var offset := Vector3(cos(phi) * radii.x * profile[row], 0, sin(phi) * radii.y * profile[row])
			var slope: float = (profile[mini(row + 1, rings)] - profile[maxi(row - 1, 0)]) * radii.x / maxf(0.01, length / rings * 2.0)
			var normal := Vector3(cos(phi) / radii.x, slope / radii.x, sin(phi) / radii.y).normalized()
			vertex(batch, center + frame * offset, frame * normal, Vector2(float(col) / sides, t), bone, secondary, 0.23 * (1.0 - t) * (1.0 - t) if secondary >= 0 else 0.0)
	for row in rings:
		for col in sides:
			var a := first + row * (sides + 1) + col
			var c := a + sides + 1
			batch.i.append_array(PackedInt32Array([a, c, a + 1, a + 1, c, c + 1]))
			triangles += 2
	for endpoint in [0, rings]:
		var center_index := vertex(batch, start + axis * 0.015 if endpoint == 0 else end - axis * 0.015, axis if endpoint == 0 else -axis, Vector2(0.5, 0.5), bone)
		for col in sides:
			var a: int = first + int(endpoint) * (sides + 1) + col
			batch.i.append_array(PackedInt32Array([center_index, a, a + 1] if endpoint == 0 else [center_index, a + 1, a]))
			triangles += 1

func rounded_box(mat: int, center: Vector3, size: Vector3, radius: float, bone: int, basis := Basis.IDENTITY):
	var batch := batches[mat]
	var half := size * 0.5
	var edge := minf(radius, minf(half.x, minf(half.y, half.z)) * 0.8)
	var core := half - Vector3.ONE * edge
	var samples := [-1.0, -0.65, 0.65, 1.0]
	for side in 6:
		var axis := side / 2
		var sign_value := 1.0 if side % 2 == 0 else -1.0
		var first: int = batch.v.size()
		for row in 4:
			for col in 4:
				var q := Vector3.ZERO
				q[axis] = sign_value * half[axis]
				q[(axis + 1) % 3] = samples[col] * half[(axis + 1) % 3]
				q[(axis + 2) % 3] = samples[row] * half[(axis + 2) % 3]
				var clamped := q.clamp(-core, core)
				var normal := (q - clamped).normalized()
				vertex(batch, center + basis * (clamped + normal * edge), basis * normal, Vector2(col / 3.0, row / 3.0), bone)
		for row in 3:
			for col in 3:
				var a := first + row * 4 + col
				if sign_value > 0:
					batch.i.append_array(PackedInt32Array([a, a + 4, a + 1, a + 1, a + 4, a + 5]))
				else:
					batch.i.append_array(PackedInt32Array([a, a + 1, a + 4, a + 1, a + 5, a + 4]))
				triangles += 2

func build(materials: Array[StandardMaterial3D]) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for idx in batches.size():
		var batch := batches[idx]
		if batch.v.is_empty(): continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = batch.v
		arrays[Mesh.ARRAY_NORMAL] = batch.n
		arrays[Mesh.ARRAY_TEX_UV] = batch.uv
		arrays[Mesh.ARRAY_BONES] = batch.b
		arrays[Mesh.ARRAY_WEIGHTS] = batch.w
		arrays[Mesh.ARRAY_INDEX] = batch.i
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[idx])
	return mesh
