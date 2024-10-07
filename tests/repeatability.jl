using LibSerialPort
using Images, Dates

##

function cap(shutter)
    img = capture(shutter)
    save("/media/james/STRONTIUM/Repeatability/4.png", img)
end

function capture(shutter=12e-3)
    w = 4608
    h = 2592
    channels = 3 # RGB
    raw = read(`libcamera-still --camera 0 --lens-position 8.4 --nopreview --shutter=$(shutter)s --denoise=cdn_fast --immediate --encoding=rgb --output=-`)
    mat = permutedims(reshape(raw, channels, w, h), (1, 3, 2))
    colorview(RGB{N0f8}, mat)
end

##

gantry = open("/dev/ttyUSB0", 115200)

##
write(gantry, "G28\n")

##

positions = [
    10.0 5.2 0
    2.6 3.4 0
    12.0 6.6 0
    12.0 18.7 0
    11.0 16.3 0
    10.5 16.3 0
    2.0 16.3 0
    22.0 10.0 0
    22.0 18.0 0
] .* 10000
positions = Int.(positions)

write(gantry, "G0 X$(positions[1,1]) Y$(positions[1,2]) Z$(positions[1,3])\n");
sleep(5)
cap(1/10)

##

spins = 500 

for i = 1:spins
    for k = 1:size(positions)[1]
        coord = positions[k, :]
        @time write(gantry, "G0 X$(coord[1]) Y$(coord[2]) Z$(coord[3])\n")
        sleep(10)
        @time img = capture(1 / 10)
        save("/media/james/STRONTIUM/Repeatability/$i-$k.png", img)
        open("/media/james/STRONTIUM/Repeatability/testing_log.txt", "a") do logfile
            println(logfile, "$(Dates.format(now(), "d u yy HH:MM:SS")): captured with i=$i, and k=$k")
            println(logfile, "G0 X$(coord[1]) Y$(coord[2]) Z$(coord[3])\n")
        end
    end
end

##

# @time img = capture(1 / 3)

##

close(gantry)
