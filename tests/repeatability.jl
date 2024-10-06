using LibSerialPort
using Images, Dates

##

function capture(shutter=12e-3)
    w = 4056
    h = 3040
    channels = 3 # RGB
    raw = read(`libcamera-still --nopreview --shutter=$(shutter)s --denoise=cdn_fast --immediate --encoding=rgb --output=-`)
    mat = permutedims(reshape(raw, channels, w, h), (1, 3, 2))
    colorview(RGB{N0f8}, mat)
end

##

# run(`echo "a" > /dev/tty.usbserial-10`)
f = open("/dev/ttyUSB1", 115200)

##

write(f, "G28\n")

##

# positions = 10000 .* [
#     10 10 0
#     12.5 10 0
#     15 12.5 0
#     15 15 0
#     12.5 17.5 0
#     10 17.5 0
#     7.5 15 0
#     7.5 12.5 0
# ]
positions = [
    14.3 11.4 0
    15.7 11.5 0
    16.4 10.2 0
    16.2 13 0
    16 15.8 0
    17.6 20.9 0
    13.2 23 0
    13.2 21.9 0
    12.1 14 0
] .* 10000
positions = Int.(positions)

write(f, "G0 X$(positions[1,1]) Y$(positions[1,2]) Z$(positions[1,3])\n");
sleep(5)

##

coldstarts = 5
spins = 30

for j = 1:coldstarts
    for i = 1:spins
        for k = 1:size(positions)[1]
            coord = positions[k, :]
            @time write(f, "G0 X$(coord[1]) Y$(coord[2]) Z$(coord[3])\n")
            sleep(6)
            @time img = capture(1 / 3)
            save("/media/james/STRONTIUM/Repeatability/$j-$i-$k.png", img)
            open("/media/james/STRONTIUM/Repeatability/testing_log.txt", "a") do logfile
                println(logfile, "$(Dates.format(now(), "d u yy HH:MM:SS")): captured with j=$j, i=$i, and k=$k")
                println(logfile, "G0 X$(coord[1]) Y$(coord[2]) Z$(coord[3])\n")
            end
        end
    end
    write(f, "G28\n")
    sleep(10)
end

##

# @time img = capture(1 / 3)

##

close(f)