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

	return UncalibratedArbitraryMotion.(rotation=rankedAngles[1:5], centreOfRotation=[reim(reference)...])

end

function wick(leads, pads)

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
	meanMovement = mean(movements)
	
	pads .-= meanMovement
	cvMotion.translation = [reim(meanMovement)...]
	
	#* STEP 2 — REMOVE ROTATION
	# no translational error on pads at present, so we can use them to calculate the centre of rotation
	centreOfRotation = mean(pads[mapping])

	# calculate rotational correction
	subtendedAngles = angle.(pads[mapping].-centreOfRotation) .- angle.(leads.-centreOfRotation)
	meanRotation = mean(subtendedAngles)

	cvMotion.rotation = meanRotation
	cvMotion.centreOfRotation = [reim(centreOfRotation)...]

	return cvMotion
	
end