using Random, Test#, BenchmarkTools

include("../common.jl")
include("algorithms.jl")

j = im
deg = 2π/360	# multiplicative degrees to radians conversion factor

@testset "findRotation dummy resistor 30°" begin
	rotationalMisalignment = 30deg
	
	leads = [
		0+0j
		1+0j
	]

	pads = copy(leads) .* cis(rotationalMisalignment)
	
	correction = findRotation(leads, pads)[1]
	rotationalCorrection = correction.rotation
	
	@test isapprox(rotationalCorrection, 360deg-rotationalMisalignment, atol=2deg)
	
	pads .+= 0.2 + 0.1j
	rotationalCorrection = findRotation(leads, pads)[1].rotation
	@test isapprox(rotationalCorrection, 360deg-rotationalMisalignment, atol=2deg)
	
	pads .-= 0.3 - 0.1j
	rotationalCorrection = findRotation(leads, pads)[1].rotation
	@test isapprox(rotationalCorrection, 360deg-rotationalMisalignment, atol=2deg) broken=true

	pads = 1.2copy(leads) .* cis(rotationalMisalignment)
	rotationalCorrection = findRotation(leads, pads)[1].rotation
	@test isapprox(rotationalCorrection, 360deg-rotationalMisalignment, atol=2deg)

end;

# do not edit directly
# copy/pasted from above 30° set
@testset "findRotation dummy resistor 213°" begin
	rotationalMisalignment = 213deg
	
	leads = [
		0+0j
		1+0j
	]

	pads = copy(leads) .* cis(rotationalMisalignment)
	
	correction = findRotation(leads, pads)[1]
	rotationalCorrection = correction.rotation
	
	@test isapprox(rotationalCorrection, 360deg-rotationalMisalignment, atol=2deg)
	
	pads .+= 0.2 + 0.1j
	rotationalCorrection = findRotation(leads, pads)[1].rotation
	@test isapprox(rotationalCorrection, 360deg-rotationalMisalignment, atol=2deg)
	
	pads .-= 0.3 - 0.1j
	rotationalCorrection = findRotation(leads, pads)[1].rotation
	@test isapprox(rotationalCorrection, 360deg-rotationalMisalignment, atol=2deg) broken=true

	pads = 1.2copy(leads) .* cis(rotationalMisalignment)
	rotationalCorrection = findRotation(leads, pads)[1].rotation
	@test isapprox(rotationalCorrection, 360deg-rotationalMisalignment, atol=2deg)

	# benchmark, 'cause I'm interested
	# display(@benchmark findRotation(leads, pads))

end;

@testset "wick dummy SOIC8" begin
	
	# demo components to ease test board construction
	res::Vector{ComplexF64} = [0, 2]
	soic8::Vector{ComplexF64} = [x + j*y for x in 0:2:8 for y in [0, 6]]

	# create component being placed
	leads::Vector{ComplexF64} = []
	append!(leads, (soic8.-mean(soic8))*cis(45°))

	# create board with picked component and more
	pads = copy(leads)
	append!(pads, j*res.+(-11+5j))
	append!(pads, j*res.+(-8+5j))
	append!(pads, j*res.+(-5+5j))
	Random.seed!(15)
	shuffle!(pads)	# simulate random ordering due to CV etc

	# simulate misalignment (so that this code can fix it)
	headOffset = 0.3+0.4j
	componentPickupOffset = 0.4-0.5j
	rotationOffset = 5deg
	pads .-= headOffset # head won't be in alignment yet
	# pads .*= cis(-2deg) # PCB won't be perfectly square
	leads .-= componentPickupOffset # component won't be picked up perfectly on centre
	leads .*= cis(-rotationOffset) # component won't be in alignment yet
	
	# analyse it
	move = wick(leads, pads)
	# println(move)
	
	# compare with expectations
	expectedCorrectiveTranslation = componentPickupOffset - headOffset
	expectedCorrectiveRotation = rotationOffset
	@test isapprox(move.translation, expectedCorrectiveTranslation, atol=0.0001)
	@test isapprox(move.rotation, expectedCorrectiveRotation, atol=0.01deg)
	
	# benchmark, 'cause I'm interested
	# display(@benchmark wick(leads, pads))

end;

@testset "wick dummy SOIC8 with scale issue" begin
	
	# demo components to ease test board construction
	res::Vector{ComplexF64} = [0, 2]
	soic8::Vector{ComplexF64} = [x + j*y for x in 0:2:8 for y in [0, 6]]

	# create component being placed
	leads::Vector{ComplexF64} = []
	append!(leads, (soic8.-mean(soic8))*cis(45°))

	# create board with picked component and more
	pads = copy(leads)
	append!(pads, j*res.+(-11+5j))
	append!(pads, j*res.+(-8+5j))
	append!(pads, j*res.+(-5+5j))
	Random.seed!(15)
	shuffle!(pads)	# simulate random ordering due to CV etc

	# simulate misalignment (so that this code can fix it)
	headOffset = 0.3+0.3j
	componentPickupOffset = 0j
	rotationOffset = 5deg
	pads .-= headOffset # head won't be in alignment yet
	# pads .*= cis(-2deg) # PCB won't be perfectly square
	leads .*= 0.92
	leads .-= componentPickupOffset # component won't be picked up perfectly on centre
	leads .*= cis(-rotationOffset) # component won't be in alignment yet
	
	# analyse it
	move = wick(leads, pads, plotting=false)
	# println(move)
	
	# compare with expectations
	expectedCorrectiveTranslation = componentPickupOffset - headOffset
	expectedCorrectiveRotation = rotationOffset
	@test isapprox(move.translation, expectedCorrectiveTranslation, atol=0.0001)
	@test isapprox(move.rotation, expectedCorrectiveRotation, atol=0.01deg)

end;