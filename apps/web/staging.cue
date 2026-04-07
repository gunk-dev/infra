@if(staging)
package web

staging: _base & {
	app:            "gunk-web-staging"
	primary_region: "iad"
	custom_domains: ["staging.web.gunk.dev"]

	http_service: {
		auto_stop_machines:   "suspend"
		auto_start_machines:  true
		min_machines_running: 0
	}
}
