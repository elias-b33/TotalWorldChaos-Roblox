--!strict
-- Seeded random numbers for Sim (Park-Miller "minimal standard" generator).
-- Sim code takes an Rng as an argument and never calls math.random, so tests are deterministic.

local MODULUS = 2147483647 -- 2^31 - 1
local MULTIPLIER = 48271

export type Rng = {
	state: number,
}

local Rng = {}

function Rng.new(seed: number): Rng
	local s = math.floor(math.abs(seed)) % MODULUS
	if s == 0 then
		s = 1
	end
	return { state = s }
end

-- Float in [0, 1).
function Rng.next(rng: Rng): number
	rng.state = (rng.state * MULTIPLIER) % MODULUS
	return (rng.state - 1) / (MODULUS - 1)
end

-- Integer in [lo, hi], both inclusive.
function Rng.int(rng: Rng, lo: number, hi: number): number
	return lo + math.floor(Rng.next(rng) * (hi - lo + 1))
end

-- Float in [lo, hi).
function Rng.range(rng: Rng, lo: number, hi: number): number
	return lo + Rng.next(rng) * (hi - lo)
end

return Rng
