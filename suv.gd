extends VehicleBody3D

@export var max_steer = 0.6
const ENGINE_POWER = 100_000
const BRAKE_POWER = 15_000
const REVERSE_SPEED = -50_000

@onready var camera_pivot = $CameraPivot
@onready var camera_3d = $CameraPivot/Camera3D

var look_at

# Called when the node enters the scene tree for the first time.
func _ready():
	# Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURE)
	look_at = global_position

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
	steering = move_toward(steering, Input.get_axis("right", "left") * max_steer, delta * 2.5)
	
	engine_force = 0
	if Input.is_action_pressed("accelerate"):
		engine_force = ENGINE_POWER * delta
	elif Input.is_action_pressed("brake"):
		brake = BRAKE_POWER
		# engine_force = -BRAKE_POWER * delta
	elif Input.is_action_pressed("decelerate"):
		if linear_velocity.dot(linear_velocity.normalized()) > 0.01:
			engine_force = REVERSE_SPEED * delta
	
	apply_central_force(-transform.basis.z * engine_force)
	
	camera_pivot.global_position = camera_pivot.global_position.lerp(global_position, delta * 20.0)
	camera_pivot.transform = camera_pivot.transform.interpolate_with(transform, delta * 5.0)
	look_at = look_at.lerp(global_position + linear_velocity, delta * 5.0)
	camera_3d.look_at(global_position + linear_velocity)
	
	if Input.is_action_pressed("ui_cancel"):
		position = Vector3(position.x, position.y + 1, position.z)
		rotation = Vector3(rotation.x, rotation.y, 0)
