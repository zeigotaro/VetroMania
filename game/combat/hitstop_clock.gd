class_name HitstopClock
extends Node
## Counts Combat.hitstop down once per physics frame, after every actor has run (high process priority
## value), so freeze(n) stops the actors for exactly n frames.


func _init() -> void:
	process_priority = 1000
	name = "HitstopClock"


func _physics_process(_delta: float) -> void:
	if Combat.hitstop > 0:
		Combat.hitstop -= 1
