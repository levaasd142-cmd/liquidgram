package main

import (
	"crypto/hmac"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"time"
)

const (
	controlTimeout     = 3 * time.Second
	maxBindAttempts    = 10
	maxRefusedRequests = 3
	bindRetryDelay     = 300 * time.Millisecond
	maxPingBodyBytes   = 4096
	nonceBytes         = 16
)

// Fixed ports below the Windows dynamic range (49152 and up), so outgoing connections never take
// them. They sit in different thousands, so one reserved range rarely covers all of them.
var defaultPorts = []int{47819, 43819, 39819, 35819, 31819}

var (
	errHandedOff      = errors.New("handed off to the running instance")
	errAlreadyRunning = errors.New("the running instance did not open a window")
	errWindowRefused  = errors.New("the running instance refused the window request")
)

type portOwner int

const (
	ownerUnknown portOwner = iota
	ownerOtherApp
	ownerSameInstance
)

var controlClient = &http.Client{
	Timeout:   controlTimeout,
	Transport: &http.Transport{Proxy: nil, DisableKeepAlives: true},
}

// Binds the saved port or the first available default one. Returns `errHandedOff` with the version of
// the instance of the same data folder that already runs on one of them and opened a window instead,
// and `errAlreadyRunning` when that instance did not open one.
func acquirePort(savedPort int, instanceID, dataDir string) (net.Listener, int, string, error) {
	ports := slices.DeleteFunc(slices.Clone(defaultPorts), func(port int) bool { return port == savedPort })
	if savedPort != 0 {
		ports = slices.Insert(ports, 0, savedPort)
	}

	var lastErr error
	for _, port := range ports {
		listener, runningVersion, err := listenOrHandOff(port, instanceID, dataDir)
		if err == nil || errors.Is(err, errHandedOff) || errors.Is(err, errAlreadyRunning) {
			return listener, port, runningVersion, err
		}
		log.Printf("Port %d is unavailable: %v", port, err)
		lastErr = err
	}
	return nil, 0, "", fmt.Errorf("no port is available: %w", lastErr)
}

// An instance with the same data folder never makes the launcher move to another port, because that
// origin would show an empty profile. Such an instance answers 503 while it shuts down, so the port
// frees up soon, and 403 when the token does not match.
func listenOrHandOff(port int, instanceID, dataDir string) (net.Listener, string, error) {
	address := net.JoinHostPort(loopbackIP, strconv.Itoa(port))

	var err error
	isSameInstance := false
	refusedRequests := 0
	for attempt := 0; attempt < maxBindAttempts; attempt++ {
		var listener net.Listener
		listener, err = net.Listen("tcp4", address)
		if err == nil {
			return listener, "", nil
		}

		owner, ping, launchToken := probePortOwner(port, instanceID, dataDir)
		switch owner {
		case ownerOtherApp:
			return nil, "", err
		case ownerSameInstance:
			isSameInstance = true
			windowErr := requestWindow(port, launchToken)
			if windowErr == nil {
				return nil, ping.Version, errHandedOff
			}
			log.Printf("The running instance on port %d did not open a window: %v", port, windowErr)
			if errors.Is(windowErr, errWindowRefused) {
				refusedRequests++
			}
			if refusedRequests >= maxRefusedRequests {
				return nil, "", errAlreadyRunning
			}
		case ownerUnknown:
			// One more attempt covers an instance that releases the port right now
			if attempt > 0 && !isSameInstance {
				return nil, "", err
			}
		}
		time.Sleep(bindRetryDelay)
	}

	if isSameInstance {
		return nil, "", errAlreadyRunning
	}
	return nil, "", err
}

// Asks the program on the port who it is. An instance of this data folder proves it knows the launch
// token, which is read only after the answer: the instance writes a new one before it starts serving.
func probePortOwner(port int, instanceID, dataDir string) (portOwner, pingResponse, string) {
	var ping pingResponse

	nonce := make([]byte, nonceBytes)
	if _, err := rand.Read(nonce); err != nil {
		return ownerUnknown, ping, ""
	}
	nonceText := hex.EncodeToString(nonce)

	response, err := controlClient.Get(buildControlURL(port, pingPath) + "?nonce=" + url.QueryEscape(nonceText))
	if err != nil {
		return ownerUnknown, ping, ""
	}
	defer response.Body.Close()

	err = json.NewDecoder(io.LimitReader(response.Body, maxPingBodyBytes)).Decode(&ping)
	if err != nil || response.StatusCode != http.StatusOK || ping.App != signatureApp || ping.Instance != instanceID {
		return ownerOtherApp, ping, ""
	}

	launchToken := readLaunchToken(dataDir)
	expectedProof := signPingNonce(launchToken, nonceText)
	if launchToken == "" || !hmac.Equal([]byte(ping.Proof), []byte(expectedProof)) {
		log.Printf("The program on port %d claims this data folder but does not know its token", port)
		return ownerOtherApp, ping, ""
	}
	return ownerSameInstance, ping, launchToken
}

func requestWindow(port int, launchToken string) error {
	request, err := http.NewRequest(http.MethodGet, buildControlURL(port, openPath), nil)
	if err != nil {
		return err
	}
	request.Header.Set(tokenHeader, launchToken)

	response, err := controlClient.Do(request)
	if err != nil {
		return err
	}
	response.Body.Close()

	switch response.StatusCode {
	case http.StatusNoContent:
		return nil
	case http.StatusForbidden:
		return errWindowRefused
	default:
		return fmt.Errorf("unexpected response %s", response.Status)
	}
}

func buildControlURL(port int, controlPath string) string {
	return "http://" + net.JoinHostPort(loopbackIP, strconv.Itoa(port)) + controlPath
}
