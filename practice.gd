extends Node3D

# Dictionary to store data for each car
var cars_data = {}

# Path to the race track (Path3D node)
@onready var path = $Path3D

@onready var player = $race2
@onready var pause = $PauseMenu

# Array of car objects
@onready var car_objects = [
	player
]

var path_global_transform

# Array to store checkpoint areas
var checkpoints = []

# Number of checkpoints to generate
@export var num_checkpoints = 15
@export var distance_checkpoint_arrow = 80
@export var laps = 3

# Called when the node enters the scene tree for the first time.
func _ready():
	if not path or car_objects.size() == 0:
		print("Warning: Missing path or car nodes reference!")
	
	path_global_transform = path.global_transform

	for car in car_objects:
		cars_data[car] = {
			"time": 0,
			"best_time": 999,
			"current_checkpoint_index": 0,
			"lap": 0,
			"progress_percent": 0.0,
			"previous_progress_percent": 0.0,
			"lap_times": [],  # Store lap times
		}
		car.connect("speed_changed", _on_car_speed_changed)
	
	generate_checkpoints()
	pause.hide()

# Function to update the HUD for a specific car
func _on_car_speed_changed(speed, car):
	car.get_node("HUD/speed").text = "Speed: " + str(round(speed)) + " units/sec"

func pauseMenu():
	if not get_tree().paused:
		pause.hide()
		player.get_node("HUD").show()
	else:
		pause.show()
		player.get_node("HUD").hide()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if not path or car_objects.size() == 0:
		return
		
	if Input.is_action_pressed("pause"):
		get_tree().paused = true
	
	pauseMenu()
		
	if Input.is_action_pressed("respawn"):
		player.global_transform.origin = checkpoints[cars_data[player]["current_checkpoint_index"] - 1].global_transform.origin
		player.global_transform.basis = checkpoints[cars_data[player]["current_checkpoint_index"] - 1].global_transform.basis
		player.linear_velocity = Vector3.ZERO
		player.angular_velocity = Vector3.ZERO
	
	
	for car in car_objects:
		var car_position = car.global_transform.origin

		# Transform car position to path's local space using path's global transform inverse
		var car_position_local = path_global_transform.affine_inverse() * car_position
		
		# Calculate car progress percentage
		var progress_percent = get_car_progress_percent(car_position_local) * 100
		
		cars_data[car]["time"] += delta
		cars_data[car]["previous_progress_percent"] = cars_data[car]["progress_percent"]
		cars_data[car]["progress_percent"] = progress_percent
		
		if car == player:
			car.get_node("HUD/time").text = "TIME: " + str(cars_data[car]["time"]).pad_zeros(3).left(6) + "\nPROGRESS: " + str(round(progress_percent)) + "%\nLAP: " + str(cars_data[car]["lap"] + 1) + " / " + str(laps)
			car.get_node("HUD/speed").text = "Best Time: " + str(cars_data[car]["best_time"]).pad_zeros(3).left(6) + "\nSpeed: " + str(round(car.linear_velocity.length()))
			
			# Checkpoint arrow point code
			var checkpoint_position = checkpoints[cars_data[car]["current_checkpoint_index"]].position
			var difference = checkpoint_position - car.position
			
			var reverse = 0 if car.linear_velocity.dot(car.transform.basis.z) < 0.01 else PI
			
			car.get_node("HUD/CheckpointArrow").rotation = car.rotation.y + atan2(difference.z , difference.x) + reverse
			var display_server = DisplayServer
			var screen_size_display_server = display_server.window_get_size(0)
				
			if difference.length() > distance_checkpoint_arrow:
				car.get_node("HUD/CheckpointArrow").visible = true
				car.get_node("HUD/CheckpointArrow").position = Vector2(screen_size_display_server[0]/2, screen_size_display_server[1]/5)
			else:
				car.get_node("HUD/CheckpointArrow").visible = false
				
			if cars_data[car]["previous_progress_percent"] > cars_data[car]["progress_percent"]:
				car.get_node("HUD/NO").position = Vector2(screen_size_display_server[0]/2, screen_size_display_server[1] * 4/5)
				car.get_node("HUD/NO").visible = true
			else:
				car.get_node("HUD/NO").visible = false

	# Update rankings based on current progress and laps
	update_rankings()

# Function to get car progress percentage
func get_car_progress_percent(target_position_local):
	var path_curve = path.curve
	var closest_distance = float(INF)
	var closest_offset = 0.0
	var path_length = path_curve.get_baked_length()
	var step_size = 5.0  # Smaller step size means more precise but more computationally expensive
	
	# Iterate along the path to find the closest point to the car's position
	for distance_along_path in range(0, path_length, step_size):
		var path_position = path_curve.sample_baked(distance_along_path)
		var distance_to_car = path_position.distance_to(target_position_local)
		
		if distance_to_car < closest_distance:
			closest_distance = distance_to_car
			closest_offset = distance_along_path
	
	# Calculate the progress percentage
	var progress_percent = closest_offset / path_length
	return progress_percent

# Generate checkpoints along the Path3D
func generate_checkpoints():
	var EPSILON = 10
	
	var path_length = path.curve.get_baked_length()
	var segment_length = path_length / num_checkpoints
	
	for i in range(num_checkpoints + 1):
		var distance_along_path = segment_length * i
		var position_along_path = path.curve.sample_baked(distance_along_path)
		# Sample a point slightly ahead for tangent calculation
		var slightly_ahead_distance = distance_along_path + EPSILON  # Small epsilon value

		# Ensure we don't go beyond path length
		if slightly_ahead_distance > path.curve.get_baked_length():
			slightly_ahead_distance = path.curve.get_baked_length()

		var slightly_ahead_point = path.curve.sample_baked(slightly_ahead_distance)
		
		var checkpoint = Area3D.new()
		var collision_shape = CollisionShape3D.new()
		var shape = CylinderShape3D.new()
		
		# Configure the shape dimensions
		shape.height = 10
		shape.radius = 10
		collision_shape.shape = shape
		
		checkpoint.add_child(collision_shape)
		add_child(checkpoint)
		
		# Set the position of the checkpoint
		checkpoint.global_position = position_along_path
		checkpoint.look_at(slightly_ahead_point, Vector3.UP)
		
		# Connect the area_entered signal
		checkpoint.connect("body_entered", func(body): return _on_checkpoint_area_entered(body, checkpoint))
		
		# Add checkpoint to array
		checkpoints.append(checkpoint)
		
# Signal handler for checkpoint area entered
func _on_checkpoint_area_entered(body, checkpoint):
	if body in car_objects:
		var car = body
		var car_data = cars_data[car]
		if checkpoints[car_data["current_checkpoint_index"]] == checkpoint:
			print("Car entered checkpoint ", car_data["current_checkpoint_index"])
			car_data["current_checkpoint_index"] += 1
			if car_data["current_checkpoint_index"] >= num_checkpoints + 1:
				car_data["current_checkpoint_index"] = 0
				start(car)
		else:
			print("Checkpoint missed or out of order!")

func start(car):
	if not car in cars_data:
		return
	var car_data = cars_data[car]
	if car_data["time"] == 0: # make sure it instantly doesn't trigger it
		return
	
	print("Car crossed the start/finish line!")
	# Update lap time and check if it's the best time
	if car_data["time"] < car_data["best_time"]:
		car_data["best_time"] = car_data["time"]
	print("Current lap time: ", car_data["time"])
	print("Best lap time: ", car_data["best_time"])
	
	# Store the lap time
	car_data["lap_times"].append(car_data["time"])
	
	# Reset the lap timer
	car_data["time"] = 0
	# Increment the lap counter
	car_data["lap"] += 1
	
	# Check if race is over (assuming 3 laps)
	if car_data["lap"] >= laps:
		race_over()

# Function to update the rankings based on laps and progress percentage
func update_rankings():
	# Create a sorted list of cars based on laps and progress percentage
	car_objects.sort_custom(compare_cars)

	# Update HUD with rankings
	for i in range(car_objects.size()):
		var car = car_objects[i]
		if car == player:
			var end = "th" if i >= 3 else ["st", "nd", "rd"][i]
			car.get_node("HUD/rank").text = str(i + 1) + end

func progress_on_track(car):
	return cars_data[car]["progress_percent"]/100 + cars_data[car]["lap"] 

# Custom comparison function to sort cars by lap and progress percentage
func compare_cars(a, b):
	var a_data = cars_data[a]
	var b_data = cars_data[b]

	# Compare by laps first
	if a_data["lap"] > b_data["lap"]:
		return true
	elif a_data["lap"] < b_data["lap"]:
		return false
	
	# Compare by checkpoint progress
	if a_data["current_checkpoint_index"] > b_data["current_checkpoint_index"]:
		return true
	elif a_data["current_checkpoint_index"] < b_data["current_checkpoint_index"]:
		return false
		
	# If laps are equal, compare by progress percentage
	return a_data["progress_percent"] > b_data["progress_percent"]

# Function to handle the end of the race
func race_over():
	# Transfer lap times to the results scene
	var results_scene = load("res://results.tscn").instance()
	results_scene.set_lap_times(cars_data)
	get_tree().change_scene_to(results_scene)