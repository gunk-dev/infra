@if(prod)
package balance

prod: _base & {
	app:            "balance-prod"
	primary_region: "iad"
	custom_domains: ["balance.gunk.dev"]

	http_service: {}
}
