package flux

import "gunk.dev/infra/schema"

_base: schema.#FlyApp & {
	primary_region: string | *"iad"

	http_service: {
		internal_port:  8080
		force_https:    true
		checks: alive: {
			method: "GET"
			path:   "/"
			interval: "30s"
			timeout:  "5s"
			grace_period: "10s"
		}
	}
}
