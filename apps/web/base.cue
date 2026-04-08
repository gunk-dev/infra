package web

import "gunk.dev/armstrong/schema"

_base: schema.#FlyApp & {
	primary_region: string | *"iad"

	http_service: {
		internal_port:  8080
		force_https:    true
		checks: [{
			method:       "GET"
			path:         "/"
			interval:     "30s"
			timeout:      "5s"
			grace_period: "10s"
		}]
	}
}
