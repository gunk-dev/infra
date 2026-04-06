@if(prod)
package web

prod: _base & {
	app:            "gunk-web-prod"
	primary_region: "iad"
	custom_domains: ["gunk.dev", "www.gunk.dev"]

	http_service: {
		auto_stop_machines:   "off"
		auto_start_machines:  true
		min_machines_running: 1
	}
}
