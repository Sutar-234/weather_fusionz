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
