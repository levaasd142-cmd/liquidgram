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
	controlTimeout   = 3 * time.Second
	maxBindAttempts  = 10
	bindRetryDelay   = 300 * time.Millisecond
	maxPingBodyBytes = 4096
)

// Fixed ports below the Windows dynamic range (49152 and up), so outgoing connections never take
// them. They sit in different thousands, so one reserved range rarely covers all of them. The web app
// lists the same ports in `src/util/desktopLauncher.ts`.
var defaultPorts = []int{47819, 43819, 39819, 35819, 31819}

var errHandedOff = errors.New("handed off to the running instance")

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

// Binds the saved port or the first available default one. Returns `errHandedOff` when the same
// user's instance already runs on one of them and opened a window instead.
func acquirePort(savedPort int, instanceID string) (net.Listener, int, error) {
	ports := slices.DeleteFunc(slices.Clone(defaultPorts), func(port int) bool { return port == savedPort })
	if savedPort != 0 {
		ports = slices.Insert(ports, 0, savedPort)
	}

	var lastErr error
	for _, port := range ports {
		listener, err := listenOrHandOff(port, instanceID)
		if err == nil || errors.Is(err, errHandedOff) {
			return listener, port, err
		}
		log.Printf("Port %d is unavailable: %v", port, err)
		lastErr = err
	}
	return nil, 0, fmt.Errorf("no port is available: %w", lastErr)
}

func listenOrHandOff(port int, instanceID string) (net.Listener, error) {
	address := net.JoinHostPort(loopbackIP, strconv.Itoa(port))

	var err error
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
			// Fails only while that instance shuts down and releases the port
			if requestWindow(port, instanceID) == nil {
				return nil, errHandedOff
			}
		case ownerUnknown:
			// One more attempt covers an instance that releases the port right now
			if attempt > 0 {
				return nil, err
			}
		}
		time.Sleep(bindRetryDelay)
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

func requestWindow(port int, instanceID string) error {
	request, err := http.NewRequest(http.MethodGet, buildControlURL(port, openPath), nil)
	if err != nil {
		return err
	}
	request.Header.Set(instanceHeader, instanceID)

	response, err := controlClient.Do(request)
	if err != nil {
		return err
	}
	response.Body.Close()

	if response.StatusCode != http.StatusNoContent {
		return fmt.Errorf("unexpected response %s", response.Status)
	}
	return nil
}

func buildControlURL(port int, controlPath string) string {
	return "http://" + net.JoinHostPort(loopbackIP, strconv.Itoa(port)) + controlPath
}
