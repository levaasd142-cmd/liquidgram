package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
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
)

// Fixed ports below the Windows dynamic range (49152 and up), so outgoing connections never take
// them. They sit in different thousands, so one reserved range rarely covers all of them. The web app
// lists the same ports in `src/util/desktopLauncher.ts`.
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

// Binds the saved port or the first available default one. Returns `errHandedOff` when an instance
// with the same data folder already runs on one of them and opened a window instead, and
// `errAlreadyRunning` when that instance did not open one.
func acquirePort(savedPort int, instanceID, dataDir string) (net.Listener, int, error) {
	ports := slices.DeleteFunc(slices.Clone(defaultPorts), func(port int) bool { return port == savedPort })
	if savedPort != 0 {
		ports = slices.Insert(ports, 0, savedPort)
	}

	var lastErr error
	for _, port := range ports {
		listener, err := listenOrHandOff(port, instanceID, dataDir)
		if err == nil || errors.Is(err, errHandedOff) || errors.Is(err, errAlreadyRunning) {
			return listener, port, err
		}
		log.Printf("Port %d is unavailable: %v", port, err)
		lastErr = err
	}
	return nil, 0, fmt.Errorf("no port is available: %w", lastErr)
}

// An instance with the same data folder never makes the launcher move to another port, because that
// origin would show an empty profile. Such an instance answers 503 while it shuts down, so the port
// frees up soon, and 403 when the token does not match.
func listenOrHandOff(port int, instanceID, dataDir string) (net.Listener, error) {
	address := net.JoinHostPort(loopbackIP, strconv.Itoa(port))

	var err error
	isSameInstance := false
	refusedRequests := 0
	for attempt := 0; attempt < maxBindAttempts; attempt++ {
		var listener net.Listener
		listener, err = net.Listen("tcp4", address)
		if err == nil {
			return listener, nil
		}

		switch probePortOwner(port, instanceID) {
		case ownerOtherApp:
			return nil, err
		case ownerSameInstance:
			isSameInstance = true
			windowErr := requestWindow(port, readLaunchToken(dataDir))
			if windowErr == nil {
				return nil, errHandedOff
			}
			log.Printf("The running instance on port %d did not open a window: %v", port, windowErr)
			if errors.Is(windowErr, errWindowRefused) {
				refusedRequests++
			}
			if refusedRequests >= maxRefusedRequests {
				return nil, errAlreadyRunning
			}
		case ownerUnknown:
			// One more attempt covers an instance that releases the port right now
			if attempt > 0 && !isSameInstance {
				return nil, err
			}
		}
		time.Sleep(bindRetryDelay)
	}

	if isSameInstance {
		return nil, errAlreadyRunning
	}
	return nil, err
}

func probePortOwner(port int, instanceID string) portOwner {
	response, err := controlClient.Get(buildControlURL(port, pingPath))
	if err != nil {
		return ownerUnknown
	}
	defer response.Body.Close()

	var ping pingResponse
	err = json.NewDecoder(io.LimitReader(response.Body, maxPingBodyBytes)).Decode(&ping)
	if err != nil || response.StatusCode != http.StatusOK || ping.App != signatureApp || ping.Instance != instanceID {
		return ownerOtherApp
	}
	return ownerSameInstance
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
