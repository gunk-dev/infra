package valleyweb

import "gunk.dev/armstrong/schema"

// One Machine runs valley-web-receive and valley-web over one volume (see
// valley-web-edge in flake.nix). A Fly volume belongs to one Machine, so
// the app never scales out, and the Machine never stops: the valley host
// pushes whenever it likes.
_base: schema.#FlyApp & {
	primary_region: string | *"yyz"

	experimental: cmd: [
		"/bin/valley-web-edge",
		"--instance", "classic-laddie",
		"--destination", "broken.dev",
		// Below the volume's size: the volume is the hard bound.
		"--max-storage", "4G",
	]

	// The receiver takes up to 15s to stop.
	kill_signal:  "SIGTERM"
	kill_timeout: 20

	vm: [{
		size:   "shared-cpu-1x"
		memory: "1gb"
	}]

	mounts: {
		source:       "valley_web_state"
		destination:  "/var/lib/valley-web"
		initial_size: "5gb"
	}

	files: [{
		guest_path:  "/etc/valley-web/token"
		secret_name: "VALLEY_WEB_RECEIVER_TOKEN"
	}, {
		guest_path: "/etc/valley-web/verifiers"
		local_path: "apps/valley-web/verifiers"
	}]

	http_service: {
		internal_port:        8080
		force_https:          true
		auto_stop_machines:   "off"
		auto_start_machines:  true
		min_machines_running: 1
	}

	// The receiver, for the publisher. Fly terminates TLS and passes plain
	// HTTP/1.1 through, which is all the receiver speaks.
	services: [{
		internal_port:        8081
		protocol:             "tcp"
		auto_stop_machines:   "off"
		auto_start_machines:  true
		min_machines_running: 1
		ports: [{
			port: 8443
			handlers: ["tls"]
			tls_options: alpn: ["http/1.1"]
		}]
	}]

	// valley-web answers 503 on every path until the first export is
	// active, so both checks are TCP.
	checks: {
		web: {
			type:         "tcp"
			port:         8080
			interval:     "15s"
			timeout:      "2s"
			grace_period: "10s"
		}
		receive: {
			type:         "tcp"
			port:         8081
			interval:     "15s"
			timeout:      "2s"
			grace_period: "10s"
		}
	}
}
