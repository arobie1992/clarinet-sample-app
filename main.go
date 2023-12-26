package main

import (
	"bytes"
	crand "crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"time"

	"arobie1992github.com/arobie1992/clarinet-sample-app/metrics"
	goclarinet "github.com/arobie1992/go-clarinet"
	"github.com/arobie1992/go-clarinet/control"
	"github.com/arobie1992/go-clarinet/log"
	"github.com/arobie1992/go-clarinet/p2p"
	"github.com/arobie1992/go-clarinet/repository"
	"github.com/libp2p/go-libp2p/core/peer"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

func main() {
	if len(os.Args) != 2 {
		panic("Must provide config file.")
	}

	cfgFile := os.Args[1]

	go func() {
		if err := goclarinet.Start(cfgFile); err != nil {
			log.Log().Fatalf("%s", err)
		}
	}()
	scheduler(cfgFile)
}

// this will be what makes connections and transfers data
func scheduler(cfgFile string) {
	fullAddr := p2p.GetFullAddr()
	for fullAddr == "" {
		time.Sleep(1 * time.Second)
		fullAddr = p2p.GetFullAddr()
	}
	log.Log().Infof("Node is now up and running: %s", fullAddr)

	cfg, err := loadConfig(cfgFile)
	if err != nil {
		log.Log().Fatal("Failed to load config")
	}
	log.Log().Infof("Directory url: %s", cfg.SampleApp.Directory)
	if err := registerWithDirectory(cfg); err != nil {
		log.Log().Fatalf("Failed to register with directory: %s", err)
	}
	for i := 0; i < cfg.SampleApp.TotalActions; i += 1 {
		time.Sleep(time.Second * time.Duration(cfg.SampleApp.ActivityPeriodSecs))
		log.Log().Infof("Action: %d/%d", i, cfg.SampleApp.TotalActions)
		switch rand.Intn(6) {
		// switch i {
		case 0:
			initiateConnection(cfg)
		case 1:
			sendData()
		case 2:
			closeConnection()
		case 3:
			query()
		case 4:
			requestPeers()
		case 5:
			// just idle
		}
	}
	log.Log().Info("Finished own actions. Send metrics and then just idle and respond to other nodes.")
	metrics.SendMetrics(cfg.SampleApp.Directory)
	c := make(chan os.Signal, 1)
	signal.Notify(c, os.Interrupt)
	<-c
	log.Log().Info("Received keyboard interrupt. Shutting down.")
}

type peerResponse struct {
	Peer string
}

func initiateConnection(cfg *Config) {
	log.Log().Info("Attempting to initiate connection.")
	// might change this to max connections instead
	peer := ""
	for i := 0; i < 5; i++ {
		log.Log().Infof("Attempt %d/5 to get random peer", i)
		possiblePeer, err := randomPeer(cfg)
		if err != nil {
			log.Log().Errorf("Error while getting peer: %s", err)
			continue
		}
		log.Log().Infof("Got possible peer %s", possiblePeer)

		var cnt int64 = 0
		log.Log().Infof("Checking for a connection already to %s", possiblePeer)
		repository.GetDB().Model(&p2p.Connection{}).Where(&p2p.Connection{Receiver: possiblePeer, Status: p2p.ConnectionStatusOpen}).Count(&cnt)
		if cnt == 0 {
			peer = possiblePeer
			break
		}
	}

	if peer == "" {
		log.Log().Warn("Failed to find peer")
		return
	}

	log.Log().Infof("Will attempt to connect to peer %s", peer)
	connID, err := control.RequestConnection(peer)
	if err != nil {
		log.Log().Errorf("Failed to request connection to %s: %s", peer, err)
		return
	}
	log.Log().Infof("Successfully connected to %s", peer)
	metrics.AddConnOpen(connID)
}

func randomPeer(cfg *Config) (string, error) {
	url := fmt.Sprintf("http://%s/peers/random?requestor=%s", cfg.SampleApp.Directory, p2p.GetFullAddr())
	resp, err := http.Get(url)
	if err != nil {
		errMsg := fmt.Sprintf("Error while getting random peer: %s", err)
		return "", errors.New(errMsg)
	}

	if resp.StatusCode != http.StatusOK {
		errMsg := fmt.Sprintf("Resp was not OK: %s", resp.Status)
		return "", errors.New(errMsg)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		errMsg := fmt.Sprintf("Failed to read body: %s", err)
		return "", errors.New(errMsg)
	}

	pr := peerResponse{}
	if err := json.Unmarshal(body, &pr); err != nil {
		errMsg := fmt.Sprintf("Failed to unmarshal body %s: %s", body, err)
		return "", errors.New(errMsg)
	}

	return pr.Peer, nil
}

func sendData() {
	log.Log().Info("Attempting to send data.")
	conn, err := randomOpenOutgoingConnection()
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Log().Info("No open connections to send data on.")
		} else {
			log.Log().Errorf("Encountered error while querying for open outgoing connection: %s", err)
		}
		return
	}

	// make a message that's in the range of 1,000-10,000 random bytes
	size := rand.Intn(9001) + 1000
	msg := make([]byte, size)
	crand.Read(msg)
	if err := p2p.SendData(conn.ID, msg); err != nil {
		log.Log().Errorf("Failed to send data on conn %s: %s", conn.ID, err)
		return
	}
	metrics.AddMessage(msg)
}

func randomOpenOutgoingConnection() (p2p.Connection, error) {
	conn := p2p.Connection{}
	tx := repository.GetDB().
		Where(&p2p.Connection{Sender: p2p.GetFullAddr(), Status: p2p.ConnectionStatusOpen}).
		Clauses(clause.OrderBy{Expression: gorm.Expr("RANDOM()")}).
		Take(&conn)

	if tx.Error != nil {
		return p2p.Connection{}, tx.Error
	}
	return conn, nil
}

func closeConnection() {
	log.Log().Info("Attempting to close a connection.")
	conn, err := randomOpenOutgoingConnection()
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			log.Log().Info("No open connections to close.")
		} else {
			log.Log().Errorf("Encountered error while querying for open outgoing connection: %s", err)
		}
		return
	}
	if err := control.CloseConnection(conn.ID); err != nil {
		log.Log().Errorf("Failed to close connection %s: %s", conn.ID, err)
	}
	metrics.AddConnClose(conn.ID)
}

func query() {
	log.Log().Info("Attempting to query another node for a message.")
	messages := []p2p.DataMessage{}
	tx := repository.GetDB().Model(&p2p.DataMessage{}).Clauses(clause.OrderBy{Expression: gorm.Expr("RANDOM()")}).Limit(1).Find(&messages)
	if len(messages) == 0 {
		log.Log().Info("No messages to query.")
		return
	}
	if tx.Error != nil {
		log.Log().Errorf("Encountered error while attempting to find message to query: %s", tx.Error)
		return
	}
	message := messages[0]
	conn := p2p.Connection{ID: message.ConnID}
	tx = repository.GetDB().Find(&conn)
	if tx.Error != nil {
		log.Log().Errorf("Failed to find connectin %s: %s", conn.ID, tx.Error)
		return
	}
	others := filter(conn.Participants(), func(p string) bool { return p != p2p.GetFullAddr() })

	query, resp, err := control.QueryForMessage(others[rand.Intn(len(others))], conn, message.SeqNo)
	if err != nil {
		log.Log().Errorf("Query for %s:%d failed: %s", message.ConnID, message.SeqNo, err)
	}
	metrics.AddQuery(query, resp)
}

func requestPeers() {
	peers := filter(p2p.GetLibp2pNode().Peerstore().Peers(), func(peerID peer.ID) bool {
		return !strings.Contains(p2p.GetFullAddr(), peerID.String())
	})

	if len(peers) == 0 {
		log.Log().Info("No peers available to request peers from.")
		return
	}

	ind := rand.Intn(len(peers))
	peer := peers[ind]
	addrs := p2p.GetLibp2pNode().Peerstore().Addrs(peer)
	if len(addrs) == 0 {
		log.Log().Warnf("Peer %s has no addresses.", peer)
		return
	}
	addr := addrs[0].String() + "/p2p/" + peer.String()
	if err := control.SendRequestPeersRequest(addr, 10); err != nil {
		log.Log().Errorf("Got error while requesting peers from node %s: %s", addr, err)
	}
}

func filter[T interface{}](vals []T, cond func(T) bool) []T {
	filtered := []T{}
	for _, v := range vals {
		if cond(v) {
			filtered = append(filtered, v)
		}
	}
	return filtered
}

type sampleAppConfig struct {
	Directory          string
	NumPeers           int
	MinPeers           int
	ActivityPeriodSecs float64
	TotalActions       int
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
	for len(p2p.GetLibp2pNode().Peerstore().Peers()) < cfg.SampleApp.MinPeers+1 {
		sleepTime := time.Duration(rand.Intn(500) + 500) * time.Millisecond
		time.Sleep(sleepTime)
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
	}
	log.Log().Info("Got minimum number of peers necessary to proceed")
	return nil
}
