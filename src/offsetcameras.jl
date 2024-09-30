

# like coordinate-conversions but we're not worrying about optical distortion
# as we don't have time to properly profile it

mutable struct CameraCalibration

	datumPos_norm::Vector{FI16}					# normalised datum position
	scaleFactor_µm_px::Vector{Float64}			# µm . px⁻¹

	function CameraCalibration(; datumPos_norm=[0., 0.], scaleFactor_µm_px=[1., 1.]) new(datumPos_norm, scaleFactor_µm_px) end

end