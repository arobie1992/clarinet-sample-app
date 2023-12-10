package metrics

import (
	"bytes"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"sync"
	"time"

	"github.com/arobie1992/go-clarinet/log"
	"github.com/arobie1992/go-clarinet/p2p"
	"github.com/google/uuid"
)

type connectionData struct {
	openTime  *time.Time
	closeTime *time.Time
}

func (cd *connectionData) duration() time.Duration {
	if cd.closeTime == nil {
		return time.Now().Sub(*cd.openTime)
	} else {
		return cd.closeTime.Sub(*cd.openTime)
	}
}

var connections = map[uuid.UUID]connectionData{}
var messages = big.NewFloat(0)
var averageMsgSize = big.NewFloat(0)
var msgLock sync.Mutex
var numQueries = big.NewFloat(0)
var averageQuerySize = big.NewFloat(0)
var averageResponseSize = big.NewFloat(0)
var queryLock sync.Mutex

var one = big.NewFloat(1)

func AddConnOpen(connID uuid.UUID) {
	open := time.Now()
	connections[connID] = connectionData{&open, nil}
}

func AddConnClose(connID uuid.UUID) {
	close := time.Now()
	cd, ok := connections[connID]
	if !ok {
		log.Log().Warnf("No existig connection data for %s. Will not update.", connID)
		return
	}
	if cd.closeTime == nil {
		cd.closeTime = &close
	}
}

func AddMessage(msg []byte) {
	msgLock.Lock()
	defer msgLock.Unlock()
	copy := big.NewFloat(0)
	copy.Copy(averageMsgSize)
	copy.Mul(copy, messages)
	copy.Add(copy, big.NewFloat(float64(len(msg))))
	messages.Add(messages, one)
	copy.Quo(copy, messages)
	averageMsgSize.Set(copy)
}

func AddQuery(query []byte, resp []byte) {
	queryLock.Lock()
	defer queryLock.Unlock()

	queryCopy := big.NewFloat(0)
	queryCopy.Copy(averageQuerySize)

	respCopy := big.NewFloat(0)
	respCopy.Copy(averageResponseSize)

	queryCopy.Mul(queryCopy, numQueries)
	respCopy.Mul(respCopy, numQueries)

	queryCopy.Add(queryCopy, big.NewFloat(float64(len(query))))
	respCopy.Add(respCopy, big.NewFloat(float64(len(resp))))

	numQueries.Add(numQueries, one)
	queryCopy.Quo(queryCopy, numQueries)
	respCopy.Quo(respCopy, numQueries)

	averageQuerySize.Set(queryCopy)
	averageResponseSize.Set(respCopy)
}

// TODO add number of peers discovered
type metricsNotificationRequest struct {
	NodeID           string     `json:"nodeId"`
	NumConnections   int        `json:"numConnections"`
	AvgDurationNanos *big.Float `json:"avgDurationNanos"`
	NumMessages      *big.Float `json:"numMessages"`
	AvgMessageSize   *big.Float `json:"avgMessageSize"`
	NumQueries       *big.Float `json:"numQueries"`
	AvgQuerySize     *big.Float `json:"avgQuerySize"`
	AvgRespSize      *big.Float `json:"avgRespSize"`
	NumPeers         int        `json:"numPeers"`
}

func SendMetrics(directoryHost string) {
	req := metricsNotificationRequest{
		NodeID:           p2p.GetFullAddr(),
		NumConnections:   len(connections),
		AvgDurationNanos: calcAverageDuration(connections),
		NumMessages:      messages,
		AvgMessageSize:   averageMsgSize,
		NumQueries:       numQueries,
		AvgQuerySize:     averageQuerySize,
		AvgRespSize:      averageResponseSize,
		NumPeers:         p2p.GetLibp2pNode().Peerstore().Peers().Len() - 1,
	}
	body, err := json.Marshal(req)
	if err != nil {
		log.Log().Errorf("Error while serializing request: %s", err)
		return
	}
	log.Log().Infof("Serialized metrics: %s", string(body))

	resp, err := http.Post(fmt.Sprintf("http://%s/metrics", directoryHost), "application/json", bytes.NewBuffer(body))
	if err != nil {
		log.Log().Errorf("Error while sending metrics: %s", err)
		return
	}
	if resp.StatusCode != http.StatusOK {
		log.Log().Errorf("Error while sending metrics: Status Code: %d", resp.StatusCode)
	}
}

func calcAverageDuration(connections map[uuid.UUID]connectionData) *big.Float {
	total := big.NewFloat(0)

	for _, cd := range connections {
		total.Add(total, big.NewFloat(float64(cd.duration().Abs().Nanoseconds())))
	}

	if total.Cmp(big.NewFloat(0)) == 0 {
		return total
	}

	return total.Quo(total, big.NewFloat(float64(len(connections))))
}
