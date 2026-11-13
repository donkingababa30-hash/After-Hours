class_name SecurityTerminal
extends Interactable
## The surveillance console in the security office.

signal activated


func _ready() -> void:
	super._ready()
	prompt_text = "View security cameras"


func interact(_player: Node) -> void:
	activated.emit()