# Stage 6 - Final

Build
  make
  make kernel

Run
  sudo insmod kernel_module/weather_driver.ko
  ./weather
  ./weather-cli

Test
  ./tests/test.sh

Stop
  Ctrl+C in server terminal
  sudo rmmod weather_driver

Clean
  make clean
