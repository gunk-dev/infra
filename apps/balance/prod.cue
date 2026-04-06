@if(prod)
package balance

prod: _base & {
	app:            "balance-prod"
	primary_region: "iad"
	custom_domains: ["balance.gunk.dev"]

	http_service: {
		auto_stop_machines:   "off"
		auto_start_machines:  true
		min_machines_running: 1
	}
}
