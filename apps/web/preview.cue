@if(preview)
package web

preview: _base & {
	app:            string | *"gunk-web-preview" @tag(appName)
	primary_region: "iad"

	http_service: {
		auto_stop_machines:   "suspend"
		auto_start_machines:  true
		min_machines_running: 0
	}
}
