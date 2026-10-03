# Stage 4 - Prototype

Build
  make

Run
  ./weather &
  ./weather-cli
  kill %1

Notes
  Sensors run in 3 threads. FusionEngine guards state with a mutex.
  Server uses one accept loop, handles one client at a time.
