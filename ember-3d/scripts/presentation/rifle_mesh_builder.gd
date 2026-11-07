extends RefCounted
## Original procedural geometry, baked by material into a small number of surfaces.
## No imported game assets, nodes, collision shapes or simulation state live here.

var groups: Dictionary = {}

func _group(material: Material) -> Dictionary:
	if not groups.has(material):
		groups[material] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "i": PackedInt32Array()}
	return groups[material]

func mesh(source: Mesh, at: Transform3D, material: Material) -> void:
	var g := _group(material)
	for surface in range(source.get_surface_count()):
		var a := source.surface_get_arrays(surface)
		var offset: int = g.v.size()
		var vertices: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var texcoords: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var normal_basis := at.basis.inverse().transposed()
		for k in range(vertices.size()):
			g.v.append(at * vertices[k])
			g.n.append((normal_basis * normals[k]).normalized())
			g.uv.append(texcoords[k] if k < texcoords.size() else Vector2(vertices[k].x, vertices[k].z))
		var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for k in range(vertices.size()): g.i.append(offset + k)
		else:
			for k in indices: g.i.append(offset + k)

func triangle(a: Vector3, b: Vector3, c: Vector3, normal: Vector3, material: Material) -> void:
	var g := _group(material)
	var offset: int = g.v.size()
	# Godot front faces wind clockwise when viewed from outside.
	var points := [a, c, b] if (b-a).cross(c-a).dot(normal) > 0.0 else [a, b, c]
	for p: Vector3 in points:
		g.v.append(p)
		g.n.append(normal)
		g.uv.append(Vector2(p.x + p.z, p.y) * 5.0)
		g.i.append(offset)
		offset += 1

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, material: Material) -> void:
	triangle(a,b,c,normal,material)
	triangle(a,c,d,normal,material)

func box(size: Vector3, position: Vector3, material: Material, rotation := Vector3.ZERO, bevel := 0.0) -> void:
	var at := Transform3D(Basis.from_euler(rotation), position)
	if bevel <= 0.0001:
		var shape := BoxMesh.new()
		shape.size = size
		mesh(shape, at, material)
		return
	# Eight sided cross section and bevelled end rings, not a scaled primitive cube.
	var x := size.x * 0.5
	var y := size.y * 0.5
	var z := size.z * 0.5
	var r := minf(bevel, minf(x, minf(y,z)) * 0.7)
	var outline := [Vector2(-x+r,-y),Vector2(x-r,-y),Vector2(x,-y+r),Vector2(x,y-r),Vector2(x-r,y),Vector2(-x+r,y),Vector2(-x,y-r),Vector2(-x,-y+r)]
	var rings: Array = []
	for end in range(4):
		var ring: Array[Vector3] = []
		var inset := r * 0.5 if end == 0 or end == 3 else 0.0
		var depth: float = [-z,-z+r,z-r,z][end]
		for p: Vector2 in outline:
			ring.append(Vector3(p.x-signf(p.x)*inset,p.y-signf(p.y)*inset,depth))
		rings.append(ring)
	for k in range(3):
		for j in range(8):
			var a: Vector3 = rings[k][j]
			var b: Vector3 = rings[k][(j+1)%8]
			var c: Vector3 = rings[k+1][(j+1)%8]
			var d: Vector3 = rings[k+1][j]
			var n := (b-a).cross(d-a).normalized()
			quad(at*a,at*b,at*c,at*d,at.basis*n,material)
	for end in [0,3]:
		var center := Vector3(0,0,-z if end == 0 else z)
		var normal := Vector3.FORWARD if end == 0 else Vector3.BACK
		for j in range(8): triangle(at*center,at*rings[end][j],at*rings[end][(j+1)%8],at.basis*normal,material)

func cylinder(radius: float, length: float, position: Vector3, material: Material, rotation := Vector3(PI*0.5,0,0), segments := 12, top_radius := -1.0) -> void:
	var shape := CylinderMesh.new()
	shape.top_radius = radius if top_radius < 0 else top_radius
	shape.bottom_radius = radius
	shape.height = length
	shape.radial_segments = segments
	shape.rings = 1
	mesh(shape, Transform3D(Basis.from_euler(rotation),position), material)

func ellipsoid(size: Vector3, position: Vector3, material: Material, rotation := Vector3.ZERO) -> void:
	var shape := SphereMesh.new()
	shape.radius = 0.5
	shape.height = 1.0
	shape.radial_segments = 10
	shape.rings = 4
	mesh(shape,Transform3D(Basis.from_euler(rotation).scaled(size),position),material)

func link(a: Vector3, b: Vector3, radius_a: float, radius_b: float, material: Material, segments := 10) -> void:
	var direction := b-a
	var shape := CylinderMesh.new()
	shape.bottom_radius = radius_a
	shape.top_radius = radius_b
	shape.height = direction.length()
	shape.radial_segments = segments
	shape.rings = 1
	var basis := Basis(Quaternion(Vector3.UP,direction.normalized()))
	mesh(shape,Transform3D(basis,(a+b)*0.5),material)

func finish() -> ArrayMesh:
	var result := ArrayMesh.new()
	for material: Material in groups:
		var g: Dictionary = groups[material]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.v
		arrays[Mesh.ARRAY_NORMAL] = g.n
		arrays[Mesh.ARRAY_TEX_UV] = g.uv
		arrays[Mesh.ARRAY_INDEX] = g.i
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result.surface_set_material(result.get_surface_count()-1,material)
	return result
