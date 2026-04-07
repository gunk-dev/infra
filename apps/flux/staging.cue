@if(staging)
package flux

staging: _base & {
	app:            "flux-staging"
	primary_region: "iad"
	custom_domains: ["staging.flux.gunk.dev"]

	http_service: {}
}
