@if(prod)
package web

prod: _base & {
	app:            "gunk-web-prod"
	primary_region: "iad"
	custom_domains: ["gunk.dev", "www.gunk.dev"]

	http_service: {
		min_machines_running: 1
	}
}
