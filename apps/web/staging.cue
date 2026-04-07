@if(staging)
package web

staging: _base & {
	app:            "gunk-web-staging"
	primary_region: "iad"
	custom_domains: ["staging.web.gunk.dev"]

	http_service: {}
}
