# CV Algorithms
# These turn centroids into machine moves

using Statistics # for `mean()`

function findRotation(leads, pads ; referenceLeadIndex=1, resolution=3°, selectivity=5)
	# leads is a list of the lead centroids
	# pads is a list of the pad centroids
	
	reference = leads[referenceLeadIndex]
	pads .-= reference
	leads .-= reference

	binSize = resolution
	numBins = 360°/binSize |> round |> Int
	binSize = 360°/numBins
	binLabels = binSize .* ((1:numBins) .- 0.5)
	bins = zeros(Float64, numBins)

	leadCoords = [(abs(l), angle(l)) for l in leads]

	for p in pads

		rp = abs(p)
		φp = angle(p)
	
		# see which arg bands it might touch
		for (rl, φl) in leadCoords[2:end]
	
			# calculate the quality of the match
			radiusMismatch = rl - rp
			quality = sech(selectivity*radiusMismatch)
	
			# calculate the angle required for this match
			angle = φl - φp
			while angle < 0° angle += 360° end
			while angle >= 360° angle -= 360° end
	
			# find the relevant bin
			binNum = 1 + (angle/binSize |> floor |> Int)
	
			# store in the bin
			bins[binNum] += quality
	
		end
	
	end
	
	binOrdering = sortperm(bins, rev=true)
	rankedAngles = binLabels[binOrdering]

	return CompoundMovement.(ArbitraryRotation.(rankedAngles[1:5], reference))

	# if the desired centre of rotation isn't the actual centre of rotation of the nozzle, it will move
	# calculate the required translation to "catch" it
	# correctiveTranslation = @. reference*(1-cis(rankedAngles))

	# return MachineMovement.(correctiveTranslation, rankedAngles)[1:5]

end

function wick(leads, pads)

	totalMovement = CompoundMovement(0.0+0.0j, 0.0)

	# STEP 0 — PREPARATION
	# find corresponding pad for each lead
	mapping = []
	for l in leads
		deltas = abs.(pads .- l)
		push!(mapping, argmin(deltas))
	end

	# # variables to keep track of the movements we make (so we can apply them to the machine)
	# trackedTranslation::ComplexF64 = 0	# all of this applied to the pads
	# trackedRotation::Float64 = 0	# all of this applied to the leads

	# STEP 1 — REMOVE NET TRANSLATION
	# step 2 requires this gone first
	movements = pads[mapping].-leads
	meanMovement = mean(movements)
	pads .-= meanMovement
	# trackedTranslation += meanMovement
	totalMovement += CompoundMovement(meanMovement)

	movements = leads.-pads[mapping]	#? do I still need these?
	meanMovement = mean(movements)

	# STEP 2 — REMOVE ROTATION
	# no translational error on pads at present, so we can use them to calculate the centre of rotation
	centreOfRotation = mean(pads[mapping])

	# calculate rotational correction
	subtendedAngles = angle.(pads[mapping].-centreOfRotation) .- angle.(leads.-centreOfRotation)
	meanRotation = mean(subtendedAngles)
	totalMovement += CompoundMovement(ArbitraryRotation(meanRotation, centreOfRotation))

	return totalMovement

	# # if the desired centre of rotation isn't the actual centre of rotation of the nozzle, it will move
	# # calculate the required translation to "catch" it
	# correctiveTranslation = centreOfRotation*(1-cis(meanRotation))

	# # make these corrections
	# leads .*= cis(meanRotation)
	# trackedRotation += meanRotation
	# pads .-= correctiveTranslation
	# trackedTranslation += correctiveTranslation

	# return MachineMovement(trackedTranslation, trackedRotation)
	
end