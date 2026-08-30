extends "res://scripts/main.gd"

func _ready() -> void:
    super._ready()

    # Replace the original procedural target machine with the STL-informed,
    # fully procedural target implementation while retaining input/UI/room.
    if is_instance_valid(machine):
        remove_child(machine)
        machine.free()

    machine = SkeeBallMachineV3.new()
    machine.name = "SkeeBallMachine"
    add_child(machine)
    machine.scored.connect(_on_machine_scored)

    if is_instance_valid(ball):
        ball.configure_start(machine.ball_start_transform())
