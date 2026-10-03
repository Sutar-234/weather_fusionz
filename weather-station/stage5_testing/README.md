# Stage 5 - Testing + Kernel Driver

Build
  make
  make kernel

Load driver
  sudo insmod kernel_module/weather_driver.ko
  cat /dev/weather
  sudo rmmod weather_driver

Test (4 second run)
  ./tests/test.sh

Checks
  No warnings with -Wall -Wextra
  Clean shutdown on SIGINT
  No leaks under valgrind (optional)
