# Virtual Weather Station

Simulated weather sensors + fusion engine + TCP server + kernel driver.

## Build

    make            # userspace binaries
    make kernel     # kernel module

## Run

    sudo insmod kernel_module/weather_driver.ko
    ./weather           # terminal 1
    ./weather-cli       # terminal 2

## Inspect driver

    cat /dev/weather
    dmesg | tail

## Stop

    Ctrl+C in the server terminal, then:
    sudo rmmod weather_driver
