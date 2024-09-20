# code to convert between optical and true coordinates
# essentially provides utilities to handle camera / lens calibrations
# see 0920 Machine state machine — coordinate systems in Sam's logbook for proper discussion

# FILE STATUS
#* THIS FILE IS WRITTEN AND "WORKING", BUT STILL AS-YET UNVERIFIED
# pretty sure that this is correct (I have done the theory) but there's still a chance of sign errors etc
# I still need to come back and check the results against manually-obtained ones
# — that or just whack it on the machine and cross my fingers …

# TODO I need to decide where the calibrations will be stored (once made) — here or elsewhere?
# these particular calibrations are probably "compile-time" in the sense that they should only
# change if the machine is moved, modified or rebuilt.

const j = 1im

include("interp.jl")

struct CalibrationConstants 

	centreOfDistortion_px::ComplexF64					# centre of the distortion
	radialDistortionOpticalValues_px::Vector{Float64}	# normalised values 0-1
														#! (does still probably depend on camera resolution, as not all resolutions have the same FoV)
	radialDistortionTrueValues_mm::Vector{Float64}		# in mm (at normal working distance)
	datum_px::ComplexF64								#! in px for convenience (this is the pixel coord of the datum in the frame)

	function CalibrationConstants(;
		centreOfDistortion_px=0.5+0.5j,
		radialDistortionOpticalValues_px=[0, 1.5],
		radialDistortionTrueValues_mm=[0, 100],
		datum_px=0.5+0.5j
	) new(
		centreOfDistortion_px,
		radialDistortionOpticalValues_px,
		radialDistortionTrueValues_mm,
		datum_px
	) end

end

function getDatumWrtCoD_mm(calibration::CalibrationConstants)
	datumWrtCoD_px = calibration.datum_px - calibration.centreOfDistortion_px
	datumWrtCoD_mm = interpmag(datumWrtCoD_px, calibration.radialDistortionOpticalValues_px, calibration.radialDistortionTrueValues_mm)
	return datumWrtCoD_mm
end

function interpmag(complexCoord::ComplexF64, interpArgs...)
	# interp magnitude using interp()
	# keep the angle the same
	mag = abs.(complexCoord)
	ang = angle.(complexCoord)

	newMag = interp(mag, interpArgs...)

	newCoord = newMag * cis(ang)

end

function opticalToTrue(opticalCoord_px::ComplexF64, calibration::CalibrationConstants)::ComplexF64
	
	# px wrt CoD = px - CoD
	# remove distortion (gets mm wrt CoD from px wrt CoD)
	# mm wrt datum = mm wrt CoD - datum

	datumWrtCoD_mm = getDatumWrtCoD_mm(calibration)
	
	opticalCoordWrtCoD_px = opticalCoord_px - calibration.centreOfDistortion_px	# prepare for distortion correction
	trueCoordWrtCoD_mm = interpmag(opticalCoordWrtCoD_px, calibration.radialDistortionOpticalValues_px, calibration.radialDistortionTrueValues_mm)	# distortion correction made

	trueCoordWrtDatum_mm = trueCoordWrtCoD_mm - datumWrtCoD_mm

	return trueCoordWrtDatum_mm

end

function trueToOptical(trueCoord_mm::ComplexF64, calibration::CalibrationConstants)

	# forwards was:
	# px wrt CoD = px - CoD
	# remove distortion (gets mm wrt CoD from px wrt CoD)
	# mm wrt datum = mm wrt CoD - datum

	# so here we do:
	# mm wrt CoD = mm wrt datum + datum
	# add distortion (gets px wrt CoD from mm wrt CoD)
	# px = px wrt CoD + CoD

	datumWrtCoD_mm = getDatumWrtCoD_mm(calibration)

	trueCoordWrtCoD_mm = trueCoord_mm + datumWrtCoD_mm # prep to reapply distortion
	opticalCoordWrtCoD_px = interpmag(trueCoordWrtCoD_mm, calibration.radialDistortionTrueValues_mm, calibration.radialDistortionOpticalValues_px)	# reapply distortion

	opticalCoord_px = opticalCoordWrtCoD_px + calibration.centreOfDistortion_px
	return opticalCoord_px

end