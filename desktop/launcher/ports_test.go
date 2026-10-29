package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"slices"
	"testing"
)

const (
	testDataDirAlice = `C:\Users\Alice\AppData\Local\Liquidgram`
	testDataDirBob   = `C:\Users\Bob\AppData\Local\Liquidgram`
)

func TestPreferredPortPerAccount(t *testing.T) {
	// Pinned, because a data folder without a saved port has to come back to the same port
	for dataDir, want := range map[string]int{testDataDirAlice: 40479, testDataDirBob: 40847} {
		if port := getPreferredPort(buildInstanceID(dataDir)); port != want {
			t.Errorf("%s: port %d, want %d", dataDir, port, want)
		}
	}

	const accountCount = 2000
	ports := make(map[int]bool)
	for i := range accountCount {
		port := getPreferredPort(buildInstanceID(fmt.Sprintf(`C:\Users\User%d\AppData\Local\Liquidgram`, i)))
		if port < preferredPortBase || port >= preferredPortBase+preferredPortCount {
			t.Fatalf("port %d is outside the range", port)
		}
		ports[port] = true
	}
	// Uniform choices give about 1770 distinct ports
	if len(ports) < 1500 {
		t.Errorf("%d accounts share %d ports", accountCount, len(ports))
	}
}

func TestListPorts(t *testing.T) {
	instanceID := buildInstanceID(testDataDirAlice)
	tests := []struct {
		savedPort int
		want      []int
	}{
		{0, []int{40479, 47819, 43819, 39819, 35819, 31819}},
		// A config of an earlier version keeps its port
		{47819, []int{47819, 40479, 43819, 39819, 35819, 31819}},
		{40479, []int{40479, 47819, 43819, 39819, 35819, 31819}},
		{50000, []int{50000, 40479, 47819, 43819, 39819, 35819, 31819}},
	}

	for _, test := range tests {
		if ports := listPorts(test.savedPort, instanceID); !slices.Equal(ports, test.want) {
			t.Errorf("saved port %d: %v, want %v", test.savedPort, ports, test.want)
		}
	}
}

func TestRecognizeOtherAccount(t *testing.T) {
	tests := []struct {
		name           string
		status         int
		ping           any
		isOtherAccount bool
	}{
		{"Liquidgram of another account", http.StatusOK, pingResponse{App: signatureApp, Instance: "other"}, true},
		{"another program", http.StatusOK, map[string]string{"status": "ok"}, false},
		{"a web server", http.StatusNotFound, nil, false},
	}

	for _, test := range tests {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(test.status)
			json.NewEncoder(w).Encode(test.ping)
		}))
		port := server.Listener.Addr().(*net.TCPAddr).Port

		listener, err := listenOrHandOff(port, testInstance, t.TempDir())
		server.Close()
		if listener != nil {
			listener.Close()
			t.Errorf("%s: bound the port of the server", test.name)
		}
		if err == nil || errors.Is(err, errOtherAccount) != test.isOtherAccount {
			t.Errorf("%s: error %v", test.name, err)
		}
	}
}
