savedcmd_weather_driver.mod := printf '%s\n'   weather_driver.o | awk '!x[$$0]++ { print("./"$$0) }' > weather_driver.mod
