CXX      := g++
CXXFLAGS := -std=c++17 -Wall -Wextra -pthread -O2

all: weather weather-cli

weather: src/server.cpp
	$(CXX) $(CXXFLAGS) $< -o $@

weather-cli: client/client.cpp
	$(CXX) $(CXXFLAGS) $< -o $@

clean:
	rm -f weather weather-cli

.PHONY: all clean
