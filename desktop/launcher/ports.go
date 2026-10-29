package main

import (
	"crypto/hmac"
	"crypto/rand"
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
	maxRejections    = 3
	bindRetryDelay   = 300 * time.Millisecond
	maxPingBodyBytes = 4096
)

// Fixed ports below the Windows dynamic range (49152 and up), so outgoing connections never take
// them. They sit in different thousands, so one reserved range rarely covers all of them.
var defaultPorts = []int{47819, 43819, 39819, 35819, 31819}

var (
	errAlreadyRunning = errors.New("the program on the port claims this data folder but opened no window")
	errWindowRefused  = errors.New("the running instance refused the window request")
)

// Reports that the instance of the same data folder already runs and opened a window for this launch
type handoffError struct {
	// The build of the running instance, which may differ from this one after an update
	build string
}

func (e *handoffError) Error() string {
	return "the running instance opened a window"
}

type portOwner int

const (
	ownerUnknown portOwner = iota
	ownerOtherApp
	// Claims this data folder but does not prove it knows the launch token: an instance that lost its
	// token file or signs differently, or a program that imitates the launcher
	ownerUnproven
	ownerSameInstance
)

var controlClient = &http.Client{
	Timeout:   controlTimeout,
	Transport: &http.Transport{Proxy: nil, DisableKeepAlives: true},
}

// Binds the saved port or the first available default one. Stops with a `handoffError` when the
// instance of the same data folder already runs on one of them and opened a window instead, and with
// `errAlreadyRunning` when the program there claims the data folder but opened no window. The port
// returned is the one bound or the one where the launch stopped.
func acquirePort(savedPort int, instanceID, dataDir string) (net.Listener, int, error) {
	ports := slices.DeleteFunc(slices.Clone(defaultPorts), func(port int) bool { return port == savedPort })
	if savedPort != 0 {
		ports = slices.Insert(ports, 0, savedPort)
	}

	var lastErr error
	for _, port := range ports {
		listener, err := listenOrHandOff(port, instanceID, dataDir)
		var handoff *handoffError
		if err == nil || errors.As(err, &handoff) || errors.Is(err, errAlreadyRunning) {
			return listener, port, err
		}
		log.Printf("Port %d is unavailable: %v", port, err)
		lastErr = err
	}
	return nil, 0, fmt.Errorf("no port is available: %w", lastErr)
}

// A program that claims the same data folder never makes the launcher move to another port, because
// that origin would show an empty profile. A program that only imitates the launcher can keep it from
// starting this way, but holding all of its ports does that as well. An instance answers 503 while it
// shuts down, so the port frees up soon, and 403 when the token does not match.
func listenOrHandOff(port int, instanceID, dataDir string) (net.Listener, error) {
	address := net.JoinHostPort(loopbackIP, strconv.Itoa(port))

	var err error
	isSameFolder := false
	rejections := 0
	for attempt := 0; attempt < maxBindAttempts && rejections < maxRejections; attempt++ {
		if attempt > 0 {
			time.Sleep(bindRetryDelay)
		}

		var listener net.Listener
		listener, err = net.Listen("tcp4", address)
		if err == nil {
			return listener, nil
		}

		owner, runningBuild, launchToken := probePortOwner(port, instanceID, dataDir)
		switch owner {
		case ownerOtherApp:
			return nil, err
		case ownerUnproven:
			log.Printf("The program on port %d claims this data folder but does not prove it knows its token", port)
			isSameFolder = true
			rejections++
		case ownerSameInstance:
			isSameFolder = true
			// The running instance opens the window, so it gets this launch's right to bring it to the front
			allowAnyForeground()
			windowErr := requestWindow(port, launchToken)
			if windowErr == nil {
				return nil, &handoffError{build: runningBuild}
			}
			log.Printf("The running instance on port %d did not open a window: %v", port, windowErr)
			if errors.Is(windowErr, errWindowRefused) {
				rejections++
			}
		case ownerUnknown:
			// One more attempt covers an instance that releases the port right now
			if attempt > 0 && !isSameFolder {
				return nil, err
			}
		}
	}

	if isSameFolder {
		return nil, errAlreadyRunning
	}
	return nil, err
}

// Asks the program on the port who it is and returns its build and the launch token to present to it.
// An instance of this data folder proves it knows the token of its port, which is read only after the
// answer: the instance writes it before it starts serving.
func probePortOwner(port int, instanceID, dataDir string) (portOwner, string, string) {
	nonce := rand.Text()
	response, err := controlClient.Get(buildControlURL(port, pingPath) + "?nonce=" + nonce)
	if err != nil {
		return ownerUnknown, "", ""
	}
	defer response.Body.Close()

	var ping pingResponse
	err = json.NewDecoder(io.LimitReader(response.Body, maxPingBodyBytes)).Decode(&ping)
	if err != nil || response.StatusCode != http.StatusOK || ping.App != signatureApp || ping.Instance != instanceID {
		return ownerOtherApp, "", ""
	}

	launchToken := readLaunchToken(dataDir, port)
	if launchToken == "" || !hmac.Equal([]byte(ping.Proof), []byte(signPingNonce(launchToken, port, nonce))) {
		return ownerUnproven, "", ""
	}
	return ownerSameInstance, ping.Build, launchToken
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
