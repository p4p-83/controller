# CV Algorithms
# These turn centroids into machine moves

using Statistics # for `mean()`

function getComplexCentroidsFromVision()::Vector{Vector{ComplexF64}}
	leadsCam = 2
	padsCam = 1


	return [
		[ ComplexF64(normedPixelsToMicrometres(c)...) for c in Vision.getCentroids(camera) ]
		for camera in [leadsCam, padsCam]
	]

	# BUG probable issue: centroids at two edges of the frame will be wrapped around to the other side
	# but this won't really affect the algoritms in their present state
end

function getComponentMotionFromArbitraryMotion(; nominalTranslation_µm::ComplexF64=0.0+0.0j, rotation_rad::Float64=0., centreOfRotation_µm::ComplexF64=0.0+0.0j)::ComponentMotion
	correctiveTranslation_µm = centreOfRotation_µm * (1 - cis(rotation_rad))
	dx_µm, dy_µm = reim.(nominalTranslation_µm + correctiveTranslation_µm)
	rotation_revs = rotation_rad/2π
	return ComponentMotion(dx=dx_µm, dy=dy_µm, dr=rotation_revs)
end

function findRotation(leads, pads ; referenceLeadIndex=1, resolution=3°, selectivity=5)::ComponentMotion
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

	return getComponentMotionFromArbitraryMotion(rotation_rad=rankedAngles[1], centreOfRotation_µm=reference)

end

function wick(leads, pads)::ComponentMotion

	cvMotion = UncalibratedArbitraryMotion()

	#* STEP 0 — PREPARATION
	# find corresponding pad for each lead
	mapping = []
	for l in leads
		deltas = abs.(pads .- l)
		push!(mapping, argmin(deltas))
	end

	#* STEP 1 — REMOVE NET TRANSLATION
	# step 2 requires this gone first
	movements = pads[mapping].-leads
	translation_µm = mean(movements)									#! this is a return value, don't further modify it
	pads .-= translation_µm
	
	#* STEP 2 — REMOVE ROTATION
	# no translational error on pads at present, so we can use them to calculate the centre of rotation
	centreOfRotation = mean(pads[mapping])								#! this is a return value, don't further modify it

	# calculate rotational correction
	subtendedAngles = angle.(pads[mapping].-centreOfRotation) .- angle.(leads.-centreOfRotation)
	meanRotation = mean(subtendedAngles)								#! this is a return value, don't further modify it

	return getComponentMotionFromArbitraryMotion(nominalTranslation_µm=translation_µm, rotation_rad=meanRotation, centreOfRotation_µm=centreOfRotation)
	
end