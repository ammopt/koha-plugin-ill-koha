# Koha Interlibrary Loans Koha backend

This backend provides the ability to create Interlibrary Loan requests by searching other Koha instances.

## Getting Started

You should always pick the version closest to your Koha version. For example, if `24.05.*` is the newest
available version and you are on Koha `v24.11.00`, then you pick the latest `v24.05.*` version of the plugin.

## Installing

### Post 18.11

* Activate ILL by enabling the `ILLModule` system preference
* Update the koha configuration to set ILL backend_directory to point to `<backend_directory>/var/lib/koha/${INSTANCE}/plugins/Koha/Illbackends</backend_directory>`
* Download the latest _.kpz_ file from the [releases](https://gitlab.com/koha-community/plugins/koha-plugin-ill-koha/-/releases) page and install it as any other plugin following the general [plugin install instructions](https://wiki.koha-community.org/wiki/Koha_plugins).

### Prior to 18.11
* Create a directory in `Koha` called `Illbackends`, so you will end up with `Koha/Illbackends`
* Clone the repository into this directory, so you will end up with `Koha/Illbackends/koha-ill-koha`
* In the `koha-ill-koha` directory switch to the branch you wish to use
* Rename the `koha-ill-koha` directory to `Koha`
* Activate ILL by enabling the `ILLModule` system preference

## Configuration

### Post 18.11

The plugin configuration is an HTML text area in which a _YAML_ structure is pasted. The available options
are maintained on this document. Example:

```
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
### Prior to 18.11

Configuration required local changes to be done in the Base.pm file.
