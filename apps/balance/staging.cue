@if(staging)
package balance

staging: _base & {
	app:            "balance-staging"
	primary_region: "iad"
	custom_domains: ["staging.balance.gunk.dev"]

	http_service: {
		auto_stop_machines:   "suspend"
		auto_start_machines:  true
		min_machines_running: 1
	}
}
