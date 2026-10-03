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
