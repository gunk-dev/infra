@if(prod)
package flux

prod: _base & {
	app:            "flux-prod"
	primary_region: "iad"
	custom_domains: ["flux.gunk.dev"]

	http_service: {}
}
