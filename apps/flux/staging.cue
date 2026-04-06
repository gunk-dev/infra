@if(staging)
package flux

staging: _base & {
	app:            "flux-staging"
	primary_region: "iad"

	http_service: {
		auto_stop_machines:   "suspend"
		auto_start_machines:  true
		min_machines_running: 1
	}
}
