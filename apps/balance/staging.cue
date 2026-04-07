@if(staging)
package balance

staging: _base & {
	app:            "balance-staging"
	primary_region: "iad"
	custom_domains: ["staging.balance.gunk.dev"]

	http_service: {}
}
