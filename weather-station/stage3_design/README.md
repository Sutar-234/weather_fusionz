# Stage 3 - Design

Architecture

  [3 sensor threads] --> [FusionEngine] --> [TCP server :8080]
                              |
                              v
                        [/dev/weather]

Class diagram

  Sensor (abstract)
    +-- TemperatureSensor
    +-- HumiditySensor
    +-- PressureSensor
  FusionEngine   (mutex-protected state)
  WeatherServer  (accept loop + per-client handler)

Data

  SensorReading { SensorType type; double value; }
  FusedReading  { double t, h, p; int samples; }

Setup

  sudo apt install -y build-essential linux-headers-$(uname -r)
  git init
  git checkout -b develop
