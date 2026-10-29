@if(prod)
package valleyweb

prod: _base & {
	app:            "valley-web-prod"
	primary_region: "yyz"
	custom_domains: ["broken.dev", "www.broken.dev"]
}
