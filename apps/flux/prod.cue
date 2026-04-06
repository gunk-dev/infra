@if(prod)
package flux

prod: _base & {
	app:            "flux-prod"
	primary_region: "iad"
	custom_domains: ["flux.gunk.dev"]

	http_service: {
		auto_stop_machines:   "off"
		auto_start_machines:  true
		min_machines_running: 1
	}
}
