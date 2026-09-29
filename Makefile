CXX      := g++
CXXFLAGS := -std=c++17 -Wall -Wextra -pthread -O2

all: weather weather-cli

weather: src/server.cpp
	$(CXX) $(CXXFLAGS) $< -o $@

weather-cli: client/client.cpp
	$(CXX) $(CXXFLAGS) $< -o $@

kernel:
	$(MAKE) -C kernel_module

load: kernel
	sudo insmod kernel_module/weather_driver.ko

unload:
	sudo rmmod weather_driver || true

clean:
	rm -f weather weather-cli
	$(MAKE) -C kernel_module clean

.PHONY: all kernel load unload clean
