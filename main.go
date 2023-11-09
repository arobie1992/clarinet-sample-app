package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"os"
	"time"

	goclarinet "github.com/arobie1992/go-clarinet"
	"github.com/arobie1992/go-clarinet/control"
	"github.com/arobie1992/go-clarinet/log"
	"github.com/arobie1992/go-clarinet/p2p"
)

func main() {
	go func() {
		if err := goclarinet.Start("config.json"); err != nil {
			log.Log().Fatalf("%s", err)
		}
	}()
	scheduler()
}

// this will be what makes connections and transfers data
func scheduler() {
	fullAddr := p2p.GetFullAddr()
	for fullAddr == "" {
		time.Sleep(1 * time.Second)
		fullAddr = p2p.GetFullAddr()
	}
	log.Log().Infof("Node is now up and running: %s", fullAddr)

	cfg, err := loadConfig("config.json")
	if err != nil {
		log.Log().Fatal("Failed to load config")
	}
	log.Log().Infof("Directory url: %s", cfg.SampleApp.Directory)
	if err := registerWithDirectory(cfg); err != nil {
		log.Log().Fatalf("Failed to register with directory: %s", err)
	}
	for {
		time.Sleep(time.Second * time.Duration(cfg.SampleApp.ActivityPeriodSecs))
		switch rand.Intn(5) {
		case 0:
			initiateConnection(cfg)
		case 1:
			// sendData()
		case 2:
			// closeConnection()
		case 3:
			// query()
		case 4:
			// just idle
		}
	}
}

type peerResponse struct {
	Peer string
}

func initiateConnection(cfg *Config) {
	url := fmt.Sprintf("http://%s/peers/random?requestor=%s", cfg.SampleApp.Directory, p2p.GetFullAddr())
	resp, err := http.Get(url)
	if err != nil {
		log.Log().Errorf("Error while getting random peer: %s", err)
		return
	}

	if resp.StatusCode != http.StatusOK {
		log.Log().Errorf("Resp was not OK: %s", resp.Status)
		return
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Log().Errorf("Failed to read body: %s", err)
	}

	pr := peerResponse{}
	if err := json.Unmarshal(body, &pr); err != nil {
		log.Log().Errorf("Failed to unmarshal body %s: %s", body, err)
	}

	if err := control.RequestConnection(pr.Peer); err != nil {
		log.Log().Errorf("Failed to request connection to %s: %s", pr.Peer, err)
	}
}

type sampleAppConfig struct {
	Directory          string
	NumPeers           int
	ActivityPeriodSecs int
}

type Config struct {
	SampleApp sampleAppConfig
}

func loadConfig(configPath string) (*Config, error) {
	contents, err := os.ReadFile(configPath)
	if err != nil {
		return nil, err
	}
	var config Config
	err = json.Unmarshal(contents, &config)
	if err != nil {
		return nil, err
	}
	return &config, nil
}

type addPeerRequest struct {
	Peer string `json:"peer"`
}

type listPeersResponse struct {
	Peers []string `json:"peers"`
}

func registerWithDirectory(cfg *Config) error {
	req := addPeerRequest{p2p.GetFullAddr()}
	body, err := json.Marshal(req)
	if err != nil {
		return err
	}
	resp, err := http.Post(fmt.Sprintf("http://%s/peers", cfg.SampleApp.Directory), "application/json", bytes.NewBuffer(body))
	if err != nil {
		return err
	}
	if resp.StatusCode != http.StatusOK {
		return errors.New("Failed to register")
	}
	url := fmt.Sprintf("http://%s/peers?numPeers=%d&requestor=%s", cfg.SampleApp.Directory, cfg.SampleApp.NumPeers, p2p.GetFullAddr())
	resp, err = http.Get(url)
	if err != nil {
		return err
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	peersResp := listPeersResponse{}
	if err := json.Unmarshal(data, &peersResp); err != nil {
		return err
	}
	for _, p := range peersResp.Peers {
		if _, err := p2p.AddPeer(p); err != nil {
			log.Log().Warnf("Failed to add peer %s: %s", p, err)
		}
	}
	return nil
}
