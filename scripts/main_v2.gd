extends "res://scripts/main.gd"

func _ready() -> void:
    super._ready()

    # Replace the original procedural target machine with the higher-fidelity
    # classic target implementation while retaining the existing input/UI/room.
    if is_instance_valid(machine):
        remove_child(machine)
        machine.free()

    machine = SkeeBallMachineV2.new()
    machine.name = "SkeeBallMachine"
    add_child(machine)
    machine.scored.connect(_on_machine_scored)

    if is_instance_valid(ball):
        ball.configure_start(machine.ball_start_transform())
