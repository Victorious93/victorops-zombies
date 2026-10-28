class_name HitReact
## Chooses how a zombie reacts to a hit: head snap, side twist, leg stumble, or a heavy knockback.

enum Kind { NONE, FLINCH, HEAD_SNAP, TWIST_LEFT, TWIST_RIGHT, STUMBLE, KNOCKBACK }

## part: "head", "torso", "leg"; frac: damage as a fraction of max health;
## side: dot of hit direction with the zombie's right vector (-1 left .. 1 right).
static func classify(part: String, frac: float, side: float) -> int:
	if frac < 0.04: return Kind.NONE
	if frac >= 0.6: return Kind.KNOCKBACK
	if part == "head": return Kind.HEAD_SNAP
	if part == "leg" and frac >= 0.2: return Kind.STUMBLE
	if absf(side) > 0.45: return Kind.TWIST_RIGHT if side > 0 else Kind.TWIST_LEFT
	return Kind.FLINCH

## How long the zombie is slowed by the reaction (seconds).
static func stagger_time(kind: int) -> float:
	match kind:
		Kind.NONE: return 0.0
		Kind.FLINCH: return 0.12
		Kind.HEAD_SNAP: return 0.22
		Kind.TWIST_LEFT, Kind.TWIST_RIGHT: return 0.18
		Kind.STUMBLE: return 0.55
		Kind.KNOCKBACK: return 0.4
	return 0.0

## Pose offset (pitch, yaw, roll in radians) applied to the model at the start of the reaction.
static func pose(kind: int) -> Vector3:
	match kind:
		Kind.FLINCH: return Vector3(-0.18, 0, 0)
		Kind.HEAD_SNAP: return Vector3(-0.38, 0, 0)
		Kind.TWIST_LEFT: return Vector3(-0.1, 0.45, 0.12)
		Kind.TWIST_RIGHT: return Vector3(-0.1, -0.45, -0.12)
		Kind.STUMBLE: return Vector3(0.35, 0, 0.1)
		Kind.KNOCKBACK: return Vector3(-0.5, 0, 0)
	return Vector3.ZERO
