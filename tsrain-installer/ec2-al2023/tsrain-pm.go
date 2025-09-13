package main

import (
  "fmt"
  "flag"
  "log"
  "time"
  "os"
  "io"
  "sync"
  "bytes"
  "strings"
  "encoding/json"
  "crypto/x509"
  "crypto/tls"
  "net"
)

///////////////////////////////////////////////////////////////////////
type Configuration struct {
  Services  struct {
    SmtpPort      int `json:"smtp_port"`
    Imap4Port     int `json:"imap4_port"`
    RainloopPort  int `json:"rainloop_port"`
    ServicePort   int `json:"service_port"`
  } `json:"services"`
  
  ServerCert struct {
    PrivateKeyFile  string  `json:"private_key"`
    CertificateFile string  `json:"certificate"`
  }  `json:"server_cert"`

  ClientCAFiles []string  `json:"client_ca_files"`
}

///////////////////////////////////////////////////////////////////////

type ProtocolMultiplexer struct {
  Config   *Configuration
  TLSConfig *tls.Config
}

func NewProtocolMultiplexer(config *Configuration) *ProtocolMultiplexer {
  pm := &ProtocolMultiplexer {
    Config: config,
    TLSConfig: &tls.Config {
      MinVersion: tls.VersionTLS12,
      RootCAs: x509.NewCertPool(),
      ClientCAs: x509.NewCertPool(),
      ClientAuth: tls.NoClientCert,
    },
  }
  return pm
}

func (pm *ProtocolMultiplexer) SetClientAuthType(authType tls.ClientAuthType) {
  pm.TLSConfig.ClientAuth = authType
}

func (pm *ProtocolMultiplexer) SetServerCertFromFile(certPath string, pkeyPath string) error {
  kcert, err := tls.LoadX509KeyPair(certPath, pkeyPath)
  if err == nil {
    pm.TLSConfig.Certificates = []tls.Certificate{kcert}
  }
  return err
}

func (pm *ProtocolMultiplexer) AddClientCAsFromFile(path string) error {
  cert, err := os.ReadFile(path)
  if err != nil {
    return err
  }
  if !pm.TLSConfig.ClientCAs.AppendCertsFromPEM(cert) {
    return fmt.Errorf("Failed to add ClientCAs.")
  }
  return nil
}

func (pm *ProtocolMultiplexer) ForwardTransaction(lc *tls.Conn) {
  defer lc.Close()

  log.Printf("Connected from: %s", lc.RemoteAddr().String())

  err := lc.Handshake()
  if err != nil {
    log.Printf("Handshake error: %s\n", err)
    return
  }
  // Detect protocol
  var protocol string
  for _, client_cert := range lc.ConnectionState().PeerCertificates {
    cn := client_cert.Subject.CommonName
    if strings.HasPrefix(cn, "imap4") {
      protocol = "imap4"
    } else if strings.HasPrefix(cn, "smtp") {
      protocol = "smtp"
    } else if strings.HasPrefix(cn, "rainloop") {
      protocol = "rainloop"
    }
  }
  var initialBytes []byte
  if protocol == "" {
    initialBytes = make([]byte, 3)
    lc.SetReadDeadline(time.Now().Add(3 * time.Second))
    n, err := lc.Read(initialBytes)
    initialBytes = initialBytes[:n]
    lc.SetDeadline(time.Time{})
    
    if n > 0 {
      if bytes.EqualFold(initialBytes, []byte("EHLO"[:n])) {
        // EHLO or ehlo
        protocol = "smtp"
      }else if n >= 3 && bytes.EqualFold(initialBytes, []byte("HELO"[:n])) {
        // HELO or helo
        protocol = "smtp"
      } else {
        protocol = "rainloop"
      }
    } else if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
      // Waiting for SMTP or IMAP greeting, but we don't suuport IMAP in auto detection
      protocol = "smtp"
      log.Print(err)
    } else {
      log.Print(err)
      return
    }
  }
  portMap := map[string]int{
    "smtp": pm.Config.Services.SmtpPort,
    "imap4": pm.Config.Services.Imap4Port,
    "rainloop": pm.Config.Services.RainloopPort,
  }
  // Connect to the remote host
  dialer := net.Dialer{
    Timeout: 5 * time.Second,
  }
  rc, err := dialer.Dial("tcp", fmt.Sprintf("127.0.0.1:%d", portMap[protocol]))
  if err != nil {
    log.Print(err)
    return
  }
  defer rc.Close()

  // Fowarding
  if initialBytes != nil && len(initialBytes) != 0 {
    if _, err := rc.Write(initialBytes); err != nil {
      log.Print(err)
      return
    }
  }
  var wg sync.WaitGroup
  wg.Add(2)
  
  go func() {
    defer wg.Done()
    _, _ = io.Copy(rc, lc)
  }()

  go func() {
    defer wg.Done()
    _, _ = io.Copy(lc, rc)
  }()
  
  wg.Wait()
}

func (pm *ProtocolMultiplexer) ServeForever(host string, port int) {
  svr, err := tls.Listen("tcp", fmt.Sprintf("%s:%d", host, port), pm.TLSConfig)
  if err != nil {
    log.Panicln(err)
  }
  defer svr.Close()
  
  for {
    conn, err := svr.Accept()
    if err != nil {
      log.Println(err)
      continue
    }
    defer conn.Close()
    
    tlscon, ok := conn.(*tls.Conn)
    if ok {
      go pm.ForwardTransaction(tlscon)
    }
  }
}

///////////////////////////////////////////////////////////////////////

func main() {
  var opts struct {
    ConfigFile string
  }
  flag.StringVar(&opts.ConfigFile, "f", "", "The file path for the configuration.")
  flag.Parse()
  if opts.ConfigFile == "" {
    flag.PrintDefaults()
    return
  }
  // Load the configuration
  var config Configuration
  {
    bin, err := os.ReadFile(opts.ConfigFile)
    if err != nil {
      log.Panic(err)
    }
    err = json.Unmarshal(bin, &config)
    if err != nil {
      log.Panic(err)
    }
  }
  // Start the server
  service_port := config.Services.ServicePort

  if service_port <= 0 || service_port >= 65535 {
    log.Panicf("Invalid service port: %d\n", service_port)
  }
  pm := NewProtocolMultiplexer(&config)
  if err := pm.SetServerCertFromFile(
    config.ServerCert.CertificateFile,
    config.ServerCert.PrivateKeyFile,
  ); err != nil {
    log.Panic(err)
  }
  for _, path := range config.ClientCAFiles {
    if err := pm.AddClientCAsFromFile(path); err != nil {
      log.Panic(err)
    }
  }
  pm.SetClientAuthType(tls.VerifyClientCertIfGiven)
  
  log.Printf("The service is about to start on port %d", service_port)
  pm.ServeForever("", service_port)
}
