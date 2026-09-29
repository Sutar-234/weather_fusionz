// weather-station/src/server.cpp
// Virtual Weather Station — server
// Build: g++ -std=c++17 -pthread src/server.cpp -o weather

#include <iostream>
#include <thread>
#include <mutex>
#include <atomic>
#include <chrono>
#include <random>
#include <sstream>
#include <string>
#include <cerrno>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <csignal>

using namespace std;

enum class SensorType { TEMP, HUM, PRES };

struct SensorReading { SensorType type; double value; };

struct FusedReading {
    double temperature = 0.0;
    double humidity    = 0.0;
    double pressure    = 0.0;
    int    samples     = 0;
};

class Sensor {
public:
    Sensor(SensorType t, double base, double noise)
        : type_(t), base_(base), noise_(noise), rng_(random_device{}()) {}
    virtual ~Sensor() = default;
    virtual double read() = 0;
    SensorType type() const { return type_; }
protected:
    SensorType type_;
    double     base_, noise_;
    mt19937    rng_;
};

class TemperatureSensor : public Sensor {
public:
    TemperatureSensor() : Sensor(SensorType::TEMP, 22.0, 0.5) {}
    double read() override {
        normal_distribution<double> d(base_, noise_);
        return d(rng_);
    }
};

class HumiditySensor : public Sensor {
public:
    HumiditySensor() : Sensor(SensorType::HUM, 55.0, 2.0) {}
    double read() override {
        normal_distribution<double> d(base_, noise_);
        return d(rng_);
    }
};

class PressureSensor : public Sensor {
public:
    PressureSensor() : Sensor(SensorType::PRES, 1013.25, 1.5) {}
    double read() override {
        normal_distribution<double> d(base_, noise_);
        return d(rng_);
    }
};

class FusionEngine {
public:
    void add(const SensorReading& r) {
        lock_guard<mutex> lock(mtx_);
        switch (r.type) {
            case SensorType::TEMP: temp_ = r.value; break;
            case SensorType::HUM:  hum_  = r.value; break;
            case SensorType::PRES: pres_ = r.value; break;
        }
        samples_++;
    }
    FusedReading snapshot() {
        lock_guard<mutex> lock(mtx_);
        FusedReading out;
        out.temperature = temp_;
        out.humidity    = hum_;
        out.pressure    = pres_;
        out.samples     = samples_;
        return out;
    }
private:
    mutex  mtx_;
    double temp_ = 0.0, hum_ = 0.0, pres_ = 0.0;
    int    samples_ = 0;
};

atomic<bool> g_shutdown{false};
extern "C" void on_signal(int) { g_shutdown.store(true); }

class WeatherServer {
public:
    WeatherServer(uint16_t port, FusionEngine& f)
        : port_(port), fusion_(f) {}

    void start() {
        int fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) { perror("socket"); exit(1); }

        int opt = 1;
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

        sockaddr_in addr{};
        addr.sin_family      = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port        = htons(port_);

        if (bind(fd, (sockaddr*)&addr, sizeof(addr)) < 0) {
            perror("bind"); exit(1);
        }
        if (listen(fd, 5) < 0) { perror("listen"); exit(1); }

        cout << "[server] listening on port " << port_ << "\n";
        cout.flush();

        while (!g_shutdown.load()) {
            int c = accept(fd, nullptr, nullptr);
            if (c < 0) {
                if (errno == EINTR) continue;
                if (g_shutdown.load()) break;
                continue;
            }

            char buf[64];
            (void)recv(c, buf, sizeof(buf) - 1, 0);

            FusedReading r = fusion_.snapshot();
            ostringstream oss;
            oss << "temperature=" << r.temperature << "\n"
                << "humidity="    << r.humidity    << "\n"
                << "pressure="    << r.pressure    << "\n"
                << "samples="     << r.samples     << "\n";

            string resp = oss.str();
            size_t sent = 0;
            while (sent < resp.size()) {
                ssize_t n = send(c, resp.c_str() + sent,
                                 resp.size() - sent, 0);
                if (n <= 0) break;
                sent += n;
            }
            close(c);
        }
        close(fd);
    }

private:
    uint16_t      port_;
    FusionEngine& fusion_;
};

int main() {
    struct sigaction sa{};
    sa.sa_handler = on_signal;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;

    sigaction(SIGINT,  &sa, nullptr);
    sigaction(SIGTERM, &sa, nullptr);
    signal(SIGPIPE, SIG_IGN);

    TemperatureSensor temp;
    HumiditySensor    hum;
    PressureSensor    pres;
    FusionEngine      fusion;

    auto loop = [&](Sensor& s) {
        while (!g_shutdown.load()) {
            fusion.add({s.type(), s.read()});
            this_thread::sleep_for(chrono::milliseconds(200));
        }
    };

    thread t1(loop, ref(temp));
    thread t2(loop, ref(hum));
    thread t3(loop, ref(pres));

    WeatherServer server(8080, fusion);
    server.start();

    t1.join(); t2.join(); t3.join();
    cout << "[server] shutdown complete\n";
    return 0;
}
