# Weather Station

Linux system that simulates three environmental sensors, fuses
their readings, and serves the result two ways: over a TCP socket and
through a kernel character device. Built as a six-stage project covering
requirements, design, implementation, testing, and delivery.

---

## Run Everything

    sh test.sh

This creates the stage-wise folder tree, installs build tools if
missing, builds stage 6, and runs the test.

---

## Project Layout

    weather-station/
      stage1_introduction/
      stage2_requirements/
      stage3_design/
      stage4_prototype/
      stage5_testing/
      stage6_final/

Each stage is a snapshot of the project at that point. Only stage 6 is
the shipping version. Stages 1-3 are documents only.

---

## Stage 1 - Introduction

Idea and scope. What the project is and what problem it solves.

    cat weather-station/stage1_introduction/README.md

---

## Stage 2 - Requirements

Functional and non-functional requirements. Development plan.

    cat weather-station/stage2_requirements/README.md

---

## Stage 3 - Design

Architecture, class layout, data structures, and setup steps.

    cat weather-station/stage3_design/README.md

---

## Stage 4 - Prototype

Sensors, fusion engine, TCP server, CLI client. No kernel driver yet.

    cd weather-station/stage4_prototype
    make
    ./weather &
    ./weather-cli
    kill %1

---

## Stage 5 - Testing

Adds the kernel character driver and a test script.

    cd weather-station/stage5_testing
    make
    make kernel
    sudo insmod kernel_module/weather_driver.ko
    cat /dev/weather
    sudo rmmod weather_driver
    ./tests/test.sh

---

## Stage 6 - Final

Shipping version. Same code as stage 5, cleaned up.

    cd weather-station/stage6_final
    make
    make kernel

### Run

    sudo insmod kernel_module/weather_driver.ko
    ./weather

In another terminal:

    ./weather-cli

### Inspect the driver

    cat /dev/weather
    dmesg | tail

### Test

    ./tests/test.sh

Runs the server, waits four seconds, queries the client, and shuts down.

### Stop

    Ctrl+C in the server terminal
    sudo rmmod weather_driver

### Clean

    make clean
