package main

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
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

	// The first choice of each account comes from this range. It lies below the Windows dynamic ports
	// (49152 and up), which outgoing connections take, and clear of ports that common local servers
	// use, such as 32400 of Plex, 35729 of LiveReload and 44300-44399 of IIS Express.
	preferredPortBase  = 36000
	preferredPortCount = 8000
)

// Fixed ports tried after the account's own, also below the Windows dynamic range. They sit in
// different thousands, so one reserved range rarely covers all of them.
var fallbackPorts = []int{47819, 43819, 39819, 35819, 31819}

var (
	errAlreadyRunning = errors.New("the program on the port claims this data folder but opened no window")
	errWindowRefused  = errors.New("the running instance refused the window request")
	errOtherAccount   = errors.New("the port belongs to Liquidgram of another account")
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
	// Liquidgram with another data folder, which means another account on the computer
	ownerOtherAccount
	// Claims this data folder but does not prove it knows the launch token: an instance that lost its
	// token file or signs differently, or a program that imitates the launcher
	ownerUnproven
	ownerSameInstance
)

var controlClient = &http.Client{
	Timeout:   controlTimeout,
	Transport: &http.Transport{Proxy: nil, DisableKeepAlives: true},
}

// Binds the saved port, the account's own port or the first available fallback one. Stops with a
// `handoffError` when the instance of the same data folder already runs on one of them and opened a
// window instead, and with `errAlreadyRunning` when the program there claims the data folder but
// opened no window. The port returned is the one bound or the one where the launch stopped. The flag
// tells whether Liquidgram of another account holds the saved port.
func acquirePort(savedPort int, instanceID, dataDir string) (net.Listener, int, bool, error) {
	isSavedPortOfOtherAccount := false
	var lastErr error
	for _, port := range listPorts(savedPort, instanceID) {
		listener, err := listenOrHandOff(port, instanceID, dataDir)
		var handoff *handoffError
		if err == nil || errors.As(err, &handoff) || errors.Is(err, errAlreadyRunning) {
			return listener, port, isSavedPortOfOtherAccount, err
		}
		log.Printf("Port %d is unavailable: %v", port, err)
		if port == savedPort && errors.Is(err, errOtherAccount) {
			isSavedPortOfOtherAccount = true
		}
		lastErr = err
	}
	return nil, 0, isSavedPortOfOtherAccount, fmt.Errorf("no port is available: %w", lastErr)
}

// Lists the ports to try: the saved one, the account's own and the fallbacks
func listPorts(savedPort int, instanceID string) []int {
	var ports []int
	for _, port := range append([]int{savedPort, getPreferredPort(instanceID)}, fallbackPorts...) {
		if port != 0 && !slices.Contains(ports, port) {
			ports = append(ports, port)
		}
	}
	return ports
}

// Derives the first choice of the account from its data folder, so accounts that run Liquidgram at
// the same time do not compete for one port. A data folder without a saved port always gets the same
// one, so the derivation must stay unchanged.
func getPreferredPort(instanceID string) int {
	sum := sha256.Sum256([]byte(instanceID))
	return preferredPortBase + int(binary.BigEndian.Uint32(sum[:])%preferredPortCount)
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
		case ownerOtherAccount:
			return nil, fmt.Errorf("%w: %w", errOtherAccount, err)
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
	if err != nil || response.StatusCode != http.StatusOK || ping.App != signatureApp {
		return ownerOtherApp, "", ""
	}
	if ping.Instance != instanceID {
		return ownerOtherAccount, "", ""
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
