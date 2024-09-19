# linear interpolations
# intended for use mapping optical coords to normal coords

# this method is a bit inefficient and suboptimal but I don't think
# it's time-critical enough to bother optimising
# at least this way it's symmetric and fairly easy to use, and that
# counts for something

# example input:
# knownXs = [0, 1, 2, 3]
# knownYs = [1, 3, 5, 8]

# note that this interpolation has an EXACT inverse simply by switching x and y
# i.e. you put your y value in as lookupX, and use (the same) known y vals
# as knwonXs and known x vals as knownXs

# find the y value corresponding to lookupX, given the knownYs that correspond to knownXs
# requires that knownXs are in ascending order and that the function is monotonic
# (valid assumptions for our lens corrections, but you need to check these assumptions
# if you reuse this function for other data)
function interp(lookupX, knownXs, knownYs)

	# handle edge cases where lookupX is outside range of knownXs
	# this function will NOT extrapolate and just chooses the closest value in this case
	if lookupX <= knownXs[1] return knownYs[1] end
	if lookupX >= knownXs[end] return knownYs[end] end

	# must be within bounds
	for n in 1:(length(knownXs)-1)
		trialLowerX = knownXs[n]
		trialUpperX = knownXs[n+1]
		if trialLowerX <= lookupX <= trialUpperX
			# interpolate within this range
			range = trialUpperX - trialLowerX
			fractionLower = (trialUpperX-lookupX)/range
			fractionUpper = 1.0-fractionLower

			lowerY = knownYs[n]
			upperY = knownYs[n+1]
			interpolatedY = fractionLower*lowerY + fractionUpper*upperY

			return interpolatedY
		end
	end

	# should never end up here
	println("interp failed")
	println("got lookupX=$lookupX, knwonXs=$knownXs, knownYs=$knownYs")
	error("buggy code! check interp(…) implementation")

end