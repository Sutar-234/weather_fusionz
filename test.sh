#!/bin/sh
set -e

PROJ=weather-station
TAB=$(printf '\t')

# ---------- helpers ----------
mkfile() { mkdir -p "$(dirname "$1")"; cat > "$1"; }
apply_tabs() { sed -i.bak "s|@@T@@|$TAB|g" "$1" && rm -f "$1.bak"; }

# ============================================================
# STAGE 1 - INTRODUCTION
# ============================================================
mkdir -p $PROJ/stage1_introduction
mkfile $PROJ/stage1_introduction/README.md <<'EOF'
# Stage 1 - Introduction

Idea: simulated weather station with 3 sensors, a fusion engine,
a TCP server, and a CLI client. Goal: practice Linux system
programming end to end (sensors -> fusion -> sockets).

Scope: userspace only. No real hardware. No persistence.

Outcome: ./weather-cli prints a live weather report.
EOF

# ============================================================
# STAGE 2 - REQUIREMENTS
# ============================================================
mkdir -p $PROJ/stage2_requirements
mkfile $PROJ/stage2_requirements/README.md <<'EOF'
# Stage 2 - Requirements

Functional
  FR1  3 sensors: temperature, humidity, pressure
  FR2  Fusion into one reading
  FR3  TCP server on port 8080
  FR4  CLI client prints a report
  FR5  Ctrl+C shuts down cleanly

Non-functional
  NFR1 Response under 50 ms
  NFR2 No compiler warnings with -Wall -Wextra
  NFR3 No leaks under valgrind

Plan
  Week 1  Intro
  Week 2  Requirements
  Week 3  Design
  Week 4  Prototype
  Week 5  Tests
  Week 6  Final
EOF

# ============================================================
# STAGE 3 - DESIGN
# ============================================================
mkdir -p $PROJ/stage3_design
mkfile $PROJ/stage3_design/README.md <<'EOF'
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
EOF

# ============================================================
# STAGE 4 - PROTOTYPE
# ============================================================
mkdir -p $PROJ/stage4_prototype/src $PROJ/stage4_prototype/client

mkfile $PROJ/stage4_prototype/Makefile <<'MK'
CXX      := g++
CXXFLAGS := -std=c++17 -Wall -Wextra -pthread -O2

all: weather weather-cli

weather: src/server.cpp
@@T@@$(CXX) $(CXXFLAGS) $< -o $@

weather-cli: client/client.cpp
@@T@@$(CXX) $(CXXFLAGS) $< -o $@

clean:
@@T@@rm -f weather weather-cli

.PHONY: all clean
MK
apply_tabs $PROJ/stage4_prototype/Makefile

mkfile $PROJ/stage4_prototype/src/server.cpp <<'SRV'
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

enum class SensorType{TEMP,HUM,PRES};
struct SensorReading{SensorType t;double v;};
struct FusedReading{double t=0,h=0,p=0;int n=0;};

class Sensor{public:Sensor(SensorType t,double b,double n):t_(t),b_(b),n_(n),r_(random_device{}()){}virtual~Sensor()=default;virtual double read()=0;SensorType type()const{return t_;}protected:SensorType t_;double b_,n_;mt19937 r_;};
class TemperatureSensor:public Sensor{public:TemperatureSensor():Sensor(SensorType::TEMP,22.0,0.5){}double read()override{normal_distribution<double>d(b_,n_);return d(r_);}};
class HumiditySensor:public Sensor{public:HumiditySensor():Sensor(SensorType::HUM,55.0,2.0){}double read()override{normal_distribution<double>d(b_,n_);return d(r_);}};
class PressureSensor:public Sensor{public:PressureSensor():Sensor(SensorType::PRES,1013.25,1.5){}double read()override{normal_distribution<double>d(b_,n_);return d(r_);}};

class FusionEngine{public:
  void add(const SensorReading&r){lock_guard<mutex>l(m_);switch(r.t){case SensorType::TEMP:t_=r.v;break;case SensorType::HUM:h_=r.v;break;case SensorType::PRES:p_=r.v;break;}n_++;}
  FusedReading snapshot(){lock_guard<mutex>l(m_);return{t_,h_,p_,n_};}
private:mutex m_;double t_=0,h_=0,p_=0;int n_=0;};

atomic<bool> g_stop{false};
extern "C" void on_sig(int){g_stop.store(true);}

void serve(uint16_t port,FusionEngine&f){
  int fd=socket(AF_INET,SOCK_STREAM,0);if(fd<0){perror("socket");exit(1);}
  int o=1;setsockopt(fd,SOL_SOCKET,SO_REUSEADDR,&o,sizeof(o));
  sockaddr_in a{};a.sin_family=AF_INET;a.sin_addr.s_addr=INADDR_ANY;a.sin_port=htons(port);
  if(bind(fd,(sockaddr*)&a,sizeof(a))<0){perror("bind");exit(1);}
  if(listen(fd,5)<0){perror("listen");exit(1);}
  cout<<"[server] port "<<port<<"\n";cout.flush();
  while(!g_stop.load()){
    int c=accept(fd,nullptr,nullptr);
    if(c<0){if(errno==EINTR)continue;if(g_stop.load())break;continue;}
    char b[64];(void)recv(c,b,63,0);
    auto r=f.snapshot();
    ostringstream o2;o2<<"temperature="<<r.t<<"\n"<<"humidity="<<r.h<<"\n"<<"pressure="<<r.p<<"\n"<<"samples="<<r.n<<"\n";
    string s=o2.str();size_t w=0;
    while(w<s.size()){ssize_t k=send(c,s.c_str()+w,s.size()-w,0);if(k<=0)break;w+=k;}
    close(c);
  }
  close(fd);
}

int main(){
  struct sigaction sa{};sa.sa_handler=on_sig;sigemptyset(&sa.sa_mask);sa.sa_flags=0;
  sigaction(SIGINT,&sa,nullptr);sigaction(SIGTERM,&sa,nullptr);signal(SIGPIPE,SIG_IGN);
  TemperatureSensor t;HumiditySensor h;PressureSensor p;FusionEngine f;
  auto loop=[&](Sensor&s){while(!g_stop.load()){f.add({s.type(),s.read()});this_thread::sleep_for(chrono::milliseconds(200));}};
  thread a(loop,ref(t)),b(loop,ref(h)),c(loop,ref(p));
  serve(8080,f);
  a.join();b.join();c.join();
  cout<<"[server] stopped\n";return 0;
}
SRV

mkfile $PROJ/stage4_prototype/client/client.cpp <<'CLI'
#include <iostream>
#include <iomanip>
#include <sstream>
#include <string>
#include <cstdlib>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
using namespace std;

static string pad(const string&s,size_t w){if(s.size()>=w)return s.substr(0,w);return s+string(w-s.size(),' ');}

int main(int argc,char**argv){
  string host=argc>1?argv[1]:"127.0.0.1";
  int port=argc>2?atoi(argv[2]):8080;
  int fd=socket(AF_INET,SOCK_STREAM,0);
  if(fd<0){perror("socket");return 1;}
  sockaddr_in a{};a.sin_family=AF_INET;a.sin_port=htons(port);inet_pton(AF_INET,host.c_str(),&a.sin_addr);
  if(connect(fd,(sockaddr*)&a,sizeof(a))<0){cerr<<"Cannot connect to "<<host<<":"<<port<<"\n";return 1;}
  send(fd,"GET\n",4,0);
  string data;char buf[512];ssize_t n;
  while((n=recv(fd,buf,511,0))>0){buf[n]='\0';data+=buf;}
  close(fd);
  double t=0,h=0,p=0;int s=0;
  istringstream iss(data);string line;
  while(getline(iss,line)){
    auto eq=line.find('=');if(eq==string::npos)continue;
    string k=line.substr(0,eq),v=line.substr(eq+1);
    try{if(k=="temperature")t=stod(v);else if(k=="humidity")h=stod(v);else if(k=="pressure")p=stod(v);else if(k=="samples")s=stoi(v);}catch(...){}
  }
  const int W=38;
  auto row=[&](const string&x){cout<<"  |"<<pad(x,W)<<"|\n";};
  auto num=[](double v){ostringstream o;o<<fixed<<setprecision(2)<<setw(8)<<v;return o.str();};
  cout<<"\n  +"<<string(W,'-')<<"+\n";
  row("      VIRTUAL WEATHER STATION");
  cout<<"  +"<<string(W,'-')<<"+\n";
  row("   Temperature : "+num(t)+" C");
  row("   Humidity    : "+num(h)+" %");
  row("   Pressure    : "+num(p)+" hPa");
  row("   Samples     : "+to_string(s));
  cout<<"  +"<<string(W,'-')<<"+\n\n";
  return 0;
}
CLI

mkfile $PROJ/stage4_prototype/README.md <<'EOF'
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
EOF

# ============================================================
# STAGE 5 - TESTING + KERNEL DRIVER
# ============================================================
cp -r $PROJ/stage4_prototype $PROJ/stage5_testing
mkdir -p $PROJ/stage5_testing/kernel_module $PROJ/stage5_testing/tests

mkfile $PROJ/stage5_testing/kernel_module/weather_driver.c <<'KDR'
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/uaccess.h>
#include <linux/device.h>
#include <linux/mutex.h>
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("Virtual Weather Station char driver");
#define DEVICE_NAME "weather"
#define CLASS_NAME  "weatherclass"
static int major_num;
static struct class*  weather_class;
static struct device* weather_device;
static struct cdev    weather_cdev;
static struct { int t, h, p, samples; } g_data = { 22000, 55000, 1013250, 0 };
static DEFINE_MUTEX(g_lock);

static ssize_t weather_read(struct file* f, char __user* buf, size_t len, loff_t* off){
  char kbuf[128]; int n;
  mutex_lock(&g_lock);
  n=snprintf(kbuf,sizeof(kbuf),
    "temperature=%d.%03d\nhumidity=%d.%03d\npressure=%d.%03d\nsamples=%d\n",
    g_data.t/1000,g_data.t%1000,g_data.h/1000,g_data.h%1000,g_data.p/1000,g_data.p%1000,g_data.samples);
  mutex_unlock(&g_lock);
  return simple_read_from_buffer(buf,len,off,kbuf,n);
}
static ssize_t weather_write(struct file* f, const char __user* buf, size_t len, loff_t* off){
  char kbuf[128]; if(len>=sizeof(kbuf))return -EINVAL;
  if(copy_from_user(kbuf,buf,len))return -EFAULT;
  kbuf[len]='\0';
  int t,h,p;
  if(sscanf(kbuf,"%d %d %d",&t,&h,&p)==3){
    mutex_lock(&g_lock); g_data.t=t;g_data.h=h;g_data.p=p;g_data.samples++;
    mutex_unlock(&g_lock); return len;
  }
  return -EINVAL;
}
static const struct file_operations fops = { .owner=THIS_MODULE, .read=weather_read, .write=weather_write };

static int __init ws_init(void){
  dev_t dev; if(alloc_chrdev_region(&dev,0,1,DEVICE_NAME)<0)return -1;
  major_num=MAJOR(dev);
  cdev_init(&weather_cdev,&fops); cdev_add(&weather_cdev,dev,1);
  weather_class=class_create(CLASS_NAME);
  weather_device=device_create(weather_class,NULL,dev,NULL,DEVICE_NAME);
  pr_info("weather_driver: /dev/%s ready\n",DEVICE_NAME);
  return 0;
}
static void __exit ws_exit(void){
  device_destroy(weather_class,MKDEV(major_num,0));
  class_destroy(weather_class); cdev_del(&weather_cdev);
  unregister_chrdev_region(MKDEV(major_num,0),1);
  pr_info("weather_driver: unloaded\n");
}
module_init(ws_init);
module_exit(ws_exit);
KDR

mkfile $PROJ/stage5_testing/kernel_module/Makefile <<'KMK'
obj-m += weather_driver.o
KDIR := /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)

all:
@@T@@$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
@@T@@$(MAKE) -C $(KDIR) M=$(PWD) clean
KMK
apply_tabs $PROJ/stage5_testing/kernel_module/Makefile

mkfile $PROJ/stage5_testing/Makefile <<'MK'
CXX      := g++
CXXFLAGS := -std=c++17 -Wall -Wextra -pthread -O2

all: weather weather-cli

weather: src/server.cpp
@@T@@$(CXX) $(CXXFLAGS) $< -o $@

weather-cli: client/client.cpp
@@T@@$(CXX) $(CXXFLAGS) $< -o $@

kernel:
@@T@@$(MAKE) -C kernel_module

load: kernel
@@T@@sudo insmod kernel_module/weather_driver.ko

unload:
@@T@@sudo rmmod weather_driver || true

clean:
@@T@@rm -f weather weather-cli
@@T@@$(MAKE) -C kernel_module clean

.PHONY: all kernel load unload clean
MK
apply_tabs $PROJ/stage5_testing/Makefile

mkfile $PROJ/stage5_testing/tests/test.sh <<'TST'
#!/bin/sh
set -e
make -s
./weather &
PID=$!
sleep 4
OUT=$(./weather-cli)
echo "$OUT"
echo "$OUT" | grep -q "Temperature" || { echo FAIL; kill $PID; exit 1; }
kill -INT $PID
wait $PID 2>/dev/null || true
echo PASS
TST
chmod +x $PROJ/stage5_testing/tests/test.sh

mkfile $PROJ/stage5_testing/README.md <<'EOF'
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
EOF

# ============================================================
# STAGE 6 - FINAL
# ============================================================
cp -r $PROJ/stage5_testing $PROJ/stage6_final

mkfile $PROJ/stage6_final/README.md <<'EOF'
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
EOF

# ============================================================
# TOP-LEVEL README
# ============================================================
mkfile $PROJ/README.md <<'EOF'
# Weather Station Project

Stages
  stage1_introduction   idea and scope
  stage2_requirements   functional and non-functional requirements
  stage3_design         architecture, classes, data
  stage4_prototype      sensors + fusion + server + client
  stage5_testing        kernel driver, tests
  stage6_final          final working project

Each stage has its own README with build and run commands.
Work through them in order. Only stage6_final is meant to ship.
EOF

# ============================================================
# INSTALLER / RUNNER
# ============================================================
cd $PROJ/stage6_final

NEED_INSTALL=0
command -v g++ >/dev/null 2>&1 || NEED_INSTALL=1
[ -f /lib/modules/$(uname -r)/build/Makefile ] || NEED_INSTALL=1

if [ "$NEED_INSTALL" = "1" ]; then
  echo "[setup] installing build tools"
  sudo apt-get update -y >/dev/null
  sudo apt-get install -y build-essential linux-headers-$(uname -r) >/dev/null
fi

echo "[setup] building stage6_final"
make -s

if [ -f /lib/modules/$(uname -r)/build/Makefile ]; then
  make -s kernel || echo "[setup] kernel build skipped or failed"
fi

echo "[setup] running tests/test.sh"
./tests/test.sh
