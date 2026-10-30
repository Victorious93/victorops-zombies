class_name Gib
extends RefCounted
## v7.11 dismemberment rules for a non-lethal hit. Returns what comes off:
## "" nothing, "arm" a forearm, "legs" (crawler conversion), "both" an arm and the legs.
## Explosives always tear something off; heavy bullets/knife hits can take an arm or, on the legs, the legs.

const HEAVY := 0.3         ## hit worth >= 30% of max hp counts as heavy
const ARM_CHANCE := 0.45   ## heavy torso hit → arm
const LEG_CHANCE := 0.55   ## heavy leg hit → legs (crawler)
const BLAST_LEGS := 0.6    ## explosive: share that takes the legs (rest take an arm)
const BLAST_BOTH := 0.25   ## explosive: share (of the legs ones) that also lose an arm

static func decide(part: String, frac: float, explosive: bool, roll: float, arm_gone := false, crawling := false) -> String:
	var out := ""
	if explosive:
		if roll < BLAST_LEGS and not crawling:
			out = "both" if roll < BLAST_LEGS * BLAST_BOTH and not arm_gone else "legs"
		elif not arm_gone: out = "arm"
		return out
	if frac < HEAVY: return ""
	if part == "legs" and not crawling and roll < LEG_CHANCE: return "legs"
	if part == "body" and not arm_gone and roll < ARM_CHANCE: return "arm"
	return ""
