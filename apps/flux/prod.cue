@if(prod)
package flux

prod: _base & {
	app:            "flux-prod"
	primary_region: "iad"

	http_service: {
		auto_stop_machines:   "off"
		auto_start_machines:  true
		min_machines_running: 1
	}
}
