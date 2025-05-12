# Koha Interlibrary Loans Koha backend

This backend provides the ability to create Interlibrary Loan requests by searching other Koha instances.

## Getting Started

You should always choose the version that is equal to or lower than your Koha version. For example:

| Koha version  | Plugin v19.6 | Plugin v24.5 | Plugin v25.5 |
|:--------------|:------------:|:------------:|:------------:|
| 22.11         | ✅           | ❌            | ❌           |
| 24.05         | ❌           | ✅            | ❌           |
| 24.11         | ❌           | ✅            | ❌           |
| 25.05         | ❌           | ❌            | ✅           |

## Installing

* Activate ILL by enabling the `ILLModule` system preference
* Update the koha configuration to set ILL backend_directory to point to `<backend_directory>/var/lib/koha/${INSTANCE}/plugins/Koha/Illbackends</backend_directory>`
* Download the latest _.kpz_ file from the [releases](https://gitlab.com/koha-community/plugins/koha-plugin-ill-koha/-/releases) page and install it as any other plugin following the general [plugin install instructions](https://wiki.koha-community.org/wiki/Koha_plugins).

## Configuration

### REST API

The default behavior is to utilize the configured z39.50 server as well as its configured ILS-DI endpoint.
However, if a 'rest_api_endpoint' if configured, the search will be performed using the REST API instead.

The YAML configuration may have both REST API or ILS-DI (default) interface servers.

### REST API example

```yaml
---
targets:
  RemoteKoha:
    rest_api_endpoint: https://kohaopacurl.com
    user: rest_user_name
    password: rest_user_pass
framework: ILL
```

Requires RemoteKoha to have `RESTBasicAuth` enabled.

### Z39.50 example

```yaml
targets:
  KOHA_1:
    ZID: 6   # ID of remote koha instance as configured as a z3950 target
    ILSDI: https://koha-instance-1.com/cgi-bin/koha/ilsdi.pl
    user: remote_koha_ill_username
    password: remote_koha_ill_userpassword
  KOHA_2:
    ZID: 7   # ID of remote koha instance as configured as a z3950 target
    ILSDI: https://koha-instance-2.com/cgi-bin/koha/ilsdi.pl
    user: remote_koha_ill_username
    password: remote_koha_ill_userpassword
framework: ILL
```

### IllLog syspref

The plugin makes use of the IllLog syspref to log various actions, including notices sent.
